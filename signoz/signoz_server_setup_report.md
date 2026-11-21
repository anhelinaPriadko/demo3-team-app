# SigNoz Server — completed work and configuration

**Recorded on:** 19 November 2026 (sections 12–16: 21 November 2026)\
**Server:** `demo3-signoz`\
**Private IP address:** `10.10.0.118`\
**Cloud provider:** AWS\
**Region / Availability Zone:** `eu-central-1` / `eu-central-1a`\
**OS:** Ubuntu 24.04.5 LTS (x86_64)

------------------------------------------------------------------------

## 1. Purpose

SigNoz is deployed on this server to receive, store and display telemetry
for Demo 3 — Observability & Reliability.

SigNoz runs on a dedicated EC2 VM in AWS. The expected telemetry sources
are OpenTelemetry Collectors on the GCP infrastructure. The AWS network
range is `10.10.0.0/16`, GCP is `10.20.0.0/16`.

## 2. EC2 infrastructure and disks

### EC2

| Parameter | Value |
| --- | --- |
| Name | `demo3-signoz` |
| Instance ID | `i-054d48c41c4174ce6` |
| Instance type | `c7i-flex.large` |
| Private IP address | `10.10.0.118` |
| Region | `eu-central-1` |
| Availability Zone | `eu-central-1a` |
| OS | Ubuntu 24.04.5 LTS |
| CPU | 2 vCPU |
| RAM | about 3.7 GiB |

No public IPv4 address is configured for the server. Administrative
access goes through AWS Systems Manager Session Manager.

### EBS

The server has a root disk and an additional EBS disk for Docker volumes
and SigNoz data.

| Parameter | Root disk | Data disk |
| --- | --- | --- |
| Size | 15 GiB | 10 GiB |
| Device | root volume | `/dev/nvme1n1` |
| File system | ext4 | ext4 |
| Mount point | `/` | `/data` |
| Data disk type | — | gp3 |

The additional EBS volume in AWS is named `demo3-signoz-data`, ID
`vol-055b543e582bbdcf6`.

Disk state at the time of the check:

- `/`: 14 GiB of usable file system space, about 6.5 GiB used.
- `/data`: 9.8 GiB, about 297 MiB used, about 9 GiB free.

### Docker volume persistence

Docker volumes are moved to the additional disk with a bind mount:

``` fstab
LABEL=data /data ext4 defaults,nofail 0 2
/data/docker-volumes /var/lib/docker/volumes none bind,nofail,x-systemd.requires-mounts-for=/data 0 0
```

Verified with:

``` bash
findmnt /data
findmnt /var/lib/docker/volumes
df -h / /data
```

Actual result:

- `/data` is mounted from `/dev/nvme1n1`.
- `/var/lib/docker/volumes` is mounted from
    `/dev/nvme1n1[/docker-volumes]`.
- `/data/docker-volumes` held about 295 MiB of data at the time of the
    check.

Main Docker volumes:

- `signoz-metastore-postgres-0-data`: PostgreSQL data.
- `signoz-telemetrykeeper-0-data`: ClickHouse Keeper data.
- `signoz-telemetrystore-0-0-data`: ClickHouse data.
- `signoz-telemetrystore-user-scripts`: volume for service scripts.

Docker also has two volumes with anonymous long identifiers. Their
purpose was not determined; they should not be deleted without further
investigation.

## 3. Installed software

Installed on the server:

- Docker Engine `29.1.0`.
- Docker Compose `v5.8.0`.
- Docker Buildx and containerd.
- Foundry CLI `v0.5.0`.
- SigNoz `v0.151.0` (enterprise-variant image).

Foundry was installed with the official SigNoz installation script. The
installation configuration is in `/opt/signoz/casting.yaml`:

``` yaml
apiVersion: v1alpha1
kind: Installation
metadata:
  name: signoz

spec:
  deployment:
    flavor: compose
    mode: docker
```

Foundry generated the Compose configuration and the Ingester
configuration. Main Compose file:

``` text
/opt/signoz/pours/deployment/compose.yaml
```

Additional Ingester files:

``` text
/opt/signoz/pours/deployment/ingester/ingester.yaml
/opt/signoz/pours/deployment/ingester/opamp.yaml
```

The Compose configuration was validated with
`docker compose ... config --quiet`, after which the services were
started in detached mode.

## 4. SigNoz containers

Main containers:

