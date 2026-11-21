# PostgreSQL HA (Patroni)

**Alerts:** *PostgreSQL exporter down*, *No Patroni leader*, *Patroni split brain*, *Replica not streaming*, *Replication lag*, *Failover happened*.
Nodes: `demo3-db-master` (10.20.1.4), `demo3-db-slave` (10.20.1.3), etcd witness (10.20.1.6). Patroni cluster: `demo3-pg-cluster`.
The data tier owner is Diana. Coordinate any action that changes the leader with her.

```
gcloud compute ssh demo3-db-master --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
sudo patronictl -c /etc/patroni/config.yml list
```
Healthy state: one `Leader` (`running`), one `Replica` (`streaming`), `Lag in MB` ≈ 0.

## No Patroni leader (critical)
Writes to the database are impossible.
1. Run `patronictl list` on both nodes. If the command hangs or mentions the DCS, the problem is etcd ([etcd.md](etcd.md)): without an etcd quorum Patroni deliberately does not elect a leader.
2. Patroni state:
   ```
   sudo systemctl status patroni --no-pager
   sudo journalctl -u patroni -n 80 --no-pager
   ```
3. If etcd is healthy but there is no leader: `sudo systemctl restart patroni` on the node with the most recent data (usually the former leader).

## Patroni split brain (critical)
`patroni_primary` = 1 on both nodes. Risk of diverging data.
1. Notify Diana immediately.
2. `patronictl list`: the real leader is the one etcd sees.
3. On the extra leader: `sudo systemctl restart patroni`. Patroni demotes it and, because `use_pg_rewind: true`, runs pg_rewind.

## Replica not streaming / Replication lag (warning)
```
sudo -u postgres psql -h /var/run/postgresql -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"   # on the leader
sudo -u postgres psql -h /var/run/postgresql -c "SELECT status, sender_host FROM pg_stat_wal_receiver;"                      # on the replica
sudo journalctl -u patroni -n 80 --no-pager                                                                                   # on the replica
```
- The replica is stopped: `gcloud compute instances start demo3-db-slave ...`.
- The replica cannot catch up (WAL already removed): `sudo patronictl -c /etc/patroni/config.yml reinit demo3-pg-cluster pg_node_2`. This rebuilds the replica from the leader; do it together with Diana.
- Temporary lag during heavy writes or the backup (`pg_dumpall` at 03:00) is normal if it goes away on its own.

## Failover happened (warning)
Patroni switched the leader on its own.
1. `patronictl list`: who is the new leader, and did the former node come back as a Replica.
2. `sudo journalctl -u patroni --since "-30min" --no-pager | grep -iE "promot|demot|lock"` on both nodes.
3. Check that the application writes to the new leader. If the JDBC URL points only to `10.20.1.4` and the leader is now `10.20.1.3`, writes will fail: a multi-host URL is needed (`targetServerType=primary`), which is Anhelina's area.
4. Move the leader back (optional): `sudo patronictl -c /etc/patroni/config.yml switchover --leader <current> --candidate <desired> --force`.

## PostgreSQL exporter down (critical for monitoring)
```
sudo systemctl status postgres-exporter --no-pager
sudo journalctl -u postgres-exporter -n 30 --no-pager
curl -s 127.0.0.1:9187/metrics | grep ^pg_up
```
- `pg_up 0` + `Peer authentication failed`: the `pg_hba` / `pg_ident` lines for `otel_monitor` are missing (see `otel/README.md`).
- The database itself is down: see the sections above.
