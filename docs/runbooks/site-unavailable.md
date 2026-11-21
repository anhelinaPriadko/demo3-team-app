# Site / API unavailable (uptime check failed)

**Алерт:** GCP Uptime Check / Pingdom: `https://cinema-service-team1.pp.ua/` або `/api/v1/movies` не відповідає 2xx.
**Вплив:** користувачі не можуть відкрити сайт. **Critical.**

Іди по ланцюжку зовні всередину: DNS → TLS → Nginx → app → БД.

## 1. DNS і TLS (зі свого комп'ютера)
```
nslookup cinema-service-team1.pp.ua
curl -sv -o NUL https://cinema-service-team1.pp.ua/ 2>&1 | findstr /i "HTTP/ expire issuer"
```
- IP має бути `34.40.82.240`. Інший IP або NXDOMAIN — проблема DNS (Cloud DNS зона `demo3-public`, NS у реєстратора).
- `certificate has expired` / `unable to get local issuer` — проблема сертифіката, крок 2.3 у [nginx.md](nginx.md).

## 2. Nginx
```
curl -s -o NUL -w "%{http_code}\n" http://34.40.82.240/
```
- Немає відповіді — VM вимкнена або Nginx лежить. Див. [nginx.md](nginx.md).
- `502` / `504` — Nginx живий, але не бачить жодного app-сервера. Іди до кроку 3.

## 3. App-сервери (з Nginx-VM)
```
gcloud compute ssh demo3-nginx --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.2:8080/
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.5:8080/
sudo tail -n 30 /var/log/nginx/error.log
```
Якщо app не відповідає, заходимо на нього:
```
gcloud compute ssh demo3-app-1 --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
sudo docker ps -a
sudo docker logs --tail 100 <container>
sudo docker restart <container>
```
У логах шукати `Connection refused` / `FATAL` до `10.20.1.4:5432`: це означає проблему з БД (крок 4).

## 4. БД
- `/` працює, а `/api/v1/movies` ні — найімовірніше БД. Див. [postgresql-ha.md](postgresql-ha.md).
- Перевір дашборд **Demo3: Patroni & etcd HA → Leaders in Cluster** (має бути 1).

## Після відновлення
- Переконайся, що uptime check знову зелений.
- Запиши, скільки хвилин сайт не працював: це витрачений бюджет SLO (`docs/slo.md`).
