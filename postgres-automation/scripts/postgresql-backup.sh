#!/bin/bash

set -Eeuo pipefail

BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BUCKET_PATH="gs://demo3-app-demo3-team1/backups/"
BACKUP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.sql.gz"
TEMP_FILE="${BACKUP_FILE}.tmp"

echo "PostgreSQL backup started"

# Script must run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Error: run this script as root"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# Remove temporary file if backup fails
trap 'rm -f "$TEMP_FILE"' EXIT

echo "Creating logical backup..."

# Dump all databases and global objects
sudo -u postgres pg_dumpall | gzip -c > "$TEMP_FILE"

# Verify compressed archive
gzip -t "$TEMP_FILE"

# Set ownership and permissions
chown postgres:postgres "$TEMP_FILE"
chmod 600 "$TEMP_FILE"

# Publish completed backup
mv "$TEMP_FILE" "$BACKUP_FILE"

echo "Backup created:"
echo "$BACKUP_FILE"

echo "Backup size:"
du -h "$BACKUP_FILE"

# Uploading a backup to Cloud Storage
echo "Uploading backup to Cloud Storage..."
if gcloud storage cp "$BACKUP_FILE" "$BUCKET_PATH"; then
    echo "Upload completed successfully"
else
    echo "Error: Failed to upload backup to Cloud Storage" >&2
    exit 1
fi

# Retention policy: remove local backups older than 7 days
echo "Cleaning up local backups older than 7 days..."
find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete

echo "PostgreSQL backup completed successfully"
