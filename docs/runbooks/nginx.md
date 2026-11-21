# Nginx down / Nginx 5xx errors

**Алерти:** *Nginx down* (`nginx_up < 1` або немає даних, critical), *Nginx 5xx errors* (> 10 за 5 хв, warning).

```
gcloud compute ssh demo3-nginx --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
```

## 1. Nginx down
```
sudo systemctl status nginx --no-pager
sudo nginx -t
sudo journalctl -u nginx -n 50 --no-pager
sudo systemctl restart nginx
curl -s 127.0.0.1:8081/stub_status
```
- `nginx -t` з помилкою — хтось зламав конфіг. Подивитися `/etc/nginx/conf.d/app.conf`, виправити або перезапустити `nginx/nginx-setup.sh`.
- Nginx працює, а `nginx_up` = 0 — впав exporter: `sudo systemctl restart nginx-prometheus-exporter`.

## 2. 5xx errors
```
sudo tail -n 50 /var/log/nginx/error.log
sudo awk '$9 ~ /^5/ {print $9}' /var/log/nginx/access.log | sort | uniq -c
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.2:8080/
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.5:8080/
```
| Код / помилка в error.log | Значення | Дія |
|---|---|---|
| `502`, `connect() failed (111: Connection refused)` | app не слухає 8080 | [site-unavailable.md](site-unavailable.md), крок 3 |
| `504`, `upstream timed out` | app повільний (БД?) | [high-cpu-memory.md](high-cpu-memory.md), [postgresql-ha.md](postgresql-ha.md) |
| `500` | помилка всередині застосунку | логи контейнера app, передати Anhelina |
| `no live upstreams` | обидва app недоступні | перезапустити app, перевірити firewall `allow-app-from-web` |

## 3. Сертифікат
```
sudo certbot certificates
sudo certbot renew --dry-run
```
Staging-сертифікат (`Invalid: TEST_CERT`) браузери й uptime-check не приймають. Перевипуск: `sudo CERTBOT_STAGING=0 bash nginx-setup.sh` (ліміт Let's Encrypt — 5 сертифікатів на тиждень).
