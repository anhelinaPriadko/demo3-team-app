# Demo 3 — SLI / SLO

Service: **Cinema Booking**, `https://cinema-service-team1.pp.ua` (Nginx `demo3-nginx` → `demo3-app-1`, `demo3-app-2` → PostgreSQL HA).
Evaluation window: **30 days, rolling**. Owner: Observability & Reliability.

## SLIs and SLOs

| # | SLI (what we measure) | How it is calculated | Source | SLO | Error budget per 30 days |
| --- | --- | --- | --- | --- | --- |
| 1 | **External availability** | successful checks / all checks. Success = HTTP 2xx and the page contains `Cinema Booking` | GCP Uptime Check (later Pingdom), every minute from ≥ 3 regions | **99.5%** | 216 min (3 h 36 min) |
| 2 | **API availability (app + DB)** | the same for `GET /api/v1/movies` (2xx response) | GCP Uptime Check | **99.0%** | 432 min (7 h 12 min) |
| 3 | **Server-side request success** | `1 − (5xx responses / all requests)` in the Nginx access log | SigNoz, `demo3-nginx` logs | **99.5%** | 0.5% of requests |
| 4 | **Latency** | share of requests faster than 1 s (p95 < 1 s) | SigNoz APM (`demo3-java-app`, Java Agent) | **95% < 1 s** | 5% slow requests |

SLI 4 is measured once the Java Agent is integrated. Until then latency is not part of the report.

### Data tier objectives

| Objective | Value | How it is verified |
| --- | --- | --- |
| RPO (how much data can be lost) | ≤ 24 h | daily backup at 03:00 from the replica to GCS |
| RTO (how fast we restore) | ≤ 1 h | regular restore test from GCS |
| Automatic failover | ≤ 60 s without a leader | Patroni (`ttl: 30`), alert *No Patroni leader* |

## Why these numbers

- 99.5% is a realistic target for demo infrastructure with a single Nginx VM (a single point of failure). 99.9% (43 min per month) would not survive even one restart of the Nginx VM together with a certificate reissue.
- The API has a lower target because it depends on the database and on failover.

## Where to look

- SLI 1–2: Cloud Console → Monitoring → **Uptime checks** → the check → *Uptime %*. Once Pingdom is approved: **Reports → Uptime**.
- SLI 3: SigNoz, Logs → **Add query**:
  - A: count, filter `host.name = 'demo3-nginx' AND log.file.path = '/var/log/nginx/access.log' AND severity_number >= 17`
  - B: count, filter `host.name = 'demo3-nginx' AND log.file.path = '/var/log/nginx/access.log'`
  - formula `(1 - A / B) * 100`, time range: last 30 days
- SLI 4: SigNoz → Services → `demo3-java-app` → p95 latency.

## Error budget policy

| Budget spent | Action |
| --- | --- |
| < 50% | business as usual |
| 50–100% | risky changes (DB migrations, VM reinstalls) only with a rollback plan and inside *Planned Downtime* |
| > 100% | freeze new features until the budget recovers. Root cause analysis (postmortem) and follow-up tasks |

Every incident that consumes > 25% of the monthly budget gets a postmortem (template in `runbooks/README.md`).

## Review

SLOs are reviewed once a month or after every major incident.
