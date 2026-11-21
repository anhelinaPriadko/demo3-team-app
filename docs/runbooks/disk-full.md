# Disk almost full / Disk full

**Alerts:** *Disk almost full* (> 85%, warning), *Disk full* (> 95%, critical) per `host.name` + `mountpoint`.
A full disk stops PostgreSQL (`/data`), logging and Docker.

## 1. What is using the space
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
df -h
sudo du -xh --max-depth=2 / 2>/dev/null | sort -rh | head -n 20
sudo journalctl --disk-usage
```

## 2. Safe cleanup
```
sudo journalctl --vacuum-size=200M
sudo apt-get clean
sudo docker system prune -f                    # app VM: stopped containers, dangling images
sudo find /var/backups/postgresql -name 'backup_*.sql.gz' -mtime +3 -print -delete   # db-slave, local copies only (they are in GCS)
sudo find /var/log -name '*.gz' -mtime +7 -print -delete
```
⚠️ **Never delete** files in `/data/postgresql` or `/var/lib/postgresql/16/main/pg_wal` by hand: this breaks the database.

## 3. `/data` on a DB node grows because of WAL
```
sudo du -sh /var/lib/postgresql/16/main/pg_wal
sudo -u postgres psql -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;"
```
An inactive slot with a large `retained` value means the replica has fallen behind or is gone, and WAL keeps accumulating. See [postgresql-ha.md](postgresql-ha.md) (Replica not streaming). The slot is removed by Diana or by Patroni, not by hand.

## 4. Grow the disk (if there is nothing to clean)
Data disk (`/data`): increase `db_data_disk_size` in Terraform, then on the VM:
```
sudo resize2fs /dev/disk/by-id/google-data
```
Boot disk: through `boot_disk_size` in the compute module.
