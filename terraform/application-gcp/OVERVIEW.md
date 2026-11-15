# application-gcp

Terraform root for the application environment on Google Cloud: network, firewall, a storage bucket and six virtual machines (Nginx, two application servers, a PostgreSQL master and replica, and an etcd witness for the database cluster). All resources are prefixed `demo3-` (`name_prefix`). Region `europe-west3`; the VMs are in zone `europe-west3-a`, except `demo3-app-2` and `demo3-db-witness` in `europe-west3-b`.

State: GCS bucket `demo3-tfstate-gcp`, prefix `demo3/application`. Provider `hashicorp/google ~> 7.0`.

## Role in the platform

This root is applied after `access-gcp`, which creates the VM service accounts, and before `vpn`, which reads its outputs. It is the part of the infrastructure that the GitLab runner can manage through the `demo3-terraform-sa` service account (see `access-gcp`).

## Structure

`main.tf` wires four modules. All VM roles share one generic `compute` module.

| Module | Creates |
|---|---|
| `network` | custom-mode VPC, public and private subnet, Cloud Router and Cloud NAT for the private subnet |
| `firewall` | tag-based ingress rules (see Allowed traffic) |
| `storage` | the application bucket and its IAM bindings for the app and db service accounts |
| `compute` | one VM with boot disk, optional data disk, optional reserved internal and external address, shielded VM and OS Login settings. Called for nginx, each app server (`for_each` over `app_instances`), db master, db slave and the witness |

## Network

| Resource | Value |
|---|---|
| VPC | `demo3-vpc`, custom mode, `10.20.0.0/16` |
| Public subnet | `10.20.0.0/24` (Nginx) |
| Private subnet | `10.20.1.0/24` (app servers, databases, witness), Private Google Access on |
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
| `demo3-db-witness` | e2-small | private | `etcd` | internal address reserved at first apply (see output `private_ips`), zone b | none |

**Application group.** The app servers are defined by the `app_instances` map (name, zone, internal IP). Adding an entry adds a server; the Terraform output `app_upstream` lists the matching Nginx `upstream` lines. Nginx distributes requests over the group, and the servers sit in different zones.

**Addresses.** Static internal addresses are reserved as separate resources and stay the same while those resources exist. The app addresses are pinned in `app_instances`. The database addresses were assigned by GCP at first apply. The Nginx internal address is not reserved and may change if the VM is recreated.

**Database cluster and witness.** The master and the replica are meant to run as a self-recovering PostgreSQL cluster managed by Patroni, which keeps its leader election in etcd. Etcd needs an odd number of members to keep a quorum, so `demo3-db-witness` is the third member next to the two database VMs. It runs etcd only, has no data disk and carries no PostgreSQL. It is placed in a different zone (`witness_zone`) from the database VMs, so that the loss of one zone leaves two of the three members. Terraform creates only the VM, the network rules and the service account; installing and configuring etcd and Patroni on the three machines is separate. Etcd and Patroni use fixed member addresses, so the reserved internal addresses are used in their configuration.

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
| `allow-etcd-patroni` | tags `db`, `etcd` | tags `db`, `etcd` | TCP 2379 (etcd client), 2380 (etcd peer), 8008 (Patroni REST API) |
| `allow-iap-ssh` | `35.235.240.0/20` (IAP) | all VMs | TCP 22 |
| `allow-ssh-from-management` | `management_cidr` (`10.10.0.0/16`, AWS over the VPN) | all VMs | TCP 22 |
| `allow-icmp-from-management` | `management_cidr` | all VMs | ICMP |

The two `management` rules exist only when `management_cidr` is set. No rule opens the application or the databases to the internet. SSH is possible through IAP and from the AWS network over the VPN.

## IAM

Each VM role has its own service account, so the default Compute Engine account is not used. The accounts and their project roles are created in `access-gcp`; this root reads them with the `google_service_account` data source, attaches them to the VMs and grants the bucket permissions.

| Service account | Used by | Access |
|---|---|---|
| `demo3-nginx-sa` | Nginx | none |
| `demo3-app-sa` | both app servers | `storage.objectAdmin` on the bucket |
| `demo3-db-sa` | both DB VMs | `storage.objectAdmin` on the bucket |
| `demo3-etcd-sa` | etcd witness | none |

The accounts have no project roles; logs and metrics go to SigNoz. Bucket permissions are granted on the bucket, not project-wide. `migrations.tf` holds the `moved` and `removed` blocks for the move of the service accounts to `access-gcp`; it can be deleted after that apply.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `project_id` | none | GCP project ID |
| `region`, `zone` | `europe-west3`, `europe-west3-a` | location; `zone` is used by Nginx and the databases |
| `witness_zone` | `europe-west3-b` | zone of the etcd witness; keep it different from the database zone |
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
