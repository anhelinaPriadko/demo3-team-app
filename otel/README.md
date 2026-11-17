# Demo 3 — OpenTelemetry

Цей каталог є джерелом deployment-скриптів у GitLab. GitLab Runner копіює його в `/tmp/otel/` на відповідну GCP VM і запускає `scripts/deploy.sh`.

## Структура
- `configs/` — конфігурації Collector за ролями VM.
- `scripts/install.sh` — встановлення Collector та рольових exporters.
- `scripts/configure.sh` — налаштування exporters, доступу до логів, конфігурації та systemd.
- `scripts/verify.sh` — перевірка конфігурації, сервісу, OTLP-зв'язку та локальних endpoints.
- `scripts/deploy.sh` — послідовний запуск install → configure → verify.
- `scripts/uninstall.sh` — видалення Collector та встановлених exporter binaries/services.

## Ролі та вузли
| Role | VM |
|---|---|
| `nginx` | `demo3-nginx` |
| `app` | `demo3-app-1`, `demo3-app-2` |
| `db-master` | `demo3-db-master` |
| `db-slave` | `demo3-db-slave` |
| `witness` | `demo3-db-witness` |

## Запуск
На VM, після копіювання каталогу `otel/` у `/tmp/otel/`:
```bash
sudo bash /tmp/otel/scripts/deploy.sh nginx demo3-nginx
```
Замінити роль і hostname відповідно до таблиці.

## Що збирається
- Усі VM: host metrics (CPU, disk, load, filesystem, memory, network, paging, processes) і system logs.
- Nginx VM: Nginx access/error logs та метрики через локальний Nginx Prometheus Exporter.
- App VM: host metrics і system logs. Application traces/metrics передаються Java Agent безпосередньо до SigNoz через OTLP/HTTP.
- DB master/replica: PostgreSQL logs, PostgreSQL exporter metrics, Patroni `/metrics`, etcd `/metrics`.
- Witness: host metrics, system logs та etcd `/metrics`.

## Endpoints
- SigNoz OTLP/gRPC: `10.10.0.118:4317`
- Nginx stub_status: `127.0.0.1:8081/stub_status`
- Nginx exporter: `127.0.0.1:9113/metrics`
- PostgreSQL exporter: `127.0.0.1:9187/metrics`
- Patroni: `127.0.0.1:8008/metrics`
- etcd metrics listener: `127.0.0.1:2381/metrics`

**Важливо щодо etcd:** порт `2379` — стандартний client port, а не гарантований metrics listener. Для цього комплекту etcd має бути налаштований з `--listen-metrics-urls=http://127.0.0.1:2381` (або еквівалентом у конфігураційному файлі). Порт `2381` не відкривати назовні.

## Передумови
- Ubuntu 24.04, systemd, outbound HTTPS до GitHub.
- Запуск deployment вимагає root/sudo.
- На Nginx VM Nginx має бути встановлений і активний.
- На DB VM PostgreSQL має бути активним; доступ `runuser -u postgres psql` має працювати через локальну peer authentication.
- На DB VM мають бути встановлені Patroni та etcd окремим infrastructure deployment. Цей комплект їх не встановлює.
- Patroni має надавати HTTP `/metrics` на localhost:8008.
- etcd має надавати HTTP `/metrics` на localhost:2381.
- На app VM Java Agent налаштовується в Docker image/application deployment, не цими host scripts.
- SigNoz має приймати OTLP/gRPC на `10.10.0.118:4317`; мережевий маршрут GCP→AWS має працювати.
- OTLP exporter використовує `tls.insecure: true`, отже endpoint має бути доступний лише через приватний VPN.

## Повторний запуск та видалення
Скрипти розраховані на повторний запуск: Nginx config/service перезаписуються контрольовано; PostgreSQL exporter credential створюється один раз і повторно використовується з локального root-owned env file. `uninstall.sh` видаляє Collector та exporter services/binaries, але не видаляє monitoring role з PostgreSQL автоматично.

## Межі перевірки
Усі YAML-файли та Bash-скрипти перевіряються локально на синтаксис. Реальна сумісність пакетів, запуск на шести VM, доступ до endpoints і фактичне надходження телеметрії мають бути перевірені під час deployment у вашій інфраструктурі.
