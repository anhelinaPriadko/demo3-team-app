#!/bin/bash

set -Eeuo pipefail

BACKUP_DIR="/var/backups/postgresql"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

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

echo "PostgreSQL backup completed successfully"

# Uploading a backup to Cloud Storage
gcloud storage cp "$BACKUP_FILE" gs://demo3-app-demo3-team1/backups/
