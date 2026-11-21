# Host not reporting

**Alert:** SigNoz *Host not reporting*: no metrics from `host.name` for more than 5 min.
**Possible causes:** the VM is stopped or rebooting; the OTel Collector crashed; no network path GCP → AWS (VPN).

## 1. Is the VM running
```
gcloud compute instances list --project demo3-team1 --filter="name~^demo3-" --format="table(name,zone.basename(),status)"
```
- `TERMINATED`: someone stopped the VM (for example, to save money). Start it: `gcloud compute instances start <vm> --zone <zone> --project demo3-team1`, or confirm that this was intended and close the alert.

## 2. Collector on the VM
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
sudo systemctl status otelcol-contrib --no-pager
sudo journalctl -u otelcol-contrib -n 50 --no-pager
sudo systemctl restart otelcol-contrib
```

## 3. Network to SigNoz
```
timeout 5 bash -c ':</dev/tcp/10.10.0.118/4317' && echo "SigNoz reachable" || echo "NOT reachable"
```
- Not reachable from **all** VMs: the VPN or SigNoz. Check the tunnels:
  ```
  gcloud compute vpn-tunnels list --project demo3-team1 --format="table(name,status,detailedStatus)"
  ```
  and [signoz-down.md](signoz-down.md).
- Not reachable from one VM only: the network of that VM (firewall, routes).

## 4. Full Collector reinstall
```
sudo bash /tmp/otel/scripts/deploy.sh <role> <vm>
```
(copy `otel/` to the VM first, see `otel/README.md`, or run the `deploy_observability` CI job).
