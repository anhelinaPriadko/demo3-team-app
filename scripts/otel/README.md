# Demo 3 — OpenTelemetry package

## Coverage
- Host metrics on all six GCP VMs.
- Ubuntu system logs on all six VMs.
- Nginx access/error logs and Nginx-specific metrics via exporter scrape at `127.0.0.1:9113`.
- PostgreSQL logs and SQL/database metrics via exporter scrape at `127.0.0.1:9187` on master and replica.
- Java Agent integration for Spring Boot on both app VMs; traces and JVM metrics export directly to SigNoz OTLP/HTTP `10.10.0.118:4318`.

## VM/config map
| VM | Config | Private IP |
|---|---|---|
| demo3-nginx | configs/nginx.yaml | 10.20.0.2 |
| demo3-app-1 | configs/app.yaml | 10.20.1.2 |
| demo3-app-2 | configs/app.yaml | 10.20.1.5 |
| demo3-db-master | configs/db-master.yaml | 10.20.1.4 |
| demo3-db-slave | configs/db-slave.yaml | 10.20.1.3 |
| demo3-db-witness | configs/witness.yaml | Terraform output `private_ips` |

## Deploy Collector
Copy folder to each VM, then:
```bash
sudo ./scripts/install.sh
sudo ./scripts/configure.sh nginx demo3-nginx 10.20.0.2
sudo ./scripts/verify.sh
```
Use role/IP from table. Supported roles: nginx, app, db-master, db-slave, witness. Collector version defaults to 0.165.0.

## Exporter prerequisites
Nginx exporter must listen only on `127.0.0.1:9113`; PostgreSQL exporter on each DB VM only on `127.0.0.1:9187`. See `exporters/` for owner instructions. Collector configs already scrape these endpoints but cannot install/configure service-specific exporters without Nginx/DB owner input and credentials.

## Java Agent
See `integration/README.md`. The snippet proposes version 2.33.1; app owner must verify Java runtime compatibility and approve. App container sends OTLP/HTTP directly to SigNoz on 4318 over VPN; do not set localhost.

## Team dependencies
SigNoz must listen on 4317 and 4318; VPN/BGP and SG must permit both ports from GCP. `demo3-deploy-sa` defaults to no sudo, but install/configure requires root. GitLab pipeline currently has Terraform stages only. Witness IP is dynamic. Confirm PostgreSQL log path/permissions. Plaintext OTLP is used only inside private VPN; TLS/mTLS requires team decision.

## Validation
`bash -n scripts/*.sh`; `configure.sh` runs `otelcol-contrib validate` on the target VM before installing config. `verify.sh` checks service and TCP 4317. Actual telemetry must be confirmed in SigNoz. No Terraform, IAM, firewall, VPN, data disk, Nginx reverse-proxy or database cluster changes are performed.
