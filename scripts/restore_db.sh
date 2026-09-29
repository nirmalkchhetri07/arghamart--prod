#!/usr/bin/env bash
#
# Restore an arghamart R2 backup into a NEW temporary database for verification.
# NEVER overwrites production unless --confirm-production is passed AND the
# target resolves to the production database.
#
# Usage:
#   scripts/restore_db.sh [--target-db NAME] [--confirm-production] <backup-key|latest>
#
# Examples:
#   scripts/restore_db.sh latest
#   scripts/restore_db.sh arghamart-2026-09-29_2015.dump --target-db arghamart_verify_sep29
#   scripts/restore_db.sh latest --target-db spree_production --confirm-production  # REAL restore
#
# Env overrides: ENV_FILE, COMPOSE_FILE, COMPOSE_PROJECT,
# COMPOSE_POSTGRES_SERVICE, BACKUP_UPLOADER (rclone|aws).
# R2 credentials come from the same BACKUP_R2_* vars as backup_db.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env.production}"
COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/docker-compose.prod.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-arghamart-prod}"
PG_SERVICE="${COMPOSE_POSTGRES_SERVICE:-postgres}"
UPLOADER_PREF="${BACKUP_UPLOADER:-rclone}"

TARGET_DB=""
CONFIRM_PROD=0
BACKUP_KEY=""

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --target-db) TARGET_DB="${2:?--target-db needs a name}"; shift 2 ;;
    --confirm-production) CONFIRM_PROD=1; shift ;;
    *) [[ -z "$BACKUP_KEY" ]] || { echo "unexpected arg: $1" >&2; usage >&2; exit 2; };
       BACKUP_KEY="$1"; shift ;;
  esac
done
[[ -n "$BACKUP_KEY" ]] || { usage >&2; exit 2; }

