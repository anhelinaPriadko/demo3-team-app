# High CPU / High memory

**Алерти:** *High CPU* (> 85% протягом 10 хв), *High memory* (> 90% протягом 5 хв). **Warning.**
VM маленькі (e2-small: 2 shared vCPU / 2 GB), тож тривале навантаження швидко впирається в ліміти.

## 1. Що навантажує
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
top -o %CPU -b -n 1 | head -n 15
ps aux --sort=-%mem | head -n 10
free -h
sudo docker stats --no-stream        # app VM
```
- Дашборд **Demo3: Infrastructure Overview → CPU Usage by State**: високий `steal` означає, що shared vCPU забирає GCP, і всередині VM з цим нічого не зробиш. Високий `iowait` вказує на диск.

## 2. Типові випадки
| Де | Причина | Дія |
|---|---|---|
| app-1/app-2 | Java з'їдає всю пам'ять, GC | `sudo docker logs --tail 100 <container>` (OutOfMemoryError?), `sudo docker restart <container>`. Надалі обмежити `-Xmx` (≈ 60% RAM) |
| db-master/slave | важкі запити | `sudo -u postgres psql -c "SELECT pid, now()-query_start AS dur, state, left(query,80) FROM pg_stat_activity WHERE state <> 'idle' ORDER BY dur DESC LIMIT 10;"` |
| будь-яка | `apt`/`unattended-upgrades` | дочекатися завершення |
| nginx | великий трафік / сканери | `sudo tail -n 200 /var/log/nginx/access.log \| awk '{print $1}' \| sort \| uniq -c \| sort -rn \| head` |

## 3. OOM killer
```
sudo journalctl -k --since "-2h" | grep -i -E "out of memory|killed process"
```

## 4. Якщо проблема постійна
Збільшити тип VM у Terraform (`application-gcp/main.tf`, `machine_type`). Це робиться через PR до Yaroslav / Anhelina.
