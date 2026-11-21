# SigNoz Server --- виконані роботи та конфігурація

**Дата фіксації:** 19 листопада 2026 року\
**Сервер:** `demo3-signoz`\
**Приватна IP-адреса:** `10.10.0.118`\
**Хмарний провайдер:** AWS\
**Регіон / Availability Zone:** `eu-central-1` / `eu-central-1a`\
**ОС:** Ubuntu 24.04.5 LTS (x86_64)

------------------------------------------------------------------------

## 1. Призначення

На сервері розгорнуто SigNoz для приймання, зберігання та перегляду
телеметрії в межах Demo 3 --- Observability & Reliability.

SigNoz розгорнуто на окремій EC2 VM в AWS. Очікувані джерела телеметрії
--- OpenTelemetry Collectors на інфраструктурі GCP. Мережевий діапазон
AWS --- `10.10.0.0/16`, GCP --- `10.20.0.0/16`.

## 2. Інфраструктура EC2 та диски

### EC2

  Параметр             Значення
  -------------------- -----------------------
  Назва                `demo3-signoz`
  Instance ID          `i-054d48c41c4174ce6`
  Instance type        `c7i-flex.large`
  Приватна IP-адреса   `10.10.0.118`
  Регіон               `eu-central-1`
  Availability Zone    `eu-central-1a`
  ОС                   Ubuntu 24.04.5 LTS
  CPU                  2 vCPU
  RAM                  приблизно 3.7 GiB

Публічну IPv4-адресу для сервера не налаштовано. Адміністративний доступ
здійснюється через AWS Systems Manager Session Manager.

### EBS

Сервер має root-диск і додатковий EBS-диск для Docker volumes та даних
SigNoz.

  Параметр           Root disk     Data disk
  ------------------ ------------- ----------------
  Розмір             15 GiB        10 GiB
  Пристрій           root volume   `/dev/nvme1n1`
  Файлова система    ext4          ext4
  Точка монтування   `/`           `/data`
  Тип data disk      ---           gp3

Додатковий EBS volume в AWS має назву `demo3-signoz-data`, ID
`vol-055b543e582bbdcf6`.

Поточний стан дисків під час перевірки:

- `/`: 14 GiB доступного файлового простору, використано близько 6.5
    GiB.
- `/data`: 9.8 GiB, використано близько 297 MiB, вільно близько 9 GiB.

### Persistence Docker volumes

Docker volumes перенесені на додатковий диск через bind mount:

``` fstab
LABEL=data /data ext4 defaults,nofail 0 2
/data/docker-volumes /var/lib/docker/volumes none bind,nofail,x-systemd.requires-mounts-for=/data 0 0
```

Перевірено командами:

``` bash
findmnt /data
findmnt /var/lib/docker/volumes
df -h / /data
```

Фактичний результат:

- `/data` змонтований з `/dev/nvme1n1`.
- `/var/lib/docker/volumes` змонтований з
    `/dev/nvme1n1[/docker-volumes]`.
- У `/data/docker-volumes` під час перевірки було близько 295 MiB
    даних.

Основні Docker volumes:

- `signoz-metastore-postgres-0-data` --- дані PostgreSQL.
- `signoz-telemetrykeeper-0-data` --- дані ClickHouse Keeper.
- `signoz-telemetrystore-0-0-data` --- дані ClickHouse.
- `signoz-telemetrystore-user-scripts` --- volume для службових
    скриптів.

Також у Docker є два volumes з анонімними довгими ідентифікаторами. Їхнє
призначення не встановлювалося; видаляти їх без додаткової перевірки не
слід.

## 3. Встановлене програмне забезпечення

На сервері встановлено:

- Docker Engine `29.1.0`.
- Docker Compose `v5.8.0`.
- Docker Buildx та containerd.
- Foundry CLI `v0.5.0`.
- SigNoz `v0.151.0` (enterprise-variant image).

Foundry встановлено за допомогою офіційного інсталяційного скрипта
SigNoz. Конфігурація інсталяції розташована в
`/opt/signoz/casting.yaml`:

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

