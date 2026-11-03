# GCP application infrastructure: overview

Region `europe-west3`, zone `europe-west3-a`. All resources are prefixed `demo3-`.

## Network

| Resource | Value |
|---|---|
| VPC | `demo3-vpc` (custom mode, `10.20.0.0/16` space) |
| Public subnet | `10.20.0.0/24` (Nginx) |
| Private subnet | `10.20.1.0/24` (app, databases), Private Google Access on |
| Outbound for private VMs | Cloud Router + Cloud NAT (private subnet only) |

## Compute

All VMs: Ubuntu 24.04 LTS, shielded VM (secure boot, vTPM, integrity monitoring), OS Login, boot disk 15 GiB `pd-balanced`.

| VM | Type | Subnet | Tag | IPs | Data disk |
|---|---|---|---|---|---|
| `demo3-nginx` | e2-small | public | `web` | static external + ephemeral internal | none |
| `demo3-app` | e2-medium | private | `app` | static internal | none |
| `demo3-db-master` | e2-medium | private | `db` | static internal | 20 GiB `pd-balanced`, mounted at `/data` |
| `demo3-db-slave` | e2-medium | private | `db` | static internal | 20 GiB `pd-balanced`, mounted at `/data` |

The DB data disks are separate resources and survive VM replacement. PostgreSQL's `/var/lib/postgresql` is bind-mounted from `/data/postgresql`.

## Storage

One bucket, `demo3-app-<project_id>`, in `europe-west3`: uniform access, public access prevention enforced, versioning on, `force_destroy` on (demo).

## Allowed traffic

Ingress is denied by default. Egress is open.

| Rule | From | To | Ports |
|---|---|---|---|
| `allow-web-from-internet` | `0.0.0.0/0` | `web` | TCP 80, 443 |
| `allow-app-from-web` | `web` | `app` | TCP 8080 |
| `allow-db-from-app` | `app` | `db` | TCP 5432 |
| `allow-db-replication` | `db` | `db` | TCP 5432 |
| `allow-iap-ssh` | `35.235.240.0/20` (IAP) | all VMs | TCP 22 |

No rule opens the app or the databases to the internet. SSH only works through IAP (`gcloud compute ssh <vm> --tunnel-through-iap`).

## IAM

One service account per role, so the default Compute Engine account is not used.

| Service account | Used by | Access |
|---|---|---|
| `demo3-nginx-sa` | Nginx | log writer, metric writer |
| `demo3-app-sa` | app | log writer, metric writer, `storage.objectAdmin` on the bucket |
| `demo3-db-sa` | both DB VMs | log writer, metric writer, `storage.objectUser` on the bucket, limited by condition to `backups/` |

Bucket access is granted on the bucket, not project-wide. The `backups/` condition means the DB account cannot list the bucket.

Not included yet: IAP and OS Login roles for the team (`roles/iap.tunnelResourceAccessor`, `roles/compute.osLogin`), and everything VPN-related.
