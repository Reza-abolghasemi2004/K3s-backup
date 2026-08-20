# 🗄️ K3s PostgreSQL Backup & Restore

A hands-on Kubernetes (K3s) scenario deploying a **PostgreSQL** database for a shop application, with automated **backup**, **restore**, and **CronJob scheduling** — including a disaster-recovery drill to prove data durability.

> Assignment scenario (originally specified in Persian): deploy PostgreSQL on K3s, seed a `users` table, write backup/restore shell scripts, schedule backups with `cron`, and prove that data survives a full wipe + restore.

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Deployment](#-deployment)
- [Database Setup](#-database-setup)
- [Backup Script](#-backup-script)
- [Restore Script](#-restore-script)
- [Scheduled Backups (CronJob)](#-scheduled-backups-cronjob)
- [Disaster Recovery Test](#-disaster-recovery-test)
- [Logs](#-logs)
- [License](#-license)

---

## 📖 Overview

| Item | Detail |
|---|---|
| Platform | K3s (lightweight Kubernetes) |
| Database | PostgreSQL (StatefulSet) |
| Storage | Two PVCs — one for PostgreSQL data, one for backup archives |
| Secrets | Kubernetes `Secret` for DB credentials |
| Backup format | `pg_dump` → `.sql` → compressed `.tar.gz` |
| Retention | Backups older than **2 days** are automatically pruned |
| Schedule | CronJob runs every **15 minutes** |

---

## 🏗️ Architecture

```
                ┌─────────────────────────────┐
                │   Namespace (postgres/namespace.yaml) │
                │                              │
   Secret ─────▶│  ┌────────────────────┐      │
 (DB creds)     │  │  StatefulSet       │      │
                │  │  PostgreSQL Pod    │◀─────┼── Service (ClusterIP)
   PVC ────────▶│  │                    │      │
 (data volume)  │  └────────────────────┘      │
                │            ▲                 │
                │            │ pg_dump          │
                │   ┌────────┴─────────┐        │
                │   │ CronJob            │       │
   Backup PVC ─▶│   │ (every 15 min)     │       │
 (archive       │   │ runs backup.sh     │       │
  volume)       │   └───────────────────┘       │
                └─────────────────────────────┘
                             │
                             ▼
                  backup/*.tar.gz + logs/
```

---

## 📁 Project Structure

```
K3s-backup/
├── postgres/
│   ├── namespace.yaml       # Namespace for the PostgreSQL workload
│   ├── secret.yaml            # DB credentials (user/password) as a K8s Secret
│   ├── pvc.yaml                 # PersistentVolumeClaim for PostgreSQL data
│   ├── statefulset.yaml      # PostgreSQL StatefulSet deployment
│   └── service.yaml            # ClusterIP Service exposing PostgreSQL
├── backup/
│   ├── backup-pvc.yaml       # PersistentVolumeClaim for storing backup archives
│   ├── cronjob.yaml            # CronJob scheduling automated backups
│   └── shop_*.sql               # Generated backup dumps
├── scripts/
│   ├── backup.sh                # Dumps DB → tar.gz, prunes backups > 2 days old
│   └── restore.sh              # Restores DB from the latest (or chosen) backup
├── logs/                          # cron.log & backup.log output
├── LICENSE
└── README.md
```

---

## ✅ Prerequisites

- A running **K3s** cluster (`kubectl` configured against it)
- `kubectl` CLI access
- Sufficient storage for the PVC (check `pvc.yaml` for the requested size)
- Basic familiarity with PostgreSQL (`psql`, `pg_dump`, `pg_restore`)

---

## 🚀 Deployment

Apply the manifests in order — namespace and secrets first, then storage, then the database itself:

```bash
# 1. Create the namespace
kubectl apply -f postgres/namespace.yaml

# 2. Create the Secret (DB password) and PVC (data volume)
kubectl apply -f postgres/secret.yaml
kubectl apply -f postgres/pvc.yaml

# 3. Deploy PostgreSQL as a StatefulSet
kubectl apply -f postgres/statefulset.yaml

# 4. Expose it internally via a Service
kubectl apply -f postgres/service.yaml

# 5. Create the PVC that will store backup archives
kubectl apply -f backup/backup-pvc.yaml
```

Verify everything is healthy:

```bash
kubectl get ns
kubectl get pods,svc,pvc,secret -n <namespace>
kubectl logs -n <namespace> <postgres-pod-name>
```

---

## 🧬 Database Setup

Once the pod is `Running`, connect to PostgreSQL and create the shop database schema:

```bash
kubectl exec -it -n <namespace> <postgres-pod-name> -- psql -U <db-user> -d <db-name>
```

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (full_name, email) VALUES
    ('Ali Rezaei', 'ali@example.com'),
    ('Sara Ahmadi', 'sara@example.com'),
    ('Reza Karimi', 'reza@example.com');

SELECT * FROM users;
```

---

## 💾 Backup Script

`scripts/backup.sh` performs a `pg_dump`, compresses the result to `.tar.gz`, and prunes anything older than **2 days**.

**Typical flow inside the script:**

```bash
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="shop_${TIMESTAMP}.sql"

pg_dump -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" -F p -f "backup/${FILENAME}"
tar -czf "backup/${FILENAME}.tar.gz" -C backup "${FILENAME}"

# Remove raw .sql after compressing
rm -f "backup/${FILENAME}"

# Retention: delete archives older than 2 days
find backup/ -name "*.tar.gz" -mtime +2 -exec rm -f {} \;

echo "$(date) - Backup completed: ${FILENAME}.tar.gz" >> logs/backup.log
```

Run manually:

```bash
./scripts/backup.sh
```

---

## ♻️ Restore Script

`scripts/restore.sh` restores the database from a chosen (or the most recent) backup archive.

```bash
./scripts/restore.sh backup/shop_2026-08-20_10-27-56.sql.tar.gz
```

**Typical flow inside the script:**

```bash
ARCHIVE=$1
TMP_DIR=$(mktemp -d)

tar -xzf "$ARCHIVE" -C "$TMP_DIR"
SQL_FILE=$(find "$TMP_DIR" -name "*.sql")

psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" -f "$SQL_FILE"

echo "$(date) - Restore completed from: ${ARCHIVE}" >> logs/backup.log
rm -rf "$TMP_DIR"
```

---

## ⏰ Scheduled Backups (CronJob)

`backup/cronjob.yaml` schedules `backup.sh` to run automatically **every 15 minutes** inside the cluster, mounting the `backup-pvc` volume so archives persist independently of the database pod:

```yaml
schedule: "*/15 * * * *"
```

Apply it:

```bash
kubectl apply -f backup/cronjob.yaml
```

Check job history:

```bash
kubectl get cronjob,jobs -n <namespace>
kubectl logs -n <namespace> job/<job-name>
```

---

## 🧪 Disaster Recovery Test

To prove the backup/restore pipeline actually protects data:

1. **Insert a new record** into `users`.
2. **Run a backup** (`./scripts/backup.sh`) — captures the new record.
3. **Wipe the data**, including the underlying PVC, to simulate total loss.
4. **Confirm data loss** — `SELECT * FROM users;` returns nothing / table doesn't exist.
5. **Run the restore script** against the latest backup archive.
6. **Confirm recovery** — the new record (and all prior data) is present and intact.

📸 Screenshots documenting the "before" (data present), "after wipe" (data gone, including on the PVC), and "after restore" (data recovered) states should be captured for submission.

---

## 📜 Logs

| File | Purpose |
|---|---|
| `logs/backup.log` | Timestamped record of every backup/restore run |
| `logs/cron.log` | CronJob execution history |

Tail logs in real time:

```bash
tail -f logs/backup.log
```

---

## 📄 License

See [LICENSE](./LICENSE) for details.