За допомогою Foundry згенеровано Compose-конфігурацію та конфігурації
Ingester. Основний Compose-файл:

``` text
/opt/signoz/pours/deployment/compose.yaml
```

Додаткові файли Ingester:

``` text
/opt/signoz/pours/deployment/ingester/ingester.yaml
/opt/signoz/pours/deployment/ingester/opamp.yaml
```

Compose-конфігурацію перевірено через
`docker compose ... config --quiet`, після чого сервіси запущено в
detached mode.

## 4. Контейнери SigNoz

Основні контейнери:

  ---------------------------------------------------------------------------------------------
  Контейнер                                     Призначення             Зафіксований стан
  --------------------------------------------- ----------------------- -----------------------
  `signoz-signoz-0`                             SigNoz UI та API        Up, healthy

  `signoz-ingester-1`                           OpenTelemetry Collector Up
                                                / ingestion

  `signoz-telemetrystore-clickhouse-0-0`        ClickHouse telemetry    Up, healthy
                                                storage

  `signoz-telemetrykeeper-clickhousekeeper-0`   ClickHouse Keeper       Up, healthy

`signoz-metastore-postgres-0`                 PostgreSQL metadata     Up, healthy
                                                store
  ---------------------------------------------------------------------------------------------

Додаткові одноразові контейнери:

- `signoz-telemetrystore-clickhouse-user-scripts` --- завершив роботу
    зі статусом `Exited (0)`.
- `signoz-telemetrystore-migrator` --- завершив роботу зі статусом
    `Exited (0)`.

`Exited (0)` для цих службових завдань означає успішне завершення, а не
помилку.

### Автоматичний запуск

Перевірено:

``` bash
systemctl is-enabled docker
systemctl is-active docker
```

Результат: Docker service --- `enabled` та `active`.

Для основних постійно працюючих контейнерів перевірено Docker restart
policy. Значення:

``` text
unless-stopped
```

Це налаштовано для SigNoz, Ingester, ClickHouse, PostgreSQL та
ClickHouse Keeper.

Монтування `/data` і bind mount Docker volumes прописані в `/etc/fstab`.
Фактичне відновлення після перезавантаження VM не тестувалося.

## 5. Мережа та порти

Сервер розташований у приватній мережі AWS `10.10.0.0/16`. Для доступу
до UI з робочої станції використовується AWS SSM port forwarding.

### Опубліковані порти

  Порт     Протокол   Призначення
  -------- ---------- --------------------
  `8080`   TCP/HTTP   SigNoz UI
  `4317`   TCP/gRPC   OTLP gRPC receiver
  `4318`   TCP/HTTP   OTLP HTTP receiver

У конфігурації Ingester визначено:

``` yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

Налаштування pipeline для метрик включає:

- receiver: `otlp`;
- processors: `filter/drop_stale`, `batch`;
- exporters: `signozclickhousemetrics`, `signozmeter`,
    `metadataexporter`.

### Security Group

Перевірені inbound rules Security Group `demo3-signoz-sg`:

  Порт   Протокол   Source           Призначення
  ------ ---------- ---------------- ------------------------
  8080   TCP        `10.10.0.0/16`   Доступ до UI з AWS VPC
  4318   TCP        `10.10.0.0/16`   OTLP HTTP з AWS VPC
  4318   TCP        `10.20.0.0/16`   OTLP HTTP з GCP
  4317   TCP        `10.10.0.0/16`   OTLP gRPC з AWS VPC
  4317   TCP        `10.20.0.0/16`   OTLP gRPC з GCP

На сервері підтверджено, що порти `4317`, `4318` та `8080` слухають на
host interfaces. Для `4317` окремо підтверджено TCP-з'єднання з
localhost.

Наявність правил Security Group сама по собі не підтверджує наскрізну
мережеву доступність з GCP. Фактичне з'єднання через VPN/BGP має
перевірятися під час інтеграції з GCP Collectors.

### Доступ до UI через SSM

Для локального доступу до UI використовується SSM port forwarding:

``` powershell
aws ssm start-session `
  --target i-054d48c41c4174ce6 `
  --region eu-central-1 `
  --document-name AWS-StartPortForwardingSession `
  --parameters '{"portNumber":["8080"],"localPortNumber":["18080"]}'
