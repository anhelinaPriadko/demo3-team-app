# Runbooks — Demo 3

Кожен алерт SigNoz, uptime-check і heartbeat посилається на runbook з цієї теки.
Посилання для опису алерту: `https://github.com/anhelinaPriadko/demo3-team-app/blob/main/docs/runbooks/<файл>.md`

## Алерт → runbook

| Алерт / перевірка | Runbook |
|---|---|
| Uptime: site / API unavailable | [site-unavailable.md](site-unavailable.md) |
| Host not reporting | [host-not-reporting.md](host-not-reporting.md) |
| High CPU, High memory | [high-cpu-memory.md](high-cpu-memory.md) |
| Disk almost full, Disk full | [disk-full.md](disk-full.md) |
| Nginx down, Nginx 5xx errors | [nginx.md](nginx.md) |
| PostgreSQL exporter down, No Patroni leader, Split brain, Replica not streaming, Replication lag, Failover happened | [postgresql-ha.md](postgresql-ha.md) |
| etcd quorum at risk / lost, etcd no leader | [etcd.md](etcd.md) |
| SigNoz heartbeat missing / failed | [signoz-down.md](signoz-down.md) |

## Доступ (однаково для всіх runbook-ів)

GCP VM (IAP + OS Login, твій Google-акаунт). Зони: `app-2` і `db-witness` у `europe-west3-b`, решта в `europe-west3-a`:
```
gcloud compute ssh <vm> --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
```
Увімкнути вимкнену VM:
```
gcloud compute instances start <vm> --zone europe-west3-a --project demo3-team1
```
AWS (SigNoz, GitLab, runner):
```
aws ssm start-session --target <instance-id> --region eu-central-1
```

| VM | Private IP | Зона |
|---|---|---|
| demo3-nginx | 10.20.0.2 (public 34.40.82.240) | a |
| demo3-app-1 | 10.20.1.2 | a |
| demo3-app-2 | 10.20.1.5 | b |
| demo3-db-master | 10.20.1.4 | a |
| demo3-db-slave | 10.20.1.3 | a |
| demo3-db-witness | 10.20.1.6 | b |
| demo3-signoz (AWS) | 10.10.0.118, `i-054d48c41c4174ce6` | eu-central-1a |

## Процес інциденту

1. **Визнати**: напиши в командний чат «беру <алерт>», щоб двоє не робили одне й те саме.
2. **Оцінити вплив**: чи працює сайт (`curl -I https://cinema-service-team1.pp.ua`)? Від цього залежить, critical це чи warning.
3. **Стабілізувати** за runbook-ом. Спершу відновити роботу, а причину шукати потім.
4. **Оновлювати статус** у чаті кожні 15–30 хв.
5. **Закрити**: алерт перейшов у *resolved*, сайт працює.
6. **Postmortem** для critical-інцидентів і всього, що з'їло > 25% бюджету помилок (`docs/slo.md`).

### Шаблон postmortem
```
# <дата> <коротка назва>
Вплив: що не працювало, скільки хвилин, скільки бюджету SLO з'їдено
Хронологія: час виявлення (алерт/людина), ключові дії, час відновлення
Причина: технічна першопричина
Що спрацювало / що ні: алерти, runbook, доступи
Дії: задача — відповідальна людина — термін
```
