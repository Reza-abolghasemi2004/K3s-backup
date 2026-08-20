#!/bin/bash

set -e

NAMESPACE="postgres"

POD="postgres-0"

DATABASE="shop"

USER="postgres"

BACKUP_DIR="./backup"

mkdir -p "$BACKUP_DIR"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")

BACKUP_FILE="$BACKUP_DIR/shop_$DATE.sql"

echo "Starting PostgreSQL backup..."

kubectl exec -n "$NAMESPACE" "$POD" -- \
  pg_dump -U "$USER" "$DATABASE" > "$BACKUP_FILE"

echo "Backup created: $BACKUP_FILE"

find "$BACKUP_DIR" -type f -name "*.sql" -mtime +1 -delete

echo "Old backups removed."