```

Після встановлення сесії UI відкривається за адресою:

``` text
http://localhost:18080
```

Вікно PowerShell із активною SSM-сесією потрібно залишати відкритим,
поки використовується UI.

## 6. Початкова реєстрація SigNoz

Виконано початкову реєстрацію адміністратора через UI SigNoz.

Після реєстрації:

- успішно створено організацію;
- виконано вхід до системи;
- UI відкривається через SSM port forwarding;
- у логах зафіксовано успішні HTTP-відповіді реєстрації та створення
    сесії.

Облікові дані в цій документації не зберігаються.

## 7. Перевірка приймання телеметрії

### OTLP HTTP --- перевірено end-to-end

Для тесту створено OTLP JSON payload із:

- `service.name = demo3-otlp-smoke-test`;
- назвою метрики `demo3_signoz_test`;
- типом `gauge`;
- значенням `42.0`.

Запит надіслано локально на Ingester:

``` bash
curl -i --max-time 10 \
  -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/otlp-test.json
```

Отримана відповідь:

``` text
HTTP/1.1 200 OK
{"partialSuccess":{}}
```

У логах Ingester за перевірений інтервал не знайдено повідомлень із
`error` або `failed`.

У SigNoz UI в Metrics Explorer знайдено `demo3_signoz_test`. UI показав:

- Samples: `1`;
- Time Series: `1 total – 1 active`;
- Metric Type: `GAUGE`;
- `service.name`: `demo3-otlp-smoke-test`;
- Last received: приблизно 2 хвилини тому на момент скриншота.

Отже, OTLP HTTP ingestion, обробка метрики, її відображення в SigNoz UI
підтверджені.

### OTLP gRPC --- частково перевірено

Підтверджено:

- receiver налаштований на `0.0.0.0:4317`;
- host слухає `0.0.0.0:4317` та `[::]:4317`;
- TCP-з'єднання до `127.0.0.1:4317` успішне.

Для додаткової перевірки використано `grpcurl` у тимчасовому
Docker-контейнері. Команда `grpcurl list` повернула:

``` text
server does not support the reflection API
```

Спроба виклику OTLP Export RPC через `grpcurl` також не виконалася,
оскільки клієнт не мав service descriptor і сервер не підтримував
reflection.

Це не доводить несправність OTLP gRPC receiver: gRPC reflection не є
обов'язковою умовою для OTLP. Однак фактичне приймання OTLP gRPC payload
не підтверджене.

**Наступна перевірка:** під час підключення GCP OpenTelemetry Collector
надіслати тестову метрику через OTLP gRPC на `10.10.0.118:4317` та
перевірити її появу в SigNoz UI.

## 8. Моніторинг ресурсів сервера

Під час перевірки зафіксовано:

  Ресурс            Значення
  ----------------- --------------------
  RAM total         3.7 GiB
  RAM used          1.3 GiB
  RAM available     2.4 GiB
  CPU               2 vCPU
  Load average      `0.05, 0.11, 0.09`
  Root disk usage   48%
  `/data` usage     4%

Приблизне споживання RAM контейнерами на момент `docker stats`:

  Контейнер                   RAM
  ------------------- -----------
  ClickHouse            646.8 MiB
  Ingester              147.9 MiB
  ClickHouse Keeper     108.9 MiB
  PostgreSQL            38.07 MiB
  SigNoz                35.38 MiB

Додаткові перевірки:

- `/proc/pressure/memory`: `avg10`, `avg60`, `avg300` дорівнювали
    `0.00`;
- у kernel journal за останні дві години не знайдено повідомлень про
    OOM або вбивство процесів через нестачу пам'яті;
- Docker memory limit для SigNoz та Ingester повернув `0`, тобто
    окремий жорсткий memory limit не заданий.

Поточних ознак memory pressure не виявлено. Водночас 3.7 GiB RAM ---
обмежений ресурс для подальшого збору метрик, логів і traces з усіх VM.
Після підключення реальних колекторів потрібно повторно оцінити
споживання. За потреби розглянути збільшення RAM, наприклад до 8 GiB, з
урахуванням бюджету та погодження команди.

## 9. Резервне копіювання

Додатковий EBS volume:

- ID: `vol-055b543e582bbdcf6`;
- Name: `demo3-signoz-data`;
- Size: 10 GiB;
- Type: gp3;
- State: In-use;
- AZ: `eu-central-1a`.

Перевірити наявність snapshots через AWS Console не вдалося:
IAM-користувач `demo3-observability-user` не має дозволу
`ec2:DescribeSnapshots`.

Тому наявність або відсутність резервних копій не встановлена.

Для завершення цієї перевірки адміністратор AWS має надати відповідний
read-only доступ або самостійно підтвердити налаштоване резервування
через AWS Backup чи Data Lifecycle Manager.

## 10. Відомі обмеження та незавершені перевірки

На момент фіксації документації:

1. **GCP → AWS connectivity:** наскрізна доставка з GCP ще не
    підтверджена. Потрібна перевірка після розгортання GCP Collectors та
    за наявності VPN/BGP-маршрутизації.
2. **OTLP gRPC ingestion:** listener і TCP-порт перевірені, але
    фактичний OTLP gRPC Export ще не протестований.
3. **EBS snapshots:** перевірка заблокована відсутністю IAM-дозволу
    `ec2:DescribeSnapshots`.
4. **Recovery after reboot:** Docker autostart, restart policies та
    `fstab` налаштовані, але повний reboot-тест не проводився.
5. **Ресурси:** сервер має 3.7 GiB RAM; потрібно спостерігати за
    навантаженням після підключення всіх джерел телеметрії.

Ці пункти не скасовують підтверджену працездатність базової інсталяції
SigNoz та OTLP HTTP ingestion.

## 11. Підсумок виконаних робіт

На сервері `demo3-signoz`:

- підготовлено EC2 Ubuntu VM та додатковий EBS-диск;
- встановлено Docker Engine і Docker Compose;
- встановлено Foundry та згенеровано конфігурацію SigNoz;
- розгорнуто SigNoz, OpenTelemetry Ingester, ClickHouse, ClickHouse
    Keeper і PostgreSQL;
- налаштовано зберігання Docker volumes на додатковому EBS;
- налаштовано монтування диска та Docker volumes через `/etc/fstab`;
- увімкнено автозапуск Docker і політики перезапуску основних
    контейнерів;
- налаштовано OTLP receivers на портах `4317` і `4318`;
- налаштовано Security Group для UI та OTLP traffic із потрібних CIDR;
- виконано початкову реєстрацію адміністратора;
- перевірено OTLP HTTP ingestion тестовою метрикою та її відображення
    в UI;
- перевірено стан контейнерів, дисків, RAM і CPU.

**Висновок:** базова серверна інсталяція SigNoz розгорнута та
працездатна. OTLP HTTP ingestion підтверджено end-to-end. Сервер
підготовлений до наступного етапу --- підключення OpenTelemetry
Collectors з GCP. Наскрізну інтеграцію, OTLP gRPC ingestion та резервне
копіювання потрібно підтвердити окремо.

## 12. Retention (термін зберігання даних)

Налаштовано в UI: **Settings → General → Retention**.

  Сигнал    Термін    Причина
  --------- --------- -----------------------------------------------------------
  Metrics   30 днів   займають мало місця, місяць історії потрібен для звіту SLO
  Logs      7 днів    найбільший обсяг (syslog з VM, access log Nginx)
  Traces    7 днів    знадобляться після підключення Java Agent

Диск `/data` має лише 10 GiB. Якщо ClickHouse його заповнить, приймання
телеметрії зупиниться. Тому заповненість `/data` контролює ще й heartbeat
(розділ 15). Ручна перевірка:

``` bash
df -h /data
```

## 13. Email-сповіщення (SMTP)

SigNoz надсилає листи через вбудований Alertmanager, якому потрібен
SMTP-сервер. Використовується Gmail (`smtp.gmail.com:587`, STARTTLS) з
App password.

Згенерований Foundry файл `/opt/signoz/pours/deployment/compose.yaml`
**не редагується**: наступний запуск `foundryctl` його перезапише.
Натомість SMTP-налаштування лежать в окремих файлах поза `pours/`:

- `/opt/signoz/smtp.env`: змінні `SIGNOZ_ALERTMANAGER_SIGNOZ_GLOBAL_SMTP__*`
    і `SIGNOZ_ALERTMANAGER_SIGNOZ_EXTERNAL__URL`, разом з App password.
    Права `600`, власник root.
- `/opt/signoz/smtp-override.yaml`: compose override, який додає
    `env_file` до сервісу SigNoz.

Вміст override-файлу:

``` yaml
services:
  signoz:
    env_file:
      - /opt/signoz/smtp.env
