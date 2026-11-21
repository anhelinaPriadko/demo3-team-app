# Disk almost full / Disk full

**Алерти:** *Disk almost full* (> 85%, warning), *Disk full* (> 95%, critical) для `host.name` + `mountpoint`.
Повний диск зупиняє PostgreSQL (`/data`), логування й Docker.

## 1. Що займає місце
```
gcloud compute ssh <vm> --zone <zone> --project demo3-team1 --tunnel-through-iap
df -h
sudo du -xh --max-depth=2 / 2>/dev/null | sort -rh | head -n 20
sudo journalctl --disk-usage
```

## 2. Безпечне звільнення місця
```
sudo journalctl --vacuum-size=200M
sudo apt-get clean
sudo docker system prune -f                    # app VM: зупинені контейнери, dangling images
sudo find /var/backups/postgresql -name 'backup_*.sql.gz' -mtime +3 -print -delete   # db-slave, лише локальні копії (є в GCS)
sudo find /var/log -name '*.gz' -mtime +7 -print -delete
```
⚠️ **Ніколи не видаляй** файли в `/data/postgresql` чи `/var/lib/postgresql/16/main/pg_wal` вручну: це зламає базу.

## 3. `/data` на DB-вузлі росте через WAL
```
sudo du -sh /var/lib/postgresql/16/main/pg_wal
sudo -u postgres psql -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained FROM pg_replication_slots;"
```
Неактивний слот із великим `retained` означає, що репліка відстала або зникла, і WAL накопичується. Див. [postgresql-ha.md](postgresql-ha.md) (Replica not streaming). Слот видаляє Diana або Patroni, не вручну.

## 4. Збільшити диск (якщо чистити нічого)
Data-диск (`/data`): збільшити `db_data_disk_size` у Terraform, потім на VM:
```
sudo resize2fs /dev/disk/by-id/google-data
```
Boot-диск — через `boot_disk_size` у модулі compute.
