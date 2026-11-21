# Nginx down / Nginx 5xx errors

**Alerts:** *Nginx down* (`nginx_up < 1` or no data, critical), *Nginx 5xx errors* (> 10 in 5 min, warning).

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
- `nginx -t` fails: someone broke the configuration. Check `/etc/nginx/conf.d/app.conf`, fix it or rerun `nginx/nginx-setup.sh`.
- Nginx works but `nginx_up` = 0: the exporter is down: `sudo systemctl restart nginx-prometheus-exporter`.

## 2. 5xx errors
```
sudo tail -n 50 /var/log/nginx/error.log
sudo awk '$9 ~ /^5/ {print $9}' /var/log/nginx/access.log | sort | uniq -c
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.2:8080/
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.5:8080/
```
| Code / error in error.log | Meaning | Action |
|---|---|---|
| `502`, `connect() failed (111: Connection refused)` | the app is not listening on 8080 | [site-unavailable.md](site-unavailable.md), step 3 |
| `504`, `upstream timed out` | the app is slow (database?) | [high-cpu-memory.md](high-cpu-memory.md), [postgresql-ha.md](postgresql-ha.md) |
| `500` | error inside the application | app container logs, hand over to Anhelina |
| `no live upstreams` | both app servers are unavailable | restart the app, check the firewall rule `allow-app-from-web` |

## 3. Certificate
```
sudo certbot certificates
sudo certbot renew --dry-run
```
Browsers and uptime checks do not accept a staging certificate (`Invalid: TEST_CERT`). Reissue: `sudo CERTBOT_STAGING=0 bash nginx-setup.sh` (Let's Encrypt limit: 5 certificates per week).