| Container | Purpose | Recorded state |
| --- | --- | --- |
| `signoz-signoz-0` | SigNoz UI and API | Up, healthy |
| `signoz-ingester-1` | OpenTelemetry Collector / ingestion | Up |
| `signoz-telemetrystore-clickhouse-0-0` | ClickHouse telemetry storage | Up, healthy |
| `signoz-telemetrykeeper-clickhousekeeper-0` | ClickHouse Keeper | Up, healthy |
| `signoz-metastore-postgres-0` | PostgreSQL metadata store | Up, healthy |

Additional one-off containers:

- `signoz-telemetrystore-clickhouse-user-scripts`: finished with status
    `Exited (0)`.
- `signoz-telemetrystore-migrator`: finished with status `Exited (0)`.

`Exited (0)` for these service jobs means successful completion, not an
error.

### Automatic start

Checked:

``` bash
systemctl is-enabled docker
systemctl is-active docker
```

Result: the Docker service is `enabled` and `active`.

The Docker restart policy was checked for the main long-running
containers. Value:

``` text
unless-stopped
```

This is set for SigNoz, Ingester, ClickHouse, PostgreSQL and ClickHouse
Keeper.

The `/data` mount and the Docker volumes bind mount are in `/etc/fstab`.
Actual recovery after a VM reboot has not been tested.

## 5. Network and ports

The server is in the private AWS network `10.10.0.0/16`. The UI is
accessed from a workstation through AWS SSM port forwarding.

### Published ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| `8080` | TCP/HTTP | SigNoz UI |
| `4317` | TCP/gRPC | OTLP gRPC receiver |
| `4318` | TCP/HTTP | OTLP HTTP receiver |

The Ingester configuration defines:

``` yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

The metrics pipeline includes:

- receiver: `otlp`;
- processors: `filter/drop_stale`, `batch`;
- exporters: `signozclickhousemetrics`, `signozmeter`,
    `metadataexporter`.

### Security Group

Verified inbound rules of the Security Group `demo3-signoz-sg`:

| Port | Protocol | Source | Purpose |
| --- | --- | --- | --- |
| 8080 | TCP | `10.10.0.0/16` | UI access from the AWS VPC |
| 4318 | TCP | `10.10.0.0/16` | OTLP HTTP from the AWS VPC |
| 4318 | TCP | `10.20.0.0/16` | OTLP HTTP from GCP |
| 4317 | TCP | `10.10.0.0/16` | OTLP gRPC from the AWS VPC |
| 4317 | TCP | `10.20.0.0/16` | OTLP gRPC from GCP |

Ports `4317`, `4318` and `8080` were confirmed to be listening on the
host interfaces. For `4317`, a TCP connection to localhost was also
confirmed.

The Security Group rules alone do not prove end-to-end network
reachability from GCP. The actual connection over VPN/BGP has to be
verified during the integration with the GCP Collectors.

### UI access through SSM

Local access to the UI uses SSM port forwarding:

``` powershell
aws ssm start-session `
  --target i-054d48c41c4174ce6 `
  --region eu-central-1 `
  --document-name AWS-StartPortForwardingSession `
  --parameters portNumber=8080,localPortNumber=18080
```

Once the session is established, the UI is available at:

``` text
http://localhost:18080
```

The PowerShell window with the active SSM session must stay open while
the UI is in use.

## 6. Initial SigNoz registration

The administrator was registered through the SigNoz UI.

After registration:

- the organization was created successfully;
- login works;
- the UI opens through SSM port forwarding;
- the logs show successful HTTP responses for registration and session
    creation.

Credentials are not stored in this documentation.

## 7. Telemetry ingestion check

### OTLP HTTP — verified end to end

A test OTLP JSON payload was created with:

- `service.name = demo3-otlp-smoke-test`;
- metric name `demo3_signoz_test`;
- type `gauge`;
- value `42.0`.

The request was sent locally to the Ingester:

``` bash
curl -i --max-time 10 \
  -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/otlp-test.json
