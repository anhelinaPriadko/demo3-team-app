# etcd quorum / no leader

**Алерти:** *etcd quorum at risk* (< 3 учасників, warning), *etcd quorum lost* (< 2, critical), *etcd no leader* (critical).
Учасники: `etcd1` = db-master (10.20.1.4), `etcd2` = db-slave (10.20.1.3), `etcd3` = db-witness. Кворум = 2 з 3.
**Без кворуму etcd Patroni не може тримати лідера: БД переходить у read-only.**

## 1. Стан кластера (з будь-якого DB-вузла)
```
gcloud compute ssh demo3-db-master --zone europe-west3-a --project demo3-team1 --tunnel-through-iap
ENDPOINTS=http://10.20.1.4:2379,http://10.20.1.3:2379,http://10.20.1.6:2379
etcdctl --endpoints=$ENDPOINTS endpoint health
etcdctl --endpoints=$ENDPOINTS endpoint status -w table
etcdctl --endpoints=$ENDPOINTS member list -w table
```

## 2. Учасник недоступний
1. Чи увімкнена VM: `gcloud compute instances list --project demo3-team1 --filter="name~db"`.
2. На VM:
   ```
   sudo systemctl status etcd --no-pager
   sudo journalctl -u etcd -n 80 --no-pager
   sudo systemctl restart etcd
   ```
3. Мережа між вузлами (firewall `allow-etcd-patroni`: 2379, 2380, 8008, теги `db` / `etcd`):
   ```
   timeout 3 bash -c ':</dev/tcp/10.20.1.3/2380' && echo peer ok
   ```

## 3. Кворум втрачено (живий лише 1 учасник)
- Насамперед підняти будь-якого другого учасника (крок 2). Кворум повернеться сам, Patroni обере лідера.
- **Не** видаляй і не перестворюй учасників (`member remove`, видалення `/var/lib/etcd`) без Diana: можна втратити кластер.

## 4. Перевірка після відновлення
- Дашборд **Demo3: Patroni & etcd HA**: *etcd Members Up (of 3)* = 3, *etcd Has Leader* = 1, *Leaders in Cluster* = 1.
