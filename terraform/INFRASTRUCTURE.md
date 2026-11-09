# Demo3 infrastructure

Two private networks, one on AWS (management tools) and one on GCP (the application), joined by a VPN. Everything is created with Terraform.

|                   | AWS: management                      | GCP: application                                           |
| ----------------- | ------------------------------------ | ---------------------------------------------------------- |
| Purpose           | GitLab, SigNoz, GitLab runner        | Nginx, two Java app servers, PostgreSQL master and replica |
| Account / project | account of the team                  | project `demo3-team1`                                    |
| Region / zone     | `eu-central-1` / `eu-central-1a` | `europe-west3` / `europe-west3-a` and `-b`           |
| Network           | `10.10.0.0/16`                     | `10.20.0.0/16`                                           |

## Instances

All run Ubuntu 24.04 LTS, have encrypted disks, and have no public IP except Nginx.

| Instance            | Cloud | Role                                                | Type           | CPU / RAM       | Disks                   | Private IP             | Public IP                 |
| ------------------- | ----- | --------------------------------------------------- | -------------- | --------------- | ----------------------- | ---------------------- | ------------------------- |
| `demo3-nginx`     | GCP   | reverse proxy and load balancer, public entry point | e2-small       | 2 shared / 2 GB | 15 GB boot              | `10.20.0.2`          | `34.40.82.240` (static) |
| `demo3-app-1`     | GCP   | Java application, port 8080 (zone a)                | e2-medium      | 2 shared / 4 GB | 15 GB boot              | `10.20.1.2` (static) | none                      |
| `demo3-app-2`     | GCP   | Java application, port 8080 (zone b)                | e2-medium      | 2 shared / 4 GB | 15 GB boot              | `10.20.1.5` (static) | none                      |
| `demo3-db-master` | GCP   | PostgreSQL master                                   | e2-medium      | 2 shared / 4 GB | 15 GB boot + 20 GB data | `10.20.1.4` (static) | none                      |
| `demo3-db-slave`  | GCP   | PostgreSQL replica                                  | e2-medium      | 2 shared / 4 GB | 15 GB boot + 20 GB data | `10.20.1.3` (static) | none                      |
| `demo3-gitlab`    | AWS   | GitLab server                                       | m7i-flex.large | 2 / 8 GB        | 15 GB boot + 10 GB data | `10.10.0.224`        | none                      |
| `demo3-signoz`    | AWS   | SigNoz (monitoring)                                 | c7i-flex.large | 2 / 4 GB        | 15 GB boot + 10 GB data | `10.10.0.118`        | none                      |
| `demo3-runner`    | AWS   | GitLab runner, deploys the app                      | t3.small       | 2 / 2 GB        | 15 GB boot              | `10.10.0.223`        | none                      |

- **Static** addresses are reserved in GCP and do not change while the resource exists. Use them in configuration (JDBC URL, replication, DNS, the Pingdom check). The Nginx internal address and the AWS private addresses are assigned automatically: AWS keeps them across stop and start, but a recreated instance gets a new one.
- Data disks are separate from the VMs and survive VM replacement. They are mounted at `/data`, and the application directories are bind-mounted from there: `/var/lib/postgresql` (databases), `/etc/gitlab` and `/var/opt/gitlab` (GitLab), `/var/lib/docker/volumes` (SigNoz).
- GCP VMs are shielded VMs (secure boot, vTPM, integrity monitoring).

## Network

| Network           | Subnet  | CIDR             | Holds             |
| ----------------- | ------- | ---------------- | ----------------- |
| AWS `demo3-vpc` | private | `10.10.0.0/24` | all AWS instances |
| AWS `demo3-vpc` | public  | `10.10.1.0/24` | NAT gateway only  |
| GCP `demo3-vpc` | public  | `10.20.0.0/24` | Nginx             |
| GCP `demo3-vpc` | private | `10.20.1.0/24` | app and databases |

**Outbound internet** from private machines goes through a NAT: the AWS NAT gateway (`63.177.149.95`, use it for allowlists) and Cloud NAT on GCP. Nothing private has an inbound path from the internet. GCP VMs also reach Google APIs (Cloud Storage) privately.

**VPN.** An HA VPN with BGP: two connections with two tunnels each (4 tunnels), so one failed tunnel or gateway interface does not cut the link. Each side learns the other's subnets automatically, so there are no static routes. GCP gateway addresses: `34.157.57.92` and `35.220.19.142`.

## Allowed traffic

Everything not listed is blocked inbound. Outbound is open on GCP, and on AWS (all three security groups allow all outbound).

| From                                  | To                  | Port                 | Purpose                    | Enforced by                                                   |
| ------------------------------------- | ------------------- | -------------------- | -------------------------- | ------------------------------------------------------------- |
| Internet                              | Nginx               | TCP 80, 443          | public site, uptime checks | GCP firewall `allow-web-from-internet`                      |
| Nginx                                 | both app servers    | TCP 8080             | proxy and load balancing   | `allow-app-from-web`                                        |
| both app servers                      | db master and slave | TCP 5432             | PostgreSQL                 | `allow-db-from-app`                                         |
| db master / slave                     | each other          | TCP 5432             | replication                | `allow-db-replication`                                      |
| AWS network `10.10.0.0/16` (runner) | all GCP VMs         | TCP 22, ICMP         | SSH deployments            | `allow-ssh-from-management`, `allow-icmp-from-management` |
| Google IAP                            | all GCP VMs         | TCP 22               | team SSH                   | `allow-iap-ssh`                                             |
| GCP network `10.20.0.0/16`          | SigNoz              | TCP 4317, 4318       | OpenTelemetry (gRPC, HTTP) | AWS group `demo3-signoz-sg`                                 |
| AWS network `10.10.0.0/16`          | SigNoz              | TCP 4317, 4318, 8080 | telemetry and web UI       | `demo3-signoz-sg`                                           |
| runner                                | GitLab              | TCP 80, 443          | clone code, report jobs    | `demo3-gitlab-sg`                                           |

