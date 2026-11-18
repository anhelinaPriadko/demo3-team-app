# PostgreSQL Infrastructure

Production-ready PostgreSQL High Availability cluster managed by **Patroni** and **etcd**, deployed on Ubuntu with automated backups to Google Cloud Storage (GCS).

## Architecture Overview

* **Cluster Name**: `demo3-pg-cluster`
* **Components**:
  * **etcd Cluster (3 nodes)**: Distributed key-value store ensuring consensus and leader election.
  * **PostgreSQL (Master & Slave via Patroni)**: Active-passive HA replication setup.
  * **Cloud Storage**: Automated remote backups pushed to the GCS bucket (`gs://demo3-app-demo3-team1/backups/`) from the replica node.

---

## Node Topology & IP Addressing

| Role / Component | Hostname | IP Address |
| :--- | :--- | :--- |
| **Master Node** (PostgreSQL + Patroni + etcd) | `demo3-db-master` | `10.20.1.4` |
| **Slave Node** (PostgreSQL + Patroni + etcd) | `demo3-db-slave` | `10.20.1.3` |
| **Dedicated etcd Node** (etcd only) | — | `10.20.1.6` |

---

## Scripts Description & Execution Guide

All deployment and backup scripts require root privileges (`sudo`) and should be executed on their respective target virtual machines.

### 1. Dedicated etcd Node Setup (`deploy/setup_etcd_node.sh`)
* **Target Machine**: `10.20.1.6`
* **What it does**: 
  * Installs `etcd-server` and `etcd-client` packages.
  * Configures `/etc/default/etcd` with peer/client URLs and the 3-node cluster topology.
  * Enables, starts, and verifies the health of the etcd service.
* **How to run**:
  ```bash
  sudo bash deploy/setup_etcd_node.sh
  ```

### 2. Master Node Setup (`deploy/setup_master_node.sh`)
* **Target Machine**: `10.20.1.4` (`demo3-db-master`)
* **What it does**: 
  * Installs local `etcd`, PostgreSQL 16, Patroni, and Python dependencies.
  * Disables standard systemd PostgreSQL startup, delegating full control to Patroni.
  * Prepares a clean data directory and generates the Patroni configuration (`/etc/patroni/config.yml`) for `pg_node_1` (Leader).
  * Starts Patroni to initialize the primary database cluster.
* **How to run**:
  ```bash
  sudo bash deploy/setup_master_node.sh
  ```

### 3. Slave Node Setup (`deploy/setup_slave_node.sh`)
* **Target Machine**: `10.20.1.3` (`demo3-db-slave`)
* **What it does**: 
  * Installs local `etcd`, PostgreSQL 16, Patroni, and dependencies.
  * Disables standard PostgreSQL service and provisions a clean data directory.
  * Configures Patroni for `pg_node_2` (Replica) pointing to the shared etcd endpoints.
  * Starts Patroni to join the cluster as a streaming replica.
* **How to run**:
  ```bash
  sudo bash deploy/setup_slave_node.sh
  ```

### 4. Automated Backup Script (`scripts/pg_backup_to_gcs.sh`)
* **Target Machine**: `10.20.1.3` (Slave node)
* **What it does**: 
  * Performs a full logical backup (`pg_dumpall`) from the PostgreSQL instance.
  * Compresses the output into a `.sql.gz` archive and verifies its integrity (`gzip -t`).
  * Securely uploads the backup to Google Cloud Storage (`gs://demo3-app-demo3-team1/backups/`).
  * Applies a retention policy by cleaning up local backup files older than 7 days.
* **How to run manually**:
  ```bash
  sudo bash scripts/pg_backup_to_gcs.sh
  ```
* **Automation via Cron**: 
  To run the backup automatically every day at 03:00 AM, open crontab (`sudo crontab -e`) and add:
  ```cron
  0 3 * * * /usr/local/bin/pg_backup_to_gcs.sh >> /var/log/pg_backup.log 2>&1
  ```

### 5. Replication & Status Verification (`scripts/verify_replication.sh`)
* **Target Machine**: Any database node (`master` or `slave`)
* **What it does**: 
  * Checks system cluster status via `pg_lsclusters`.
  * Detects the current node role dynamically using `pg_is_in_recovery()`.
  * If run on a **Slave**: displays WAL receiver status (`pg_stat_wal_receiver`).
  * If run on a **Master**: inspects active streaming replicas (`pg_stat_replication`) and replication slots (`pg_replication_slots`).
* **How to run**:
  ```bash
  sudo bash scripts/verify_replication.sh
  ```

---

## Cluster Management

### Check Patroni Cluster Status
To view active leaders, replicas, timelines, and replication lag across the cluster, run:
```bash
sudo -E patronictl -c /etc/patroni/config.yml list
```
