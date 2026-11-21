# SigNoz down (heartbeat missing / failed)

**Signal:** an email from healthchecks.io: check `demo3-signoz` is **DOWN** (no ping for > 10 min), or a `/fail` message with the reason.
While SigNoz is down, **no other alert works**, so this is critical.

```
aws ssm start-session --target i-054d48c41c4174ce6 --region eu-central-1
sudo -i
tail -n 20 /var/log/signoz-heartbeat.log
```
The last `FAIL: ...` line shows which check failed.

## 1. VM / SSM unavailable
- AWS Console → EC2 → `demo3-signoz`: state, *Status checks*. If it is stopped, start it.
- No SSM: check that the VM is running and has the `demo3-signoz` role.

## 2. Containers
```
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
cd /opt/signoz/pours/deployment
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml up -d
docker logs --tail 80 signoz-signoz-0
docker logs --tail 80 signoz-telemetrystore-clickhouse-0-0
```
`-f /opt/signoz/smtp-override.yaml` is mandatory, otherwise email notifications stop working.

## 3. `/data` disk is full
```
df -h / /data
du -sh /data/docker-volumes/*
```
- Short term: reduce retention in SigNoz UI → Settings → General (logs: 3 days).
- Long term: grow the EBS volume `demo3-signoz-data` (Terraform `management-aws`), then run `resize2fs` on `/data`.

## 4. Ingestion (`OTLP HTTP ingest returned ...`)
```
docker logs --tail 80 signoz-ingester-1
ss -ltnp | grep -E ':4317|:4318'
```

## 5. After recovery
- Run `/usr/local/bin/signoz-heartbeat.sh` by hand: it must print `ok`, and the check in healthchecks.io turns UP.
- Check that metrics from the GCP hosts arrive again (Infrastructure Overview dashboard).
- Data for the outage period is not recovered: the Collectors keep a queue (`queue_size: 5000`) for only a few minutes.
