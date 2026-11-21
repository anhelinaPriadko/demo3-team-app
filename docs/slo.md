# Demo 3 — SLI / SLO

Сервіс: **Cinema Booking**, `https://cinema-service-team1.pp.ua` (Nginx `demo3-nginx` → `demo3-app-1`, `demo3-app-2` → PostgreSQL HA).
Вікно оцінки: **30 днів, ковзне**. Власник: Observability & Reliability.

## SLI і SLO

| # | SLI (що міряємо) | Як рахується | Джерело | SLO | Бюджет помилок за 30 днів |
|---|---|---|---|---|---|
| 1 | **Доступність ззовні** | успішні перевірки / усі перевірки. Успіх = HTTP 2xx і сторінка містить `Cinema Booking` | GCP Uptime Check (згодом Pingdom), кожну хвилину з ≥ 3 регіонів | **99.5%** | 216 хв (3 год 36 хв) |
| 2 | **Доступність API (app + БД)** | те саме для `GET /api/v1/movies` (відповідь 2xx) | GCP Uptime Check | **99.0%** | 432 хв (7 год 12 хв) |
| 3 | **Успішність запитів на сервері** | `1 − (кількість 5xx / усі запити)` у Nginx access log | SigNoz, логи `demo3-nginx` | **99.5%** | 0.5% запитів |
| 4 | **Латентність** | частка запитів, швидших за 1 с (p95 < 1 с) | SigNoz APM (`demo3-java-app`, Java Agent) | **95% < 1 с** | 5% повільних запитів |

SLI 4 починає рахуватися після інтеграції Java Agent. До того латентність не входить у звіт.

### Цілі для даних (Data tier)
| Ціль | Значення | Як перевіряється |
|---|---|---|
| RPO (скільки даних можна втратити) | ≤ 24 год | щоденний бекап 03:00 з репліки в GCS |
| RTO (за скільки відновити) | ≤ 1 год | регулярний тест відновлення з GCS |
| Автоматичний failover | ≤ 60 с без лідера | Patroni (`ttl: 30`), алерт *No Patroni leader* |

## Чому такі цифри
- 99.5% для демо-інфраструктури з однією Nginx-VM (single point of failure) — реалістична ціль. 99.9% (43 хв на місяць) не витримав би навіть один перезапуск Nginx-VM разом із перевипуском сертифіката.
- API має нижчу ціль, бо залежить від БД і failover-у.

## Де дивитися
- SLI 1–2: Cloud Console → Monitoring → **Uptime checks** → потрібна перевірка → *Uptime %*. Після схвалення Pingdom: **Reports → Uptime**.
- SLI 3: SigNoz, Logs → **Add query**:
  - A: count, filter `host.name = 'demo3-nginx' AND log.file.path = '/var/log/nginx/access.log' AND severity_number >= 17`
  - B: count, filter `host.name = 'demo3-nginx' AND log.file.path = '/var/log/nginx/access.log'`
  - формула `(1 - A / B) * 100`, інтервал — останні 30 днів
- SLI 4: SigNoz → Services → `demo3-java-app` → p95 latency.

## Політика бюджету помилок
| Витрачено бюджету | Дії |
|---|---|
| < 50% | працюємо як звичайно |
| 50–100% | ризикові зміни (міграції БД, перевстановлення VM) лише з планом відкату й у *Planned Downtime* |
| > 100% | заморозка нових фіч до відновлення. Розбір причин (postmortem) і задачі на усунення |

Кожен інцидент, що з'їв > 25% місячного бюджету, отримує postmortem (шаблон у `runbooks/README.md`).

## Перегляд
SLO переглядаються раз на місяць або після кожного великого інциденту.
