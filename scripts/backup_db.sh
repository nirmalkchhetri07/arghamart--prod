#!/usr/bin/env bash
#
# arghamart production Postgres backup -> private Cloudflare R2 bucket.
#
# What it does:
#   1. pg_dump (custom format, compressed) inside the postgres container of
#      the "$COMPOSE_PROJECT" compose project. DB name/user are read from
#      .env.production (DATABASE_URL preferred, POSTGRES_DB/POSTGRES_USER
#      fallback). Passwords are never printed or hardcoded.
#   2. Backs up Active Storage local files ONLY when no S3/R2 image bucket
#      is configured; otherwise skips with a log line.
#   3. Uploads to R2 (rclone preferred, aws-cli fallback) using the separate
#      BACKUP_R2_* credentials/bucket, verifies size > 0, then prunes locals.
#   4. R2 retention: keep last 14 daily + 8 weekly (Sunday) backups per
#      prefix; delete older. Local: keep 2 newest per prefix.
#   5. Logs with timestamps; alerts on failure; pings healthcheck on success.
#
# Usage:
#   scripts/backup_db.sh [--help]
#
# Env overrides (all optional except the BACKUP_R2_* vars in .env.production):
#   ENV_FILE, COMPOSE_FILE, COMPOSE_PROJECT, COMPOSE_POSTGRES_SERVICE,
#   BACKUP_LOCAL_DIR, BACKUP_LOG_FILE, BACKUP_UPLOADER (rclone|aws),
#   BACKUP_KEEP_DAILY, BACKUP_KEEP_WEEKLY, BACKUP_KEEP_LOCAL,
#   BACKUP_STORAGE_VOLUME, BACKUP_ALERT_WEBHOOK_URL, BACKUP_HEALTHCHECK_URL
#
set -eEuo pipefail # -E (errtrace): the ERR trap below must also fire for
                   # failures inside functions/subshells (e.g. a failed R2
                   # upload in s3_upload), otherwise no alert would be sent.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env.production}"
COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/docker-compose.prod.yml}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-arghamart-prod}"
PG_SERVICE="${COMPOSE_POSTGRES_SERVICE:-postgres}"
LOCAL_DIR="${BACKUP_LOCAL_DIR:-${REPO_ROOT}/backups}"
LOG_FILE="${BACKUP_LOG_FILE:-/var/log/arghamart-backup.log}"
UPLOADER_PREF="${BACKUP_UPLOADER:-rclone}"
KEEP_DAILY="${BACKUP_KEEP_DAILY:-14}"
KEEP_WEEKLY="${BACKUP_KEEP_WEEKLY:-8}"
KEEP_LOCAL="${BACKUP_KEEP_LOCAL:-2}"

STAMP="$(date -u +%Y-%m-%d_%H%M)" # UTC (20:15 UTC = 02:00 +0545 next day)
DUMP_BASENAME="arghamart-${STAMP}.dump"
FILES_BASENAME="arghamart-files-${STAMP}.tar.gz"

FAILED=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'
  exit 0
fi

log() {
  local level="$1"; shift
  local line="$(date -u '+%Y-%m-%dT%H:%M:%SZ') [${level}] $*"
  echo "$line"
  echo "$line" >>"$LOG_FILE" 2>/dev/null || true
}

send_alert() {
  local msg="$1"
  if [[ -n "${BACKUP_ALERT_WEBHOOK_URL:-}" ]]; then
    curl -fsS -m 20 -X POST -H 'Content-Type: application/json' \
      --data "{\"text\":\"[arghamart backup] ${msg}\"}" \
      "$BACKUP_ALERT_WEBHOOK_URL" >/dev/null 2>&1 \
      && log INFO "Failure alert sent" \
      || log WARN "Could not deliver failure alert webhook"
  else
    log WARN "BACKUP_ALERT_WEBHOOK_URL unset - no alert sent"
  fi
}

fail() {
  trap - ERR
  FAILED=1
  log ERROR "$*"
  send_alert "FAILED: $* (host $(hostname), ${STAMP} UTC)"
  exit 1
}

