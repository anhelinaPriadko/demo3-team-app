# Host not reporting

**Алерт:** SigNoz *Host not reporting*: від `host.name` більше 5 хв немає метрик.
**Можливі причини:** VM вимкнена або перезавантажується; впав OTel Collector; немає мережі GCP → AWS (VPN).

## 1. Чи увімкнена VM
```
gcloud compute instances list --project demo3-team1 --filter="name~^demo3-" --format="table(name,zone.basename(),status)"
```
- `TERMINATED` — хтось вимкнув VM (наприклад, щоб заощадити). Увімкнути: `gcloud compute instances start <vm> --zone <zone> --project demo3-team1` або підтвердити, що так і задумано, і закрити алерт.

## 2. Collector на VM
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
sudo systemctl status otelcol-contrib --no-pager
sudo journalctl -u otelcol-contrib -n 50 --no-pager
sudo systemctl restart otelcol-contrib
```

## 3. Мережа до SigNoz
```
timeout 5 bash -c ':</dev/tcp/10.10.0.118/4317' && echo "SigNoz reachable" || echo "NOT reachable"
```
- Not reachable з **усіх** VM — VPN або SigNoz. Перевір тунелі:
  ```
  gcloud compute vpn-tunnels list --project demo3-team1 --format="table(name,status,detailedStatus)"
  ```
  і [signoz-down.md](signoz-down.md).
- Not reachable лише з однієї VM — мережа цієї VM (firewall, маршрути).

## 4. Повне переналаштування Collector-а
```
sudo bash /tmp/otel/scripts/deploy.sh <role> <vm>
```
(спершу скопіювати `otel/` на VM, див. `otel/README.md`).
