# application-gcp

Terraform root for the application environment on Google Cloud: network, firewall, service accounts, a storage bucket and five virtual machines (Nginx, two application servers, a PostgreSQL master and replica). All resources are prefixed `demo3-` (`name_prefix`). Region `europe-west3`; the VMs are in zone `europe-west3-a`, except `demo3-app-2` in `europe-west3-b`.

State: GCS bucket `demo3-tfstate-gcp`, prefix `demo3/application`. Provider `hashicorp/google ~> 7.0`.

## Role in the platform

This root is applied before `vpn` and `access-gcp`, which read its outputs and use its service accounts. It is the part of the infrastructure that the GitLab runner can manage through the `demo3-terraform-sa` service account (see `access-gcp`).

## Structure

`main.tf` wires five modules. The three VM roles share one generic `compute` module.

| Module | Creates |
|---|---|
| `network` | custom-mode VPC, public and private subnet, Cloud Router and Cloud NAT for the private subnet |
| `firewall` | tag-based ingress rules (see Allowed traffic) |
| `iam` | one service account per VM role (nginx, app, db), their project roles and bucket permissions |
| `storage` | the application bucket |
| `compute` | one VM with boot disk, optional data disk, optional reserved internal and external address, shielded VM and OS Login settings. Called for nginx, each app server (`for_each` over `app_instances`), db master and db slave |

## Network

| Resource | Value |
|---|---|
| VPC | `demo3-vpc`, custom mode, `10.20.0.0/16` |
| Public subnet | `10.20.0.0/24` (Nginx) |
| Private subnet | `10.20.1.0/24` (app servers, databases), Private Google Access on |
| Outbound for private VMs | Cloud Router and Cloud NAT, private subnet only |

## Compute

All VMs run Ubuntu 24.04 LTS as shielded VMs (secure boot, vTPM, integrity monitoring) with OS Login enabled and a 15 GiB `pd-balanced` boot disk. Only Nginx has a public address.

| VM | Type | Subnet | Tag | Addresses | Data disk |
|---|---|---|---|---|---|
| `demo3-nginx` | e2-small | public | `web` | external `34.40.82.240` (static), internal `10.20.0.2` (ephemeral) | none |
| `demo3-app-1` | e2-medium | private | `app` | internal `10.20.1.2` (static), zone a | none |
| `demo3-app-2` | e2-medium | private | `app` | internal `10.20.1.5` (static), zone b | none |
| `demo3-db-master` | e2-medium | private | `db` | internal `10.20.1.4` (static) | 20 GiB `pd-balanced`, mounted at `/data` |
| `demo3-db-slave` | e2-medium | private | `db` | internal `10.20.1.3` (static) | 20 GiB `pd-balanced`, mounted at `/data` |

**Application group.** The app servers are defined by the `app_instances` map (name, zone, internal IP). Adding an entry adds a server; the Terraform output `app_upstream` lists the matching Nginx `upstream` lines. Nginx distributes requests over the group, and the servers sit in different zones.

**Addresses.** Static internal addresses are reserved as separate resources and stay the same while those resources exist. The app addresses are pinned in `app_instances`. The database addresses were assigned by GCP at first apply. The Nginx internal address is not reserved and may change if the VM is recreated.

**Data disks.** The database data disks are separate resources and survive VM replacement. A startup script mounts them at `/data` through `/dev/disk/by-id/google-data`, formats a disk only when it is blank, and bind-mounts `/data/postgresql` to `/var/lib/postgresql`.

## Storage

One bucket, `demo3-app-<project_id>`, in `europe-west3`: uniform bucket-level access, public access prevention enforced, versioning on, `force_destroy` on.

## Allowed traffic

Ingress is denied by default. Egress is open.

| Rule | Source | Target | Ports |
|---|---|---|---|
| `allow-web-from-internet` | `0.0.0.0/0` | tag `web` | TCP 80, 443 |
| `allow-app-from-web` | tag `web` | tag `app` | TCP 8080 (`app_port`) |
| `allow-db-from-app` | tag `app` | tag `db` | TCP 5432 |
| `allow-db-replication` | tag `db` | tag `db` | TCP 5432 |
| `allow-iap-ssh` | `35.235.240.0/20` (IAP) | all VMs | TCP 22 |
| `allow-ssh-from-management` | `management_cidr` (`10.10.0.0/16`, AWS over the VPN) | all VMs | TCP 22 |
| `allow-icmp-from-management` | `management_cidr` | all VMs | ICMP |

The two `management` rules exist only when `management_cidr` is set. No rule opens the application or the databases to the internet. SSH is possible through IAP and from the AWS network over the VPN.

## IAM

Each VM role has its own service account, so the default Compute Engine account is not used.

| Service account | Used by | Access |
|---|---|---|
| `demo3-nginx-sa` | Nginx | log writer, metric writer |
| `demo3-app-sa` | both app servers | log writer, metric writer, `storage.objectAdmin` on the bucket |
| `demo3-db-sa` | both DB VMs | log writer, metric writer, `storage.objectUser` on the bucket, restricted by condition to the `backups/` prefix |

Bucket permissions are granted on the bucket, not project-wide. Because of the `backups/` condition, the DB account cannot list the bucket.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `project_id` | none | GCP project ID |
| `region`, `zone` | `europe-west3`, `europe-west3-a` | location; `zone` is used by Nginx and the databases |
| `name_prefix` | `demo3` | prefix for all resources |
| `public_subnet_cidr`, `private_subnet_cidr` | `10.20.0.0/24`, `10.20.1.0/24` | subnets |
| `app_port` | `8080` | application port opened from Nginx |
| `app_instances` | `app-1` (zone a, `10.20.1.2`), `app-2` (zone b, `10.20.1.5`) | the application group |
| `management_cidr` | `10.10.0.0/16` | network allowed to SSH in; `null` disables the two rules |
| `db_data_disk_size` | `20` | GiB per database data disk |

## Outputs

`instances` (name, zone, private and public IP of every VM), `app_upstream` (Nginx upstream lines), the `gcloud` commands to connect through IAP, and the values the other roots consume: `project_id`, `region`, `network_name`, `network_self_link` and the subnet CIDRs.

## Notes

- Changing an address or a subnet replaces the VMs that use it.
- Routes learned over the VPN apply to the VPN's region only, because the VPC uses regional routing.
- The bucket and the VMs are removed by `terraform destroy`; the database data disks go with them.
