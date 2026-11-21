# PostgreSQL HA (Patroni)

**Алерти:** *PostgreSQL exporter down*, *No Patroni leader*, *Patroni split brain*, *Replica not streaming*, *Replication lag*, *Failover happened*.
Вузли: `demo3-db-master` (10.20.1.4), `demo3-db-slave` (10.20.1.3), etcd-witness. Кластер Patroni: `demo3-pg-cluster`.
Власник Data tier — Diana. Будь-які дії, що змінюють лідера, координуй з нею.

```
gcloud compute ssh demo3-db-master --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
sudo patronictl -c /etc/patroni/config.yml list
```
Нормальний стан: один `Leader` (`running`), одна `Replica` (`streaming`), `Lag in MB` ≈ 0.

## No Patroni leader (critical)
Записи в БД неможливі.
1. `patronictl list` на обох вузлах. Якщо команда висить або каже про DCS, проблема в etcd ([etcd.md](etcd.md)): без кворуму etcd Patroni навмисно не призначає лідера.
2. Стан Patroni:
   ```
   sudo systemctl status patroni --no-pager
   sudo journalctl -u patroni -n 80 --no-pager
   ```
3. Якщо etcd здоровий, а лідера немає: `sudo systemctl restart patroni` на вузлі з найсвіжішими даними (зазвичай колишній лідер).

## Patroni split brain (critical)
`patroni_primary` = 1 на обох вузлах. Ризик розбіжності даних.
1. Негайно повідомити Diana.
2. `patronictl list`: справжній лідер той, кого бачить etcd.
3. На «зайвому» лідері: `sudo systemctl restart patroni`. Patroni понизить його і, оскільки `use_pg_rewind: true`, зробить pg_rewind.

## Replica not streaming / Replication lag (warning)
```
sudo -u postgres psql -h /var/run/postgresql -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"   # на лідері
sudo -u postgres psql -h /var/run/postgresql -c "SELECT status, sender_host FROM pg_stat_wal_receiver;"                      # на репліці
sudo journalctl -u patroni -n 80 --no-pager                                                                                   # на репліці
```
- Репліка вимкнена: `gcloud compute instances start demo3-db-slave ...`.
- Репліка не може наздогнати (WAL уже видалено): `sudo patronictl -c /etc/patroni/config.yml reinit demo3-pg-cluster pg_node_2`. Це перезаливка репліки з лідера; робиться разом з Diana.
- Тимчасовий lag під час великих записів чи бекапу (`pg_dumpall` о 03:00) нормальний, якщо минає сам.

## Failover happened (warning)
Patroni сам переключив лідера.
1. `patronictl list`: хто новий лідер, чи повернулася колишня нода як Replica.
2. `sudo journalctl -u patroni --since "-30min" --no-pager | grep -iE "promot|demot|lock"` на обох вузлах.
3. Перевірити, що застосунок пише в нового лідера. Якщо JDBC URL вказує лише на `10.20.1.4`, а лідер тепер `10.20.1.3`, записи падатимуть: потрібен multi-host URL (`targetServerType=primary`), це зона Anhelina.
4. Повернути лідера назад (не обов'язково): `sudo patronictl -c /etc/patroni/config.yml switchover --leader <поточний> --candidate <бажаний> --force`.

## PostgreSQL exporter down (critical для моніторингу)
```
sudo systemctl status postgres-exporter --no-pager
sudo journalctl -u postgres-exporter -n 30 --no-pager
curl -s 127.0.0.1:9187/metrics | grep ^pg_up
```
- `pg_up 0` + `Peer authentication failed` — немає рядків `pg_hba` / `pg_ident` для `otel_monitor` (див. `otel/README.md`).
- Сама БД не працює — розділи вище.
