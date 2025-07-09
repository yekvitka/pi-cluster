# K3s Backup Solution

This document describes the backup solution for the k3s cluster to MinIO S3-compatible storage.

## Components

1. **k3s-backup.sh**: Main backup script that:
   - Backs up etcd database
   - Copies k3s configuration
   - Backs up k3s manifests
   - Exports kubernetes resources by namespace
   - Archives and uploads to MinIO

2. **k3s_backup_to_minio.yml**: Ansible playbook to run a one-time backup
   - Installs MinIO client if needed
   - Copies and executes the backup script
   - Shows backup results

3. **schedule_k3s_backup.yml**: Ansible playbook to set up scheduled backups
   - Installs MinIO client if needed
   - Sets up a cron job for regular backups

## Running a One-time Backup

```bash
cd /home/pi-cluster/ansible
ansible-playbook k3s_backup_to_minio.yml
```

## Setting Up Scheduled Backups

By default, the backup will run daily at 3:00 AM.

```bash
cd /home/pi-cluster/ansible
ansible-playbook schedule_k3s_backup.yml
```

To change the schedule, use the backup_schedule variable:

```bash
cd /home/pi-cluster/ansible
ansible-playbook schedule_k3s_backup.yml -e "backup_schedule='0 2 * * 0'"  # Weekly on Sunday at 2:00 AM
```

## Backup Contents

Each backup includes:
- etcd database snapshot
- k3s configuration files
- k3s manifests
- All Kubernetes resources organized by namespace

## Backup Storage

Backups are stored in the MinIO bucket `k3s-backup` with a date-based folder structure:
```
k3s-backup/YYYY-MM-DD/k3s-backup-YYYYMMDD-HHMMSS.tar.gz
```

## Restoring from Backup

To restore from a backup:

1. Download the backup archive from MinIO:
   ```bash
   mc cp minio/k3s-backup/YYYY-MM-DD/k3s-backup-YYYYMMDD-HHMMSS.tar.gz ./
   ```

2. Extract the backup:
   ```bash
   tar -xzf k3s-backup-YYYYMMDD-HHMMSS.tar.gz
   ```

3. For etcd restore, follow the official k3s documentation using the etcd snapshot:
   https://docs.k3s.io/datastore/backup-restore

   Example:
   ```bash
   systemctl stop k3s
   mkdir -p /var/lib/rancher/k3s/server/db/snapshots
   cp ./k3s-backups-YYYYMMDD-HHMMSS/etcd-backup.db /var/lib/rancher/k3s/server/db/snapshots/
   k3s server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/etcd-backup.db
   ```

4. Additional Kubernetes resources can be restored using kubectl:
   ```bash
   kubectl apply -f ./k3s-backups-YYYYMMDD-HHMMSS/resources/NAMESPACE/RESOURCE.yaml
   ```