```

Response:

``` text
HTTP/1.1 200 OK
{"partialSuccess":{}}
```

No `error` or `failed` messages were found in the Ingester logs for the
checked interval.

`demo3_signoz_test` was found in the SigNoz UI Metrics Explorer. The UI
showed:

- Samples: `1`;
- Time Series: `1 total – 1 active`;
- Metric Type: `GAUGE`;
- `service.name`: `demo3-otlp-smoke-test`;
- Last received: about 2 minutes before the screenshot.

This confirms OTLP HTTP ingestion, metric processing and display in the
SigNoz UI.

### OTLP gRPC — partially verified

Confirmed:

- the receiver is configured on `0.0.0.0:4317`;
- the host listens on `0.0.0.0:4317` and `[::]:4317`;
- a TCP connection to `127.0.0.1:4317` succeeds.

For an additional check, `grpcurl` was run in a temporary Docker
container. `grpcurl list` returned:

``` text
server does not support the reflection API
```

An attempt to call the OTLP Export RPC with `grpcurl` also failed,
because the client had no service descriptor and the server does not
support reflection.

This does not prove that the OTLP gRPC receiver is broken: gRPC
reflection is not required for OTLP. However, actual ingestion of an
OTLP gRPC payload has not been confirmed.

**Next check:** when the GCP OpenTelemetry Collector is connected, send
a test metric over OTLP gRPC to `10.10.0.118:4317` and confirm that it
appears in the SigNoz UI.

## 8. Server resource monitoring

Recorded during the check:

| Resource | Value |
| --- | --- |
| RAM total | 3.7 GiB |
| RAM used | 1.3 GiB |
| RAM available | 2.4 GiB |
| CPU | 2 vCPU |
| Load average | `0.05, 0.11, 0.09` |
| Root disk usage | 48% |
| `/data` usage | 4% |

Approximate container RAM usage at the time of `docker stats`:

| Container | RAM |
| --- | --- |
| ClickHouse | 646.8 MiB |
| Ingester | 147.9 MiB |
| ClickHouse Keeper | 108.9 MiB |
| PostgreSQL | 38.07 MiB |
| SigNoz | 35.38 MiB |

Additional checks:

- `/proc/pressure/memory`: `avg10`, `avg60`, `avg300` were all `0.00`;
- the kernel journal for the last two hours had no OOM messages or
    processes killed because of low memory;
- the Docker memory limit for SigNoz and Ingester returned `0`, meaning
    no hard memory limit is set.

There are currently no signs of memory pressure. However, 3.7 GiB of
RAM is a limited resource for collecting metrics, logs and traces from
all VMs. Usage has to be reassessed after the real collectors are
connected. If needed, consider increasing RAM, for example to 8 GiB,
subject to the budget and team approval.

## 9. Backups

Additional EBS volume:

- ID: `vol-055b543e582bbdcf6`;
- Name: `demo3-signoz-data`;
- Size: 10 GiB;
- Type: gp3;
- State: In-use;
- AZ: `eu-central-1a`.

Snapshots could not be checked in the AWS Console: the IAM user
`demo3-observability-user` lacks the `ec2:DescribeSnapshots`
permission.

Therefore, whether backups exist has not been established.

To finish this check, the AWS administrator has to grant the
corresponding read-only access or confirm the configured backups
through AWS Backup or Data Lifecycle Manager.

## 10. Known limitations and pending checks

At the time of writing:

1. **GCP → AWS connectivity:** end-to-end delivery from GCP is not yet
    confirmed. It has to be verified after the GCP Collectors are
    deployed and VPN/BGP routing is in place.
2. **OTLP gRPC ingestion:** the listener and the TCP port are verified,
    but an actual OTLP gRPC Export has not been tested yet.
3. **EBS snapshots:** the check is blocked by the missing IAM
    permission `ec2:DescribeSnapshots`.
4. **Recovery after reboot:** Docker autostart, restart policies and
    `fstab` are configured, but a full reboot test has not been done.
5. **Resources:** the server has 3.7 GiB of RAM; the load has to be
    monitored after all telemetry sources are connected.

These items do not invalidate the confirmed working state of the base
SigNoz installation and OTLP HTTP ingestion.

## 11. Summary of completed work

On the `demo3-signoz` server:

- the EC2 Ubuntu VM and the additional EBS disk were prepared;
- Docker Engine and Docker Compose were installed;
- Foundry was installed and the SigNoz configuration was generated;
- SigNoz, the OpenTelemetry Ingester, ClickHouse, ClickHouse Keeper and
    PostgreSQL were deployed;
- Docker volumes are stored on the additional EBS disk;
- the disk and Docker volume mounts are configured in `/etc/fstab`;
- Docker autostart and restart policies for the main containers are
    enabled;
- OTLP receivers are configured on ports `4317` and `4318`;
- the Security Group is configured for UI and OTLP traffic from the
    required CIDRs;
- the initial administrator registration was completed;
- OTLP HTTP ingestion was verified with a test metric and its display
    in the UI;
- container, disk, RAM and CPU state were checked.

**Conclusion:** the base SigNoz server installation is deployed and
working. OTLP HTTP ingestion is confirmed end to end. The server is
ready for the next stage: connecting the OpenTelemetry Collectors from
GCP. End-to-end integration, OTLP gRPC ingestion and backups have to be
confirmed separately.

## 12. Retention

Configured in the UI: **Settings → General → Retention**.

| Signal | Retention | Reason |
| --- | --- | --- |
| Metrics | 30 days | small volume; a month of history is needed for the SLO report |
| Logs | 7 days | the largest volume (syslog from the VMs, Nginx access log) |
| Traces | 7 days | needed once the Java Agent is connected |

The `/data` disk is only 10 GiB. If ClickHouse fills it, telemetry
ingestion stops. That is why `/data` usage is also checked by the
heartbeat (section 15). Manual check:

``` bash
df -h /data
```

## 13. Email notifications (SMTP)

SigNoz sends emails through its built-in Alertmanager, which needs an
SMTP server. Gmail is used (`smtp.gmail.com:587`, STARTTLS) with an App
password.

The Foundry-generated file `/opt/signoz/pours/deployment/compose.yaml`
is **not edited**: the next `foundryctl` run would overwrite it. Instead,
the SMTP settings live in separate files outside `pours/`:

- `/opt/signoz/smtp.env`: the `SIGNOZ_ALERTMANAGER_SIGNOZ_GLOBAL_SMTP__*`
    and `SIGNOZ_ALERTMANAGER_SIGNOZ_EXTERNAL__URL` variables, including
    the App password. Permissions `600`, owner root.
- `/opt/signoz/smtp-override.yaml`: a compose override that adds
    `env_file` to the SigNoz service.

Override file content (the service name in the Foundry compose file is
`signoz-signoz-0`):

``` yaml
services:
  signoz-signoz-0:
    env_file:
      - /opt/signoz/smtp.env
