#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

: "${LEADS_DB_HOST:?LEADS_DB_HOST is required}"
: "${LEADS_DB_PORT:?LEADS_DB_PORT is required}"
: "${LEADS_DB_NAME:?LEADS_DB_NAME is required}"
: "${LEADS_APP_USER:?LEADS_APP_USER is required}"
: "${LEADS_APP_PASSWORD:?LEADS_APP_PASSWORD is required}"

case "$LEADS_DB_HOST" in
  127.0.0.1|localhost|::1) ;;
  *) echo "refusing non-local PostgreSQL host: $LEADS_DB_HOST" >&2; exit 64 ;;
esac

if [[ "$LEADS_DB_NAME" != "leads_workstation" ]]; then
  echo "refusing unexpected database: $LEADS_DB_NAME" >&2
  exit 64
fi

backup_dir="${LEADS_BACKUP_DIR:-/home/codestra/Backups/Leads}"
retention_days="${LEADS_BACKUP_RETENTION_DAYS:-14}"
if ! [[ "$retention_days" =~ ^[0-9]+$ ]] || (( retention_days < 1 )); then
  echo "LEADS_BACKUP_RETENTION_DAYS must be an integer >= 1" >&2
  exit 64
fi

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
exec 9>"$backup_dir/.backup.lock"
if ! flock -n 9; then
  echo "backup already running" >&2
  exit 75
fi

ts="$(date +%Y%m%dT%H%M%S%z)"
base="leads_workstation_${ts}"
tmp="$backup_dir/.${base}.dump.tmp"
final="$backup_dir/${base}.dump"
sha_file="$final.sha256"
meta_file="$final.meta"
trap 'rm -f "$tmp"' EXIT

export PGPASSWORD="$LEADS_APP_PASSWORD"
pg_dump \
  --host "$LEADS_DB_HOST" \
  --port "$LEADS_DB_PORT" \
  --username "$LEADS_APP_USER" \
  --dbname "$LEADS_DB_NAME" \
  --format custom \
  --no-owner \
  --no-acl \
  --file "$tmp"

pg_restore --list "$tmp" >/dev/null
mv "$tmp" "$final"
sha256sum "$final" > "$sha_file"
chmod 600 "$final" "$sha_file"

canonical_count="$(psql --host "$LEADS_DB_HOST" --port "$LEADS_DB_PORT" --username "$LEADS_APP_USER" --dbname "$LEADS_DB_NAME" --tuples-only --no-align --command 'select count(*) from leads.leads')"
cat > "$meta_file" <<META
policy=local-backup-only
created_at=$(date -Is)
database=$LEADS_DB_NAME
host=$LEADS_DB_HOST
port=$LEADS_DB_PORT
canonical_lead_count=$canonical_count
format=postgresql-custom
validation=pg_restore-list-pass
sha256=$(cut -d' ' -f1 "$sha_file")
META
chmod 600 "$meta_file"

find "$backup_dir" -maxdepth 1 -type f -name 'leads_workstation_*.dump' -mtime "+$retention_days" -print0 | while IFS= read -r -d '' old; do
  rm -f -- "$old" "$old.sha256" "$old.meta"
done

echo "backup_path=$final"
echo "sha256=$(cut -d' ' -f1 "$sha_file")"
echo "canonical_lead_count=$canonical_count"
