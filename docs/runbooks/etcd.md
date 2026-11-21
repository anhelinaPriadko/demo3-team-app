# etcd quorum / no leader

**Alerts:** *etcd quorum at risk* (< 3 members, warning), *etcd quorum lost* (< 2, critical), *etcd no leader* (critical).
Members: `etcd1` = db-master (10.20.1.4), `etcd2` = db-slave (10.20.1.3), `etcd3` = db-witness (10.20.1.6). Quorum = 2 of 3.
**Without an etcd quorum Patroni cannot keep a leader: the database becomes read-only.**

## 1. Cluster state (from any DB node)
```
gcloud compute ssh demo3-db-master --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
ENDPOINTS=http://10.20.1.4:2379,http://10.20.1.3:2379,http://10.20.1.6:2379
etcdctl --endpoints=$ENDPOINTS endpoint health
etcdctl --endpoints=$ENDPOINTS endpoint status -w table
etcdctl --endpoints=$ENDPOINTS member list -w table
```

## 2. A member is unavailable
1. Is the VM running: `gcloud compute instances list --project demo3-team1 --filter="name~db"`.
2. On the VM:
   ```
   sudo systemctl status etcd --no-pager
   sudo journalctl -u etcd -n 80 --no-pager
   sudo systemctl restart etcd
   ```
3. Network between the nodes (firewall `allow-etcd-patroni`: 2379, 2380, 8008, tags `db` / `etcd`):
   ```
   timeout 3 bash -c ':</dev/tcp/10.20.1.3/2380' && echo peer ok
   ```

## 3. Quorum lost (only 1 member alive)
- First bring up any second member (step 2). The quorum comes back on its own and Patroni elects a leader.
- Do **not** remove or recreate members (`member remove`, deleting `/var/lib/etcd`) without Diana: the cluster can be lost.

## 4. Check after recovery
- Dashboard **Demo3: Patroni & etcd HA**: *etcd Members Up (of 3)* = 3, *etcd Has Leader* = 1, *Leaders in Cluster* = 1.
