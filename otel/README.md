# Demo 3 — OpenTelemetry

This folder is the source of the deployment scripts used by GitLab. The GitLab Runner copies it to `/tmp/otel/` on the target GCP VM and runs `scripts/deploy.sh`.

## Layout

- `configs/`: Collector configurations per VM role.
- `scripts/install.sh`: installs the Collector and the role-specific exporters.
- `scripts/configure.sh`: configures the exporters, log access, the Collector configuration and systemd.
- `scripts/verify.sh`: checks the configuration, the service, OTLP connectivity and the local endpoints.
- `scripts/deploy.sh`: runs install → configure → verify in sequence.
- `scripts/uninstall.sh`: removes the Collector and the installed exporter binaries/services.

## Roles and nodes

| Role | VM |
| --- | --- |
| `nginx` | `demo3-nginx` |
| `app` | `demo3-app-1`, `demo3-app-2` |
| `db-master` | `demo3-db-master` |
| `db-slave` | `demo3-db-slave` |
| `witness` | `demo3-db-witness` |

## Running

On the VM, after copying the `otel/` folder to `/tmp/otel/`:

```bash
sudo bash /tmp/otel/scripts/deploy.sh nginx demo3-nginx
```

Replace the role and hostname according to the table.

## What is collected

- All VMs: host metrics (CPU, disk, load, filesystem, memory, network, paging, processes), including `system.cpu.utilization`, `system.memory.utilization` and `system.filesystem.utilization` (disabled by default in hostmetrics, enabled explicitly here), and system logs. Pseudo file systems and bind mounts are excluded so that disks are not counted twice.
- Nginx VM: Nginx access/error logs (with severity: 5xx → ERROR, 4xx → WARN; attributes `http_status`, `http_method`, `http_path`, `client_ip`) and metrics through the Nginx Prometheus Exporter.
- App VMs: host metrics and system logs, `service.name = demo3-app-host`. Application traces, metrics and logs are sent by the Java Agent directly to SigNoz over OTLP/HTTP (`service.name = demo3-java-app`).
- DB master/replica: PostgreSQL logs (`service.name = postgresql`), Patroni and etcd logs from journald (`service.name = patroni` / `etcd`), PostgreSQL exporter metrics, Patroni `/metrics`, etcd `/metrics`. The current role of a node is the `patroni_primary` metric (1 = leader), not a static label.
- Witness: host metrics, system logs, etcd logs from journald and etcd `/metrics`.

## Endpoints

- SigNoz OTLP/gRPC: `10.10.0.118:4317`
- Nginx stub_status: `127.0.0.1:8081/stub_status`
- Nginx exporter: `127.0.0.1:9113/metrics`
- PostgreSQL exporter: `127.0.0.1:9187/metrics` (unix socket, peer auth, no password)
- Patroni: `127.0.0.1:8008/metrics`
- etcd: `127.0.0.1:2379/metrics` (client listener, no separate metrics port needed)

## Prerequisites

- Ubuntu 24.04, systemd, outbound HTTPS to GitHub, persistent journal (`/var/log/journal`).
- The deployment must run as root/sudo.
- On the Nginx VM, Nginx must be installed and active.
- On the DB VMs, Patroni (or `postgresql.service`) must be running. `/etc/patroni/config.yml` on **both** DB nodes needs:

  ```yaml
  postgresql:
    pg_hba:
      - local all postgres peer
      - local all otel_monitor peer map=otel
      - host replication replicator 10.20.1.0/24 scram-sha-256
      - host all all 10.20.1.0/24 scram-sha-256
      - host all all 127.0.0.1/32 scram-sha-256
    pg_ident:
      - otel postgres_exporter otel_monitor
  ```

  and, for PostgreSQL file logs (`patronictl edit-config`): `logging_collector: on`, `log_directory: /var/log/postgresql`. Both are already part of the data tier scripts in `postgres-automation/scripts/`.
- Deploy to the current leader first (the `otel_monitor` role is created only there and replicated).
- Patroni and etcd must be installed on the DB VMs by the separate infrastructure deployment. This kit does not install them.
- Patroni must expose HTTP `/metrics` on localhost:8008.
- etcd must listen on the client URL `http://127.0.0.1:2379` (already in the data tier scripts).
- On the app VMs, the Java Agent is configured in the Docker image and the application deployment, not by these host scripts.
- SigNoz must accept OTLP/gRPC on `10.10.0.118:4317`, and the GCP → AWS network route must work.
- The OTLP exporter uses `tls.insecure: true`, so the endpoint must only be reachable through the private VPN.

## Rerunning and removal

The scripts are safe to rerun: the Nginx config and services are overwritten in a controlled way; the PostgreSQL exporter has no password: the OS user `postgres_exporter` is mapped to the `otel_monitor` role through `pg_ident`. `uninstall.sh` removes the Collector and the exporter services/binaries, but does not remove the monitoring role from PostgreSQL automatically.

## Verification scope

All YAML files and Bash scripts are syntax-checked locally. Real package compatibility, running on the six VMs, endpoint access and actual telemetry delivery must be verified during deployment in your infrastructure.
