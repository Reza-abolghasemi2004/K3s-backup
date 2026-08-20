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

if [ ! -f "$BACKUP_FILE"]; then 
	echo "Backup file not found!"
	exit 1
fi

echo "starting restore ..."

cat "$BACKUP_FILE" | kubectl exec -i -n "$NAMESPACE" "$POD" -- \
	psql -U "$USER" "$DATABASE"

echo "Restore completed successfully."