Not allowed: the internet reaching the app, the databases, GitLab or SigNoz; GCP reaching AWS on anything except the SigNoz ports; SSH from the internet to anything.

## How to get in

| Who           | Where                | How                                                                                                                                         |
| ------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Teammates     | AWS instances        | Session Manager: `aws ssm start-session --target <instance-id> --region eu-central-1`                                                     |
| Teammates     | GCP VMs              | `gcloud compute ssh <vm> --zone europe-west3-a --project demo3-team1 --tunnel-through-iap` (IAP tunnel and OS Login, your Google account) |
| Teammates     | start / stop GCP VMs | `gcloud compute instances start\|stop <vm> --zone europe-west3-a --project demo3-team1` (only `demo3-*` VMs)                             |
| GitLab runner | GCP VMs              | SSH over the VPN to the private IP, as the service account `demo3-deploy-sa` (OS Login, key-based), see below                             |
| GitLab runner | GCP APIs (Terraform) | as `demo3-terraform-sa`, through Workload Identity Federation, see below                                                                  |

**Runner to GCP VMs.** The runner connects with its private key `~/.ssh/runner_deploy`, as the OS Login user of `demo3-deploy-sa` (`sa_116687368623049818165`):

```bash
ssh -i ~/.ssh/runner_deploy sa_116687368623049818165@10.20.1.2
```

Use the VM's private IP: `10.20.1.2` (app-1), `10.20.1.5` (app-2), `10.20.1.4` (db master), `10.20.1.3` (db slave), `10.20.0.2` (nginx). A deployment has to go to both app servers. The account has no sudo (`deploy_can_sudo = false`).

**Runner Terraform access.** The runner has no GCP key. Its AWS role `demo3-runner` is trusted by a GCP identity pool (`demo3-aws`), and jobs swap that identity for short-lived tokens of `demo3-terraform-sa`. For this the runner needs a credentials file (no secrets in it) and `GOOGLE_APPLICATION_CREDENTIALS` pointing at it; jobs must use the shell executor. Setup steps for whoever manages the runner: `access-gcp/RUNNER_SETUP.md`. This covers the `application-gcp` root only.

There are no public SSH ports and no shared passwords. GCP VMs use OS Login, so ordinary SSH keys in instance metadata do not work.

## Access control (IAM)

**GCP** has one service account per VM role, so no VM uses the default account:

| Service account        | Used by          | Access                                                                                                                                                              |
| ---------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `demo3-nginx-sa`     | Nginx            | write logs and metrics                                                                                                                                              |
| `demo3-app-sa`       | both app servers | logs and metrics, read/write objects in the application bucket                                                                                                      |
| `demo3-db-sa`        | both DB VMs      | logs and metrics, read/write objects under `backups/` in the bucket                                                                                               |
| `demo3-deploy-sa`    | GitLab runner    | OS Login on the VMs, no other rights                                                                                                                                |
| `demo3-terraform-sa` | GitLab runner    | create and change the application infrastructure (`application-gcp` root). Reached without a key, through Workload Identity Federation from the runner's AWS role |

Teammates (listed in the `access-gcp` root) get IAP tunnel access, OS Login with sudo, instance viewer, and start/stop on the `demo3-*` VMs.

**AWS** has one instance role per machine (`demo3-gitlab`, `demo3-signoz`, `demo3-runner`) with Session Manager access only. The GitLab role can additionally read its repository sync secrets from SSM Parameter Store under `/demo3/gitlab-sync/`.

## Storage

One Cloud Storage bucket, `demo3-app-demo3-team1`, in `europe-west3`: application files and database backups. Versioning on, no public access, access only for the service accounts above.

## Terraform roots

Each root is separate, with its own state. Apply in this order:

| # | Root                | Creates                                                                                | State                                                         |
| - | ------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| 1 | `management-aws`  | AWS network, security groups, IAM, GitLab, SigNoz, runner                              | S3 `demo3-tfstate-mgmt-bucket`, `demo3/terraform.tfstate` |
| 2 | `application-gcp` | GCP network, firewall, IAM, bucket, the four VMs                                       | GCS `demo3-tfstate-gcp`, `demo3/application`              |
| 3 | `vpn`             | HA VPN, tunnels, BGP, route propagation                                                | S3, `demo3/vpn.tfstate`                                     |
| 4 | `access-gcp`      | team access, VM power rights, deploy and Terraform service accounts, runner federation | GCS, `demo3/access`                                         |

Each root has an `OVERVIEW.md` with the details of that part (`vpn`, `access-gcp`, `application-gcp`, `management-aws`).

## Good to know

- **Cost.** NAT gateways, two VPN connections and the running VMs bill by the hour. Stop the VMs when not in use, and run `terraform destroy` (in reverse order: `access-gcp`, `vpn`, then the other two) after the demo. A reserved external IP that is not attached to a running VM is billed.
- **Changing IPs or subnets** means replacing the VMs. Plan it.
- **Region changes on GCP:** the VPN learns routes per region (`europe-west3`). VMs in another region would need global routing on the VPC.
- **SigNoz** is reachable from GCP only when its collector is actually running; the network path is open either way.
- The VPN pre-shared keys are stored in the `vpn` state file. Keep that bucket private.
