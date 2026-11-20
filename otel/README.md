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
- Усі VM: host metrics (CPU, disk, load, filesystem, memory, network, paging, processes), включно з `system.cpu.utilization`, `system.memory.utilization`, `system.filesystem.utilization` (у hostmetrics вони за замовчуванням вимкнені, тут увімкнені явно), і system logs. Псевдо-ФС і bind-mount-и виключені, щоб диск не рахувався двічі.
- Nginx VM: Nginx access/error logs (з severity: 5xx → ERROR, 4xx → WARN; атрибути `http_status`, `http_method`, `http_path`, `client_ip`) та метрики через Nginx Prometheus Exporter.
- App VM: host metrics і system logs, `service.name = demo3-app-host`. Application traces/metrics передаються Java Agent безпосередньо до SigNoz через OTLP/HTTP (`service.name = demo3-java-app`).
- DB master/replica: PostgreSQL logs (`service.name = postgresql`), логи Patroni і etcd з journald (`service.name = patroni` / `etcd`), PostgreSQL exporter metrics, Patroni `/metrics`, etcd `/metrics`. Поточна роль вузла — метрика `patroni_primary` (1 = лідер), а не статичний ярлик.
- Witness: host metrics, system logs, логи etcd з journald та etcd `/metrics`.

## Endpoints
- SigNoz OTLP/gRPC: `10.10.0.118:4317`
- Nginx stub_status: `127.0.0.1:8081/stub_status`
- Nginx exporter: `127.0.0.1:9113/metrics`
- PostgreSQL exporter: `127.0.0.1:9187/metrics` (unix socket, peer auth, без пароля)
- Patroni: `127.0.0.1:8008/metrics`
- etcd: `127.0.0.1:2379/metrics` (client listener, окремий metrics-порт не потрібен)

## Передумови
- Ubuntu 24.04, systemd, outbound HTTPS до GitHub, persistent journal (`/var/log/journal`).
- Запуск deployment вимагає root/sudo.
- На Nginx VM Nginx має бути встановлений і активний.
- На DB VM має працювати Patroni (або `postgresql.service`). У `/etc/patroni/config.yml` на **обох** DB-вузлах потрібні:
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
  і для файлових логів PostgreSQL (`patronictl edit-config`): `logging_collector: on`, `log_directory: /var/log/postgresql`.
- Деплоїти спочатку на поточного лідера (роль `otel_monitor` створюється лише там і реплікується).
- На DB VM мають бути встановлені Patroni та etcd окремим infrastructure deployment. Цей комплект їх не встановлює.
- Patroni має надавати HTTP `/metrics` на localhost:8008.
- etcd має слухати client URL `http://127.0.0.1:2379` (є у скриптах Data tier).
- На app VM Java Agent налаштовується в Docker image/application deployment, не цими host scripts.
- SigNoz має приймати OTLP/gRPC на `10.10.0.118:4317`; мережевий маршрут GCP→AWS має працювати.
- OTLP exporter використовує `tls.insecure: true`, отже endpoint має бути доступний лише через приватний VPN.

## Повторний запуск та видалення
Скрипти розраховані на повторний запуск: Nginx config/service перезаписуються контрольовано; PostgreSQL exporter не має пароля: OS-користувач `postgres_exporter` через `pg_ident` відображається на роль `otel_monitor`. `uninstall.sh` видаляє Collector та exporter services/binaries, але не видаляє monitoring role з PostgreSQL автоматично.

## Межі перевірки
Усі YAML-файли та Bash-скрипти перевіряються локально на синтаксис. Реальна сумісність пакетів, запуск на шести VM, доступ до endpoints і фактичне надходження телеметрії мають бути перевірені під час deployment у вашій інфраструктурі.
