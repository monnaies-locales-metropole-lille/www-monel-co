#!/bin/bash
# Dump the SPIP database out of the compose stack.
#
# Replaces the backupninja `10-moneldb.mysql` handler, which authenticated through
# /etc/mysql/debian.cnf against a mysqld on the host and cannot reach a container.
#
# The output path is deliberately unchanged from the backupninja layout:
#
#     /var/backups/mysql/sqldump/monel.sql.gz
#
# so `prod-db-backup-sync` on preprod, and every restore habit, keep working.
#
# Install from ansible as a daily cron. Run as root (it needs to reach the docker
# socket and write under /var/backups).
#
# Usage: backup-db.sh [compose-project-dir] [backup-dir]

set -euo pipefail

PROJECT_DIR="${1:-/var/lib/monel-spip}"
BACKUP_DIR="${2:-/var/backups/mysql/sqldump}"
KEEP_DAYS="${KEEP_DAYS:-14}"

DB_NAME="${MONEL_DB_NAME:-monel}"
DB_USER="${MONEL_DB_USER:-monel}"

umask 077

# 0700, owned by whoever runs this. The postgres backups being world-readable is
# report item 12, and it is how a webshell read the entire Cyclos database without
# needing a single credential (§5.2). Do not relax this.
mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

target="$BACKUP_DIR/${DB_NAME}.sql.gz"
tmp="$target.tmp.$$"
trap 'rm -f "$tmp"' EXIT

# Only this schema. The old `databases = all` also dumped the `mysql` system
# database — every account's password hash — into the same directory. That is the
# same mistake as globals.sql.gz on the Postgres side (§5.9 item 3).
#
# --single-transaction keeps it consistent without locking the site out; SPIP is
# InnoDB throughout.
docker compose --project-directory "$PROJECT_DIR" exec -T db \
    mariadb-dump \
        --user="$DB_USER" \
        --password="${MONEL_DB_PASSWORD:?MONEL_DB_PASSWORD must be set}" \
        --single-transaction \
        --quick \
        --default-character-set=utf8mb4 \
        --routines \
        --events \
        "$DB_NAME" \
    | gzip -c > "$tmp"

# A truncated dump that overwrites a good one is worse than a failed backup, so
# only move it into place once it is complete and non-trivial.
if [ ! -s "$tmp" ] || [ "$(stat -c %s "$tmp")" -lt 1024 ]; then
    echo "FATAL: dump is empty or implausibly small — keeping the previous one" >&2
    exit 1
fi

if ! gzip -t "$tmp" 2>/dev/null; then
    echo "FATAL: dump failed gzip integrity check — keeping the previous one" >&2
    exit 1
fi

mv "$tmp" "$target"
chmod 0600 "$target"

# Dated copy for retention; the undated name above is what the sync cron pulls.
cp -a "$target" "$BACKUP_DIR/${DB_NAME}-$(date +%F).sql.gz"
find "$BACKUP_DIR" -name "${DB_NAME}-*.sql.gz" -mtime "+${KEEP_DAYS}" -delete

echo "$(date -Is) dumped ${DB_NAME} -> ${target} ($(stat -c %s "$target") bytes)"