[[ -f "$ENV_FILE" ]] || { echo "env file not found: $ENV_FILE" >&2; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "compose file not found: $COMPOSE_FILE" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

DB_NAME="${POSTGRES_DB:-postgres}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:-}"
if [[ -n "${DATABASE_URL:-}" ]]; then
  if [[ "$DATABASE_URL" =~ ^postgres(ql)?://([^:/@?]+)(:([^@?]*))?@[^/?]+/([^?]+) ]]; then
    DB_USER="${BASH_REMATCH[2]}"
    [[ -z "$DB_PASS" ]] && DB_PASS="${BASH_REMATCH[4]:-}"
    DB_NAME="${BASH_REMATCH[5]}"
  fi
fi

R2_ENDPOINT="${BACKUP_R2_ENDPOINT:?BACKUP_R2_ENDPOINT must be set}"
R2_KEY_ID="${BACKUP_R2_ACCESS_KEY_ID:?BACKUP_R2_ACCESS_KEY_ID must be set}"
R2_SECRET="${BACKUP_R2_SECRET_ACCESS_KEY:?BACKUP_R2_SECRET_ACCESS_KEY must be set}"
R2_BUCKET="${BACKUP_R2_BUCKET:?BACKUP_R2_BUCKET must be set}"

UPLOADER="$UPLOADER_PREF"
if [[ "$UPLOADER" == "rclone" ]] && ! command -v rclone >/dev/null 2>&1; then
  command -v aws >/dev/null 2>&1 || { echo "neither rclone nor aws-cli installed" >&2; exit 1; }
  echo "WARN: rclone not found - falling back to aws-cli" >&2
  UPLOADER="aws"
fi

RCLONE_TMP=""
if [[ "$UPLOADER" == "rclone" ]]; then
  RCLONE_TMP="$(mktemp -d)"
  chmod 700 "$RCLONE_TMP"
  cat >"$RCLONE_TMP/rclone.conf" <<EOF
[backup]
type = s3
provider = Cloudflare
endpoint = ${R2_ENDPOINT}
access_key_id = ${R2_KEY_ID}
secret_access_key = ${R2_SECRET}
region = auto
EOF
  chmod 600 "$RCLONE_TMP/rclone.conf"
  RCLONE="rclone --config $RCLONE_TMP/rclone.conf"
else
  export AWS_ACCESS_KEY_ID="$R2_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$R2_SECRET"
  export AWS_EC2_METADATA_DISABLED=true
  AWS_EP=(aws --endpoint-url "$R2_ENDPOINT")
fi
cleanup_dl() {
  [[ -n "${DL_DIR:-}" ]] && rm -rf "$DL_DIR"
  [[ -n "$RCLONE_TMP" ]] && rm -rf "$RCLONE_TMP"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY 2>/dev/null || true
}
trap cleanup_dl EXIT

compose() { docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"; }

pg() { # extra psql args appended; runs inside the postgres container
  if [[ -n "$DB_PASS" ]]; then
    compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" "PGPASSWORD=$DB_PASS" \
      psql -U "$DB_USER" -d "$DB_NAME" "$@"
  else
    compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" \
      psql -U "$DB_USER" -d "$DB_NAME" "$@"
  fi
}

pg_ondb() { # $1=db, rest=psql args
  local db="$1"; shift
  if [[ -n "$DB_PASS" ]]; then
    compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" "PGPASSWORD=$DB_PASS" \
      psql -U "$DB_USER" -d "$db" "$@"
  else
    compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" \
      psql -U "$DB_USER" -d "$db" "$@"
  fi
}

# ------------------------------------------------------------ pick backup --
if [[ "$BACKUP_KEY" == "latest" ]]; then
  if [[ "$UPLOADER" == "rclone" ]]; then
    # shellcheck disable=SC2086
    BACKUP_KEY="$($RCLONE lsf "backup:${R2_BUCKET}/" 2>/dev/null | grep -E '^arghamart-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.dump$' | sort | tail -n 1)"
  else
    BACKUP_KEY="$("${AWS_EP[@]}" s3api list-objects-v2 --bucket "$R2_BUCKET" \
      --query 'Contents[].Key' --output text 2>/dev/null | tr '\t' '\n' \
      | grep -E '^arghamart-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.dump$' | sort | tail -n 1)"
  fi
  [[ -n "$BACKUP_KEY" ]] || { echo "no backups found in s3://$R2_BUCKET" >&2; exit 1; }
  echo "Latest backup: $BACKUP_KEY"
fi

[[ "$BACKUP_KEY" =~ ^arghamart-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.dump$ ]] \
  || { echo "refusing: '$BACKUP_KEY' does not look like an arghamart dump (expected arghamart-YYYY-MM-DD_HHMM.dump)" >&2; exit 2; }

if [[ -z "$TARGET_DB" ]]; then
  TARGET_DB="arghamart_restore_$(date -u +%Y%m%d_%H%M%S)"
fi

if [[ "$TARGET_DB" == "$DB_NAME" && "$CONFIRM_PROD" -ne 1 ]]; then
  cat >&2 <<EOF
REFUSING: target database "$TARGET_DB" is the PRODUCTION database.
Restore into a temporary database instead (default), or re-run with
--confirm-production if you really intend to overwrite production.
No changes were made.
EOF
  exit 3
fi

if [[ "$TARGET_DB" == "$DB_NAME" ]]; then
  cat <<EOF
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
WARNING: you are about to OVERWRITE THE PRODUCTION DATABASE
  database : $DB_NAME
  backup   : s3://${R2_BUCKET}/${BACKUP_KEY}
The app will be down / inconsistent until the restore finishes.
Starting in 10 seconds - Ctrl+C to abort.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
EOF
  sleep 10
fi

# --------------------------------------------------------------- download --
DL_DIR="$(mktemp -d)"
chmod 700 "$DL_DIR"
DL_PATH="$DL_DIR/$BACKUP_KEY"
echo "Downloading s3://${R2_BUCKET}/${BACKUP_KEY} ..."
if [[ "$UPLOADER" == "rclone" ]]; then
  # shellcheck disable=SC2086
  $RCLONE copyto "backup:${R2_BUCKET}/${BACKUP_KEY}" "$DL_PATH"
else
  "${AWS_EP[@]}" s3 cp "s3://${R2_BUCKET}/${BACKUP_KEY}" "$DL_PATH"
fi
[[ -s "$DL_PATH" ]] || { echo "downloaded file is empty/missing" >&2; exit 1; }
echo "Downloaded $(du -h "$DL_PATH" | cut -f1)"

# ---------------------------------------------------------------- restore --
if pg -tAc "SELECT 1 FROM pg_database WHERE datname='$TARGET_DB'" | grep -q 1; then
  echo "database $TARGET_DB already exists - drop it first or pick another --target-db (no changes made)" >&2
  exit 4
fi

echo "Creating database $TARGET_DB ..."
pg -c "CREATE DATABASE \"$TARGET_DB\"" >/dev/null

CID="$(compose ps -q "$PG_SERVICE")"
[[ -n "$CID" ]] || { echo "postgres container not running" >&2; exit 1; }
docker cp "$DL_PATH" "$CID:/tmp/restore.dump"
if [[ -n "$DB_PASS" ]]; then
  compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" "PGPASSWORD=$DB_PASS" \
    pg_restore --no-owner --no-privileges -U "$DB_USER" -d "$TARGET_DB" /tmp/restore.dump
else
  compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" \
    pg_restore --no-owner --no-privileges -U "$DB_USER" -d "$TARGET_DB" /tmp/restore.dump
fi
compose exec -T "$PG_SERVICE" rm -f /tmp/restore.dump >/dev/null

# ----------------------------------------------------------------- verify --
echo "Row counts (production vs restored):"
printf '%-16s %12s %12s\n' "table" "production" "$TARGET_DB"
for t in spree_orders spree_payments spree_products; do
  prod_n="$(pg_ondb "$DB_NAME" -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo ERROR)"
  rest_n="$(pg_ondb "$TARGET_DB" -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo ERROR)"
  printf '%-16s %12s %12s\n' "$t" "$prod_n" "$rest_n"
done

if [[ "$TARGET_DB" == "$DB_NAME" ]]; then
  echo "PRODUCTION RESTORE COMPLETE from $BACKUP_KEY."
else
  echo "Restore complete into temporary database \"$TARGET_DB\"."
  echo "Drop it when done: docker compose -p $COMPOSE_PROJECT -f $COMPOSE_FILE exec -T $PG_SERVICE psql -U $DB_USER -d $DB_NAME -c 'DROP DATABASE \"$TARGET_DB\"'"
fi