```

The password is stored only on the server; it is never committed to the
repository or written into documentation.

### Restarting SigNoz (always with the override)

``` bash
cd /opt/signoz/pours/deployment
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml config --quiet && echo "config OK"
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml up -d --no-deps signoz-signoz-0
```

> **Important:** every start or restart of SigNoz through
> `docker compose` must include **`-f /opt/signoz/smtp-override.yaml`**.
> Without it the container is recreated without the SMTP variables and
> emails stop being sent. The settings survive a VM reboot: Docker
> starts the same container with the same environment.

### Verification

``` bash
docker exec signoz-signoz-0 env | grep -c '^SIGNOZ_ALERTMANAGER_SIGNOZ_GLOBAL_SMTP__'
docker logs --since 5m signoz-signoz-0 2>&1 | grep -iE 'smtp|alertmanager' | tail -n 20
```

The first command must print `6`. The logs must not contain
`smtp_auth_username is not configured`.

### Channel in the UI

**Settings → Notification Channels**: channel `demo3-email`, type Email,
*Send resolved alerts* enabled. The test email was delivered
successfully.

## 14. Alerts

16 rules are created in SigNoz. For all of them: channel `demo3-email`,
labels `team=demo3`, `area=<infra|nginx|db|etcd>`,
`severity=<critical|warning>`. Each alert description links to a
dashboard and to a runbook in `docs/runbooks/`.

| # | Alert | Type | Condition | Severity |
| --- | --- | --- | --- | --- |
| 1 | Host not reporting | Metric | no data from the host for 5 min | critical |
| 2 | High CPU | Metric | CPU > 85% for 10 min | warning |
| 3 | High memory | Metric | RAM > 90% for 5 min | warning |
| 4 | Disk almost full | Metric | disk > 85% | warning |
| 5 | Disk full | Metric | disk > 95% | critical |
| 6 | Nginx down | Metric | `nginx_up` < 1 or no data for 5 min | critical |
| 7 | Nginx 5xx errors | Log | > 10 5xx responses in 5 min | warning |
| 8 | PostgreSQL exporter down | Metric | `up{service.name=postgresql}` < 1 for 2 min | critical |
| 9 | No Patroni leader | Metric | leaders < 1 or no data for 5 min | critical |
| 10 | Patroni split brain | Metric | leaders > 1 | critical |
| 11 | Replica not streaming | Metric | streaming replicas < 1 for 3 min | warning |
| 12 | Replication lag | Metric | lag > 30 s for 5 min | warning |
| 13 | Failover happened | Log | `promoted self to leader` in the Patroni logs | warning |
| 14 | etcd quorum at risk | Metric | fewer than 3 etcd members up for 2 min | warning |
| 15 | etcd quorum lost | Metric | fewer than 2 etcd members up | critical |
| 16 | etcd no leader | Metric | `etcd_server_has_leader` < 1 for 1 min | critical |

**Current state:** all rules are created but **disabled** until the
OpenTelemetry Collector is deployed on the GCP VMs. After deployment
they have to be enabled and tested (stopping the Collector, CPU load,
filling the disk, Patroni switchover).

SigNoz v0.151 has no export of alert rules in the UI, so their
parameters are recorded in this section. After a SigNoz reinstall the
rules have to be recreated from this table.

## 15. Heartbeat (dead man's switch) for SigNoz itself

**Why.** All alerts are sent by SigNoz itself. If the VM, Docker or
ClickHouse goes down, or the disk fills up, no alert arrives. An
external uptime check cannot reach SigNoz because the server is in a
private network. So SigNoz checks in with the external service
healthchecks.io every 5 minutes. If the check-in does not arrive,
healthchecks.io sends the email.

### healthchecks.io

| Parameter | Value |
| --- | --- |
| Check | `demo3-signoz` |
| Schedule | Simple, period **5 min**, grace **10 min** |
| Notifications | email (team mailbox) |

The ping URL (`https://hc-ping.com/<uuid>`) is a secret and is stored
only on the server.

