# High CPU / High memory

**Alerts:** *High CPU* (> 85% for 10 min), *High memory* (> 90% for 5 min). **Warning.**
The VMs are small (e2-small / e2-medium: 2 shared vCPUs, 2–4 GB RAM), so sustained load quickly hits the limits.

## 1. What is causing the load
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
top -o %CPU -b -n 1 | head -n 15
ps aux --sort=-%mem | head -n 10
free -h
sudo docker stats --no-stream        # app VM
```
- Dashboard **Demo3: Infrastructure Overview → CPU Usage by State**: high `steal` means GCP is taking the shared vCPU away, and nothing can be done about it inside the VM. High `iowait` points to the disk.

## 2. Typical cases
| Where | Cause | Action |
|---|---|---|
| app-1/app-2 | Java uses all memory, GC | `sudo docker logs --tail 100 <container>` (OutOfMemoryError?), `sudo docker restart <container>`. Later limit `-Xmx` (≈ 60% of RAM) |
| db-master/slave | heavy queries | `sudo -u postgres psql -c "SELECT pid, now()-query_start AS dur, state, left(query,80) FROM pg_stat_activity WHERE state <> 'idle' ORDER BY dur DESC LIMIT 10;"` |
| any | `apt`/`unattended-upgrades` | wait until it finishes |
| nginx | heavy traffic / scanners | `sudo tail -n 200 /var/log/nginx/access.log \| awk '{print $1}' \| sort \| uniq -c \| sort -rn \| head` |

## 3. OOM killer
```
sudo journalctl -k --since "-2h" | grep -i -E "out of memory|killed process"
```

## 4. If the problem is permanent
Increase the VM type in Terraform (`application-gcp/main.tf`, `machine_type`). This is done through a PR to Yaroslav / Anhelina.
