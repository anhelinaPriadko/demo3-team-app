# Site / API unavailable (uptime check failed)

**Alert:** GCP Uptime Check / Pingdom: `https://cinema-service-team1.pp.ua/` or `/api/v1/movies` does not return 2xx.
**Impact:** users cannot open the site. **Critical.**

Go along the chain from the outside in: DNS → TLS → Nginx → app → DB.

## 1. DNS and TLS (from your own computer)
```
nslookup cinema-service-team1.pp.ua
curl -sv -o NUL https://cinema-service-team1.pp.ua/ 2>&1 | findstr /i "HTTP/ expire issuer"
```
- The IP must be `34.40.82.240`. A different IP or NXDOMAIN means a DNS problem (Cloud DNS zone `demo3-public`, name servers at the registrar).
- `certificate has expired` / `unable to get local issuer` means a certificate problem, see step 2.3 in [nginx.md](nginx.md).

## 2. Nginx
```
curl -s -o NUL -w "%{http_code}\n" http://34.40.82.240/
```
- No response: the VM is stopped or Nginx is down. See [nginx.md](nginx.md).
- `502` / `504`: Nginx is alive but cannot reach any app server. Go to step 3.

## 3. App servers (from the Nginx VM)
```
gcloud compute ssh demo3-nginx --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.2:8080/
curl -s -o /dev/null -w "%{http_code}\n" http://10.20.1.5:8080/
sudo tail -n 30 /var/log/nginx/error.log
```
If an app server does not respond, log in to it:
```
gcloud compute ssh demo3-app-1 --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
sudo docker ps -a
sudo docker logs --tail 100 <container>
sudo docker restart <container>
```
In the logs, look for `Connection refused` / `FATAL` to `10.20.1.4:5432`: this points to a database problem (step 4).

## 4. Database
- `/` works but `/api/v1/movies` does not: most likely the database. See [postgresql-ha.md](postgresql-ha.md).
- Check the dashboard **Demo3: Patroni & etcd HA → Leaders in Cluster** (must be 1).

## After recovery
- Make sure the uptime check is green again.
- Record how many minutes the site was down: this is the consumed SLO budget (`docs/slo.md`).
