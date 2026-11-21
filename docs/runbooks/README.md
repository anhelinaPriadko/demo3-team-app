# Runbooks — Demo 3

Every SigNoz alert, uptime check and the heartbeat link to a runbook in this folder.
Link format for alert descriptions: `https://github.com/anhelinaPriadko/demo3-team-app/blob/main/docs/runbooks/<file>.md`

## Alert → runbook

| Alert / check | Runbook |
|---|---|
| Uptime: site / API unavailable | [site-unavailable.md](site-unavailable.md) |
| Host not reporting | [host-not-reporting.md](host-not-reporting.md) |
| High CPU, High memory | [high-cpu-memory.md](high-cpu-memory.md) |
| Disk almost full, Disk full | [disk-full.md](disk-full.md) |
| Nginx down, Nginx 5xx errors | [nginx.md](nginx.md) |
| PostgreSQL exporter down, No Patroni leader, Split brain, Replica not streaming, Replication lag, Failover happened | [postgresql-ha.md](postgresql-ha.md) |
| etcd quorum at risk / lost, etcd no leader | [etcd.md](etcd.md) |
| SigNoz heartbeat missing / failed | [signoz-down.md](signoz-down.md) |

## Access (the same for all runbooks)

GCP VMs (IAP + OS Login, your Google account). Zones: `app-2` and `db-witness` are in `europe-west3-b`, the rest in `europe-west3-a`:
```
gcloud compute ssh <vm> --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
```
Start a stopped VM:
```
gcloud compute instances start <vm> --zone europe-west3-a --project demo3-team1
```
AWS (SigNoz, GitLab, runner):
```
aws ssm start-session --target <instance-id> --region eu-central-1
```

| VM | Private IP | Zone |
|---|---|---|
| demo3-nginx | 10.20.0.2 (public 34.40.82.240) | a |
| demo3-app-1 | 10.20.1.2 | a |
| demo3-app-2 | 10.20.1.5 | b |
| demo3-db-master | 10.20.1.4 | a |
| demo3-db-slave | 10.20.1.3 | a |
| demo3-db-witness | 10.20.1.6 | b |
| demo3-signoz (AWS) | 10.10.0.118, `i-054d48c41c4174ce6` | eu-central-1a |

## Incident process

1. **Acknowledge**: post "taking <alert>" in the team chat so that two people do not work on the same thing.
2. **Assess the impact**: does the site work (`curl -I https://cinema-service-team1.pp.ua`)? This decides whether it is critical or a warning.
3. **Stabilize** using the runbook. Restore service first, look for the root cause later.
4. **Post status updates** in the chat every 15–30 min.
5. **Close**: the alert is *resolved* and the site works.
6. **Postmortem** for critical incidents and for anything that consumed > 25% of the error budget (`docs/slo.md`).

### Postmortem template
```
# <date> <short title>
Impact: what did not work, for how many minutes, how much SLO budget was consumed
Timeline: detection time (alert/person), key actions, recovery time
Root cause: the technical root cause
What worked / what did not: alerts, runbook, access
Actions: task — owner — due date
```
