# Demo 3 — OpenTelemetry team hand-off

## Prepared
- Collector Contrib install/configure/verify/uninstall scripts.
- Host metrics and Ubuntu system logs for all six GCP VMs.
- Nginx access/error logs plus Prometheus scrape config for exporter `127.0.0.1:9113`.
- PostgreSQL file logs plus Prometheus scrape config for exporter `127.0.0.1:9187` on master and replica.
- Java Agent Dockerfile snippet and environment example for Spring Boot app.

## Infrastructure / Yaroslav
- [ ] Start SigNoz; confirm OTLP/gRPC 4317 AND OTLP/HTTP 4318 on `10.10.0.118`.
- [ ] Confirm VPN/BGP routes between GCP `10.20.0.0/16` and AWS `10.10.0.0/16`.
- [ ] Allow TCP 4317/4318 from GCP CIDR in SigNoz security group.
- [ ] Resolve sudo: `demo3-deploy-sa` currently defaults to `deploy_can_sudo=false`; apt, `/etc`, systemd require root. Grant controlled sudo or have admin execute scripts.
- [ ] Finish Runner and deployment job; current GitLab CI has Terraform stages only.
- [ ] Provide dynamic witness private IP from Terraform output `private_ips`.
- [ ] Confirm plaintext OTLP inside VPN is acceptable; otherwise provide CA/certs and TLS/mTLS requirements.

## Nginx owner
- [ ] Enable localhost-only Nginx `stub_status`.
- [ ] Install/pin nginx-prometheus-exporter; bind `127.0.0.1:9113`; scrape local stub_status.
- [ ] Verify `curl http://127.0.0.1:9113/metrics`.
- [ ] Ensure Collector service user can read Nginx access/error logs.

## Database owner
- [ ] Confirm PostgreSQL writes logs to `/var/log/postgresql/*.log`; update configs if not.
- [ ] Install/pin postgres_exporter on master and replica, bind `127.0.0.1:9187`.
- [ ] Create least-privilege monitoring DB role and secure local credentials; never commit passwords.
- [ ] Verify `curl http://127.0.0.1:9187/metrics` on both DB VMs.
- [ ] Ensure Collector service user can read PostgreSQL log files.
- [ ] Patroni metrics are not included; provide endpoint/port/auth/TLS if these are required.

## Application owner / Angelina
- [ ] Add `integration/java-agent.Dockerfile.snippet` to final/runtime stage of existing Dockerfile.
- [ ] Merge `java-agent.env.example` into existing app service environment; target SigNoz `10.10.0.118:4318`, not localhost.
- [ ] Confirm Java runtime compatibility and approve/pin agent version 2.33.1.
- [ ] Rebuild/publish image and redeploy both `demo3-app-1` and `demo3-app-2`.
- [ ] Verify traces and JVM metrics in SigNoz. App log export remains separate.

## VM map
| VM | Role | Private IP |
|---|---|---|
| demo3-nginx | nginx | 10.20.0.2 |
| demo3-app-1 | app | 10.20.1.2 |
| demo3-app-2 | app | 10.20.1.5 |
| demo3-db-master | db-master | 10.20.1.4 |
| demo3-db-slave | db-slave | 10.20.1.3 |
| demo3-db-witness | witness | Terraform output `private_ips` |

Run on each VM after copying this folder:
```bash
sudo ./scripts/install.sh
sudo ./scripts/configure.sh <role> <vm-name> <private-ip>
sudo ./scripts/verify.sh
```

No Terraform/IAM/VPN/firewall/data-disk changes are made. No Patroni or etcd metrics are included in this scope. OTLP exporter uses plaintext within the private VPN only.
