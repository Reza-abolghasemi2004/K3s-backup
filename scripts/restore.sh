#!/bin/bash

set -e

NAMESPACE="postgres"

POD="postgres-0"

DATABASE="shop"

USER="postgres"

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ./scripts/restore.sh backup/shop_YYYY-MM-DD_HH-MM-SS.sql"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "Starting restore..."

kubectl exec -i -n "$NAMESPACE" "$POD" -- \
    psql \
    -v ON_ERROR_STOP=1 \
    -U "$USER" \
    "$DATABASE" < "$BACKUP_FILE"

echo "Restore completed successfully."