```

Пароль зберігається лише на сервері, у репозиторій і документацію він не
потрапляє.

### Перезапуск SigNoz (обов'язково з override)

``` bash
cd /opt/signoz/pours/deployment
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml config --quiet && echo "config OK"
docker compose -f compose.yaml -f /opt/signoz/smtp-override.yaml up -d signoz
```

> **Важливо:** будь-який запуск або перезапуск SigNoz через
> `docker compose` робити **лише з `-f /opt/signoz/smtp-override.yaml`**.
> Без нього контейнер перестворюється без SMTP-змінних, і листи
> перестають надсилатися. Після reboot VM налаштування зберігаються:
> Docker піднімає той самий контейнер з тим самим env.

### Перевірка

``` bash
docker exec signoz-signoz-0 env | grep -c '^SIGNOZ_ALERTMANAGER_SIGNOZ_GLOBAL_SMTP__'
docker logs --since 5m signoz-signoz-0 2>&1 | grep -iE 'smtp|alertmanager' | tail -n 20
```

Перша команда має вивести `6`. У логах не повинно бути
`smtp_auth_username is not configured`.

### Канал у UI

**Settings → Notification Channels**: канал `demo3-email`, тип Email,
*Send resolved alerts* увімкнено. Тестовий лист доставлено успішно.

## 14. Алерти

У SigNoz створено 16 правил. Для всіх: канал `demo3-email`, мітки
`team=demo3`, `area=<infra|nginx|db|etcd>`, `severity=<critical|warning>`.
В описі кожного алерту є посилання на дашборд і на runbook у
`docs/runbooks/`.

  #    Алерт                      Тип      Умова                                         Severity
  ---- -------------------------- -------- --------------------------------------------- ----------
  1    Host not reporting         Metric   немає даних від хоста 5 хв                    critical
  2    High CPU                   Metric   CPU > 85 % протягом 10 хв                     warning
  3    High memory                Metric   RAM > 90 % протягом 5 хв                      warning
  4    Disk almost full           Metric   диск > 85 %                                   warning
  5    Disk full                  Metric   диск > 95 %                                   critical
  6    Nginx down                 Metric   `nginx_up` < 1 або немає даних 5 хв           critical
  7    Nginx 5xx errors           Log      > 10 відповідей 5xx за 5 хв                   warning
  8    PostgreSQL exporter down   Metric   `up{service.name=postgresql}` < 1, 2 хв       critical
  9    No Patroni leader          Metric   лідерів < 1 або немає даних 5 хв              critical
  10   Patroni split brain        Metric   лідерів > 1                                   critical
  11   Replica not streaming      Metric   реплік у streaming < 1, 3 хв                  warning
  12   Replication lag            Metric   відставання > 30 с протягом 5 хв              warning
  13   Failover happened          Log      у логах Patroni `promoted self to leader`     warning
  14   etcd quorum at risk        Metric   працюють < 3 вузлів etcd, 2 хв                warning
  15   etcd quorum lost           Metric   працюють < 2 вузлів etcd                      critical
  16   etcd no leader             Metric   `etcd_server_has_leader` < 1, 1 хв            critical

**Поточний стан:** усі правила створені, але **вимкнені**, доки
OpenTelemetry Collector не розгорнуто на VM у GCP. Після розгортання
їх треба ввімкнути і провести тести спрацювання (зупинка Collector-а,
навантаження CPU, заповнення диска, switchover Patroni).

У SigNoz v0.151 в UI немає експорту правил алертів. Тому їх параметри
зафіксовано в цьому розділі. Після перевстановлення SigNoz правила треба
створити заново за цією таблицею.

## 15. Heartbeat (dead man's switch) для самого SigNoz

**Навіщо.** Усі алерти надсилає сам SigNoz. Якщо впаде VM, Docker,
ClickHouse або заповниться диск, жоден алерт не прийде. Зовнішній
uptime-check SigNoz не перевірить, бо сервер у приватній мережі. Тому
SigNoz сам кожні 5 хвилин «відмічається» на зовнішньому сервісі
healthchecks.io. Якщо відмітки немає, лист надсилає вже healthchecks.io.

### healthchecks.io

  Параметр       Значення
  -------------- -------------------------------------
  Check          `demo3-signoz`
  Schedule       Simple, період **5 хв**, grace **10 хв**
  Сповіщення     email (командна пошта)

Ping URL (`https://hc-ping.com/<uuid>`) є секретом і зберігається лише на
сервері.

