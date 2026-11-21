# SigNoz down (heartbeat missing / failed)

**Сигнал:** лист від healthchecks.io: check `demo3-signoz` is **DOWN** (немає пінгу > 10 хв) або повідомлення `/fail` з причиною.
Поки SigNoz лежить, **жоден інший алерт не працює**, тому це critical.

```
aws ssm start-session --target i-054d48c41c4174ce6 --region eu-central-1
sudo -i
tail -n 20 /var/log/signoz-heartbeat.log
```
Останній рядок `FAIL: ...` показує, яка саме перевірка впала.

## 1. VM / SSM недоступні
- AWS Console → EC2 → `demo3-signoz`: стан, *Status checks*. Якщо stopped — Start.
- Немає SSM — перевірити, що VM running і має роль `demo3-signoz`.

## 2. Контейнери
```
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
cd /opt/signoz/pours/deployment
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml up -d
docker logs --tail 80 signoz-signoz-0
docker logs --tail 80 signoz-telemetrystore-clickhouse-0-0
```
`-f /opt/signoz/smtp-override.yaml` обов'язковий, інакше email-сповіщення зникнуть.

## 3. Диск `/data` заповнений
```
df -h / /data
du -sh /data/docker-volumes/*
```
- Тимчасово зменшити retention: SigNoz UI → Settings → General (logs 3 дні).
- Довгостроково — збільшити EBS-том `demo3-signoz-data` (Terraform `management-aws`), потім `resize2fs` на `/data`.

## 4. Ingestion (`OTLP HTTP ingest returned ...`)
```
docker logs --tail 80 signoz-ingester-1
ss -ltnp | grep -E ':4317|:4318'
```

## 5. Після відновлення
- `/usr/local/bin/signoz-heartbeat.sh` вручну: має вивести `ok`, і check у healthchecks.io стане UP.
- Перевірити, що метрики з GCP-хостів знову надходять (дашборд Infrastructure Overview).
- Пропуск даних за час простою не відновлюється: Collector-и тримають чергу (`queue_size: 5000`) лише кілька хвилин.