trap 'fail "unexpected error (exit $?) during backup run"' ERR

compose() {
  docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE" "$@"
}

# ---------------------------------------------------------------- sanity --
[[ -f "$ENV_FILE" ]] || fail "env file not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "compose file not found: $COMPOSE_FILE"
command -v docker >/dev/null || fail "docker CLI not found"
mkdir -p "$LOCAL_DIR"

# Prevent overlapping runs.
exec 9>"$LOCAL_DIR/.backup.lock"
flock -n 9 || fail "another backup run is holding $LOCAL_DIR/.backup.lock"

# Load .env.production WITHOUT printing values.
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# ------------------------------------------------------------- DB resolve --
# Production database.yml uses DATABASE_URL only, so prefer it; fall back to
# POSTGRES_DB/POSTGRES_USER (dev-style compose defaults to postgres/postgres).
DB_NAME="${POSTGRES_DB:-}"
DB_USER="${POSTGRES_USER:-}"
DB_PASS="${POSTGRES_PASSWORD:-}"
if [[ -n "${DATABASE_URL:-}" ]]; then
  if [[ "$DATABASE_URL" =~ ^postgres(ql)?://([^:/@?]+)(:([^@?]*))?@[^/?]+/([^?]+) ]]; then
    DB_USER="${BASH_REMATCH[2]}"
    [[ -z "$DB_PASS" ]] && DB_PASS="${BASH_REMATCH[4]:-}"
    DB_NAME="${BASH_REMATCH[5]}"
  else
    log WARN "Could not parse DATABASE_URL - falling back to POSTGRES_* vars"
  fi
fi
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-postgres}"
[[ -n "$DB_NAME" && -n "$DB_USER" ]] || fail "could not resolve DB name/user"

# ---------------------------------------------------------------- R2 conf --
R2_ENDPOINT="${BACKUP_R2_ENDPOINT:-}"
R2_KEY_ID="${BACKUP_R2_ACCESS_KEY_ID:-}"
R2_SECRET="${BACKUP_R2_SECRET_ACCESS_KEY:-}"
R2_BUCKET="${BACKUP_R2_BUCKET:-}"
[[ -n "$R2_ENDPOINT" && -n "$R2_KEY_ID" && -n "$R2_SECRET" && -n "$R2_BUCKET" ]] \
  || fail "BACKUP_R2_ENDPOINT / _ACCESS_KEY_ID / _SECRET_ACCESS_KEY / _BUCKET must all be set"

# -------------------------------------------------------------- uploader ---
UPLOADER="$UPLOADER_PREF"
if [[ "$UPLOADER" == "rclone" ]] && ! command -v rclone >/dev/null 2>&1; then
  if command -v aws >/dev/null 2>&1; then
    log WARN "rclone not found - falling back to aws-cli for this run (install rclone for the preferred path)"
    UPLOADER="aws"
  else
    fail "neither rclone nor aws-cli is installed"
  fi
fi
if [[ "$UPLOADER" == "aws" ]] && ! command -v aws >/dev/null 2>&1; then
  fail "aws-cli not found (BACKUP_UPLOADER=aws)"
fi
log INFO "Uploader: $UPLOADER | project: $COMPOSE_PROJECT | db: $DB_USER@$DB_NAME (name only)"

RCLONE_CONF=""
if [[ "$UPLOADER" == "rclone" ]]; then
  RCLONE_TMP="$(mktemp -d)"
  RCLONE_CONF="$RCLONE_TMP/rclone.conf"
  chmod 700 "$RCLONE_TMP"
  cat >"$RCLONE_CONF" <<EOF
[backup]
type = s3
provider = Cloudflare
endpoint = ${R2_ENDPOINT}
access_key_id = ${R2_KEY_ID}
secret_access_key = ${R2_SECRET}
region = auto
EOF
  chmod 600 "$RCLONE_CONF"
  RCLONE="rclone --config $RCLONE_CONF"
else
  export AWS_ACCESS_KEY_ID="$R2_KEY_ID"
  export AWS_SECRET_ACCESS_KEY="$R2_SECRET"
  export AWS_EC2_METADATA_DISABLED=true
  AWS_EP=(aws --endpoint-url "$R2_ENDPOINT")
fi

cleanup_uploader_creds() {
  [[ -n "${RCLONE_TMP:-}" ]] && rm -rf "$RCLONE_TMP"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY 2>/dev/null || true
}
trap_cleanup() { cleanup_uploader_creds; }
# NOTE: ERR trap owns failure handling; this only scrubs temp creds on exit.
trap trap_cleanup EXIT

s3_upload() { # $1=local path $2=object key
  if [[ "$UPLOADER" == "rclone" ]]; then
    # shellcheck disable=SC2086
    $RCLONE copyto "$1" "backup:${R2_BUCKET}/$2"
  else
    "${AWS_EP[@]}" s3 cp "$1" "s3://${R2_BUCKET}/$2"
  fi
}

s3_size() { # $1=object key -> prints bytes, empty if missing
  if [[ "$UPLOADER" == "rclone" ]]; then
    # shellcheck disable=SC2086
    $RCLONE lsl "backup:${R2_BUCKET}/$1" 2>/dev/null | awk '{print $1}'
  else
    "${AWS_EP[@]}" s3api head-object --bucket "$R2_BUCKET" --key "$1" \
      --query ContentLength --output text 2>/dev/null
  fi
}

s3_list() { # prints object keys, one per line
  if [[ "$UPLOADER" == "rclone" ]]; then
    # shellcheck disable=SC2086
    $RCLONE lsf "backup:${R2_BUCKET}/" 2>/dev/null
  else
    "${AWS_EP[@]}" s3api list-objects-v2 --bucket "$R2_BUCKET" \
      --query 'Contents[].Key' --output text 2>/dev/null | tr '\t' '\n'
  fi
}

s3_rm() { # $1=object key
  if [[ "$UPLOADER" == "rclone" ]]; then
    # shellcheck disable=SC2086
    $RCLONE deletefile "backup:${R2_BUCKET}/$1"
  else
    "${AWS_EP[@]}" s3 rm "s3://${R2_BUCKET}/$1"
  fi
}

# ---------------------------------------------------------------- pg_dump --
DUMP_PATH="$LOCAL_DIR/$DUMP_BASENAME"
log INFO "Dumping database to $DUMP_BASENAME (-Fc, compressed)"
if [[ -n "$DB_PASS" ]]; then
  compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" "PGPASSWORD=$DB_PASS" \
    pg_dump -Fc -U "$DB_USER" -d "$DB_NAME" >"$DUMP_PATH"
else
  compose exec -T "$PG_SERVICE" env "PGUSER=$DB_USER" \
    pg_dump -Fc -U "$DB_USER" -d "$DB_NAME" >"$DUMP_PATH"
fi
[[ -s "$DUMP_PATH" ]] || fail "pg_dump produced an empty file"
log INFO "Dump complete: $(du -h "$DUMP_PATH" | cut -f1)"

# ------------------------------------------------------- Active Storage ----
FILES_PATH=""
# R2_BUCKET is the short alias for CLOUDFLARE_BUCKET (see config/storage.yml).
if [[ -n "${AWS_BUCKET:-}${CLOUDFLARE_BUCKET:-}${R2_BUCKET:-}" ]]; then
  log INFO "Image bucket configured (AWS_BUCKET/CLOUDFLARE_BUCKET/R2_BUCKET) - skipping local Active Storage backup"
else
  VOLUME="${BACKUP_STORAGE_VOLUME:-${COMPOSE_PROJECT}_storage_data}"
  if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    log INFO "Backing up Active Storage volume $VOLUME"
    # --user keeps the archive owned by the invoking user (not root) so
    # later pruning works without sudo.
    if docker run --rm --user "$(id -u):$(id -g)" -v "${VOLUME}:/data:ro" -v "${LOCAL_DIR}:/out" \
        alpine:3.21 tar -czf "/out/${FILES_BASENAME}" -C /data . ; then
      FILES_PATH="$LOCAL_DIR/$FILES_BASENAME"
      log INFO "Files archive complete: $(du -h "$FILES_PATH" | cut -f1)"
    else
      log WARN "Active Storage tar failed - continuing with DB backup only"
    fi
  else
    log WARN "Volume $VOLUME not found - skipping Active Storage backup (set BACKUP_STORAGE_VOLUME if different)"
  fi
fi

# ----------------------------------------------------------------- upload --
upload_and_verify() { # $1=local path $2=object key
  local path="$1" key="$2" size
  log INFO "Uploading $key"
  s3_upload "$path" "$key"
  size="$(s3_size "$key")"
  if [[ -z "$size" || "$size" == "None" || "$size" -le 0 ]]; then
    fail "upload verification failed for $key (missing or zero size)"
  fi
  log INFO "Verified $key (${size} bytes)"
}

upload_and_verify "$DUMP_PATH" "$DUMP_BASENAME"
[[ -n "$FILES_PATH" ]] && upload_and_verify "$FILES_PATH" "$FILES_BASENAME"

# ---------------------------------------------------------------- retention --
# Keep the last KEEP_DAILY daily backups plus the KEEP_WEEKLY most recent
# Sunday backups, per filename prefix. Weekly Sundays that already fall inside
# the daily window do not consume an extra slot.
apply_retention() { # $1=name regex-group, e.g. 'arghamart-[0-9...]' handled by caller list
  local key y m d epoch age_days dow entry
  local now
  now="$(date -u +%s)"
  local list_tmp keep_sundays=0
  list_tmp="$(mktemp)"
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if [[ "$key" =~ ^(arghamart|arghamart-files)-([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{4})\.(dump|tar\.gz)$ ]]; then
      y="${BASH_REMATCH[2]}"; m="${BASH_REMATCH[3]}"; d="${BASH_REMATCH[4]}"
      epoch="$(date -u -d "${y}-${m}-${d}" +%s 2>/dev/null || echo 0)"
      [[ "$epoch" -eq 0 ]] && continue
      dow="$(date -u -d "${y}-${m}-${d}" +%u)"
      echo "${epoch} ${dow} ${key}" >>"$list_tmp"
    fi
  done <<<"$1"
  while read -r epoch dow key; do
    age_days=$(( (now - epoch) / 86400 ))
    if (( age_days < KEEP_DAILY )); then
      continue # kept: within the daily window
    fi
    if [[ "$dow" == "7" ]] && (( keep_sundays < KEEP_WEEKLY )); then
      keep_sundays=$((keep_sundays + 1))
      continue # kept: one of the newest Sundays
    fi
    log INFO "Retention: deleting s3://${R2_BUCKET}/${key}"
    s3_rm "$key" || log WARN "Could not delete $key (continuing)"
  done < <(sort -rn "$list_tmp")
  rm -f "$list_tmp"
}

log INFO "Applying R2 retention (keep ${KEEP_DAILY} daily + ${KEEP_WEEKLY} Sundays)"
apply_retention "$(s3_list)"

# Local: keep only the newest KEEP_LOCAL files per prefix.
prune_local() { # $1=glob pattern
  local files total
  files="$(ls -1t $1 2>/dev/null || true)"
  [[ -z "$files" ]] && return 0
  total="$(echo "$files" | wc -l)"
  if (( total > KEEP_LOCAL )); then
    echo "$files" | tail -n +"$((KEEP_LOCAL + 1))" | xargs -r rm -f
    log INFO "Pruned local copies for $1 to newest $KEEP_LOCAL"
  fi
}
prune_local "$LOCAL_DIR/arghamart-[0-9]*.dump"
prune_local "$LOCAL_DIR/arghamart-files-[0-9]*.tar.gz"

# ----------------------------------------------------------------- finish --
trap - ERR
trap_cleanup
trap - EXIT
if [[ -n "${BACKUP_HEALTHCHECK_URL:-}" ]]; then
  curl -fsS -m 20 "$BACKUP_HEALTHCHECK_URL" >/dev/null 2>&1 \
    && log INFO "Healthcheck pinged" \
    || log WARN "Healthcheck ping failed (backup itself succeeded)"
fi
log INFO "Backup run complete: $DUMP_BASENAME"