### Що перевіряє скрипт

Скрипт `signoz/heartbeat/signoz-heartbeat.sh` (у репозиторії),
встановлений як `/usr/local/bin/signoz-heartbeat.sh`:

1. API SigNoz відповідає: `http://localhost:8080/api/v1/health`.
2. Ingester приймає OTLP на `:4318`, відповідає `200`.
3. `/data` заповнений менше ніж на 90 %.
4. Запущено щонайменше 5 контейнерів SigNoz.

Якщо все гаразд, скрипт надсилає ping. Якщо якась перевірка не пройшла,
надсилає `/fail` з причиною, і лист приходить одразу. Якщо не працює
сама VM або cron, ping не приходить, і через 15 хв healthchecks.io
надсилає лист *DOWN*.

### Файли на сервері

  Файл                                    Призначення
  --------------------------------------- -----------------------------------------
  `/usr/local/bin/signoz-heartbeat.sh`    скрипт, права `755`
  `/opt/signoz/heartbeat.url`             ping URL, права `600`
  `/etc/cron.d/signoz-heartbeat`          запуск кожні 5 хв
  `/etc/logrotate.d/signoz-heartbeat`     ротація лога щотижня, 4 копії
  `/var/log/signoz-heartbeat.log`         лог запусків

Вміст `/etc/cron.d/signoz-heartbeat`:

``` text
*/5 * * * * root /usr/local/bin/signoz-heartbeat.sh >> /var/log/signoz-heartbeat.log 2>&1
```

### Перевірка

``` bash
/usr/local/bin/signoz-heartbeat.sh                  # очікується: ... ok disk=NN% containers=5
DISK_LIMIT=1 /usr/local/bin/signoz-heartbeat.sh     # тест: одразу лист DOWN
/usr/local/bin/signoz-heartbeat.sh                  # повернення: лист UP
tail -n 20 /var/log/signoz-heartbeat.log
```

### Обмеження

Скрипт, URL і cron лежать на root-диску EC2. Якщо Terraform перестворить
інстанс, їх треба встановити знову (або додати в `user_data`).

## 16. Дашборди

Виправлені дашборди експортовано в JSON і збережено в репозиторії,
`signoz/dashboards/`:

- `infrastructure-overview.json`: Demo3: Infrastructure Overview
- `nginx-load-balancer.json`: Demo3: Nginx & Load Balancer
- `application-observability.json`: Demo3: Application Observability
- `postgresql-replication.json`: Demo3: PostgreSQL & Replication
- `patroni-etcd-ha.json`: Demo3: Patroni & etcd HA

Відновлення: **Dashboards → + New dashboard → Import JSON**. Після змін
у UI дашборд треба знову експортувати (⋮ → Export JSON) і закомітити.
