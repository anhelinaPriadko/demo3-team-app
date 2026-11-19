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