### What the script checks

The script `signoz/heartbeat/signoz-heartbeat.sh` (in the repository),
installed as `/usr/local/bin/signoz-heartbeat.sh`:

1. The SigNoz API responds: `http://localhost:8080/api/v1/health`.
2. The Ingester accepts OTLP on `:4318` and returns `200`.
3. `/data` is less than 90% full.
4. At least 5 SigNoz containers are running.

If everything is fine, the script sends a ping. If a check fails, it
sends `/fail` with the reason, and the email arrives immediately. If
the VM itself or cron is down, no ping arrives, and after 15 min
healthchecks.io sends a *DOWN* email.

### Files on the server

| File | Purpose |
| --- | --- |
| `/usr/local/bin/signoz-heartbeat.sh` | the script, permissions `755` |
| `/opt/signoz/heartbeat.url` | ping URL, permissions `600` |
| `/etc/cron.d/signoz-heartbeat` | runs every 5 min |
| `/etc/logrotate.d/signoz-heartbeat` | weekly log rotation, 4 copies |
| `/var/log/signoz-heartbeat.log` | run log |

Content of `/etc/cron.d/signoz-heartbeat`:

``` text
*/5 * * * * root /usr/local/bin/signoz-heartbeat.sh >> /var/log/signoz-heartbeat.log 2>&1
```

### Verification

``` bash
/usr/local/bin/signoz-heartbeat.sh                  # expected: ... ok disk=NN% containers=5
DISK_LIMIT=1 /usr/local/bin/signoz-heartbeat.sh     # test: DOWN email right away
/usr/local/bin/signoz-heartbeat.sh                  # back to normal: UP email
tail -n 20 /var/log/signoz-heartbeat.log
```

### Limitations

The script, the URL and the cron entry live on the EC2 root disk. The
AWS management infrastructure is set up manually, not by the pipeline,
so if the instance is ever recreated they have to be installed again
following this section. During planned SigNoz maintenance, pause the
check in healthchecks.io (it resumes automatically on the next ping).

## 16. Dashboards

The fixed dashboards are exported to JSON and stored in the repository
under `signoz/dashboards/`:

- `infrastructure-overview.json`: Demo3: Infrastructure Overview
- `nginx-load-balancer.json`: Demo3: Nginx & Load Balancer
- `application-observability.json`: Demo3: Application Observability
- `postgresql-replication.json`: Demo3: PostgreSQL & Replication
- `patroni-etcd-ha.json`: Demo3: Patroni & etcd HA

Restore: **Dashboards → + New dashboard → Import JSON**. After changing
a dashboard in the UI, export it again (⋮ → Export JSON) and commit.
