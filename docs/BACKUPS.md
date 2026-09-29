# Backups: Postgres -> Cloudflare R2 (daily)

## How it works

- `scripts/backup_db.sh` runs `pg_dump -Fc` (compressed custom format) **inside**
  the `postgres` container of the `arghamart-prod` compose project, so no DB
  password travels over the network. DB name/user come from `.env.production`
  (`DATABASE_URL` preferred, `POSTGRES_DB`/`POSTGRES_USER` fallback). Secrets
  are never printed.
- File name: `arghamart-YYYY-MM-DD_HHMM.dump` (UTC; the 20:15 UTC run lands at
  02:00 Nepal time, dated the UTC day).
- Active Storage: backed up as `arghamart-files-YYYY-MM-DD_HHMM.tar.gz` from
  the storage Docker volume **only when no S3/R2 image bucket is configured**
  (`AWS_BUCKET`/`CLOUDFLARE_BUCKET`/`R2_BUCKET` empty). Otherwise skipped with a log line.
- Uploads to a **separate private R2 bucket** via `rclone` (preferred) or
  `aws-cli` fallback, using `BACKUP_R2_*` vars. The upload is verified
  (object exists, size > 0) before local pruning.
- Retention in R2: last **14 daily + 8 weekly (Sunday)** backups per prefix;
  older objects deleted. Locally only the **2 newest** per prefix are kept.
- Logs to `/var/log/arghamart-backup.log` (timestamps, UTC). Failures POST to
  `BACKUP_ALERT_WEBHOOK_URL` (Slack/Discord format `{"text": ...}`; for
  Telegram use a relay or a Pipedream/ntfy bridge - see Troubleshooting).
  Success pings `BACKUP_HEALTHCHECK_URL` (healthchecks.io style) when set.
- Overlap guard via `flock` on `backups/.backup.lock`.

## One-time setup on EC2

1. Install rclone (preferred uploader; aws-cli is the automatic fallback):
   ```bash
   sudo apt update && sudo apt install -y rclone
   rclone version
   ```
   (Ask before installing on shared hosts - this is the only package needed.)
2. Create the R2 bucket (Cloudflare dashboard -> R2 Object Storage):
   - **Create bucket**, name e.g. `arghamart-backups`, location Automatic,
     **not** public (no custom domain / public access).
   - Must differ from the images bucket (`CLOUDFLARE_BUCKET`, aka `R2_BUCKET`).
3. Create a bucket-scoped API token (R2 -> **Manage R2 API Tokens** ->
   **Create API Token**):
   - Permissions: **Object Read & Write** (least privilege; no admin).
   - Scope: **Apply to specific buckets only** -> select `arghamart-backups`.
   - TTL: no expiry (or yearly with a rotation reminder). Save the
     Access Key ID, Secret Access Key, and the endpoint
     `https://<account-id>.r2.cloudflarestorage.com` into `.env.production`
     as `BACKUP_R2_*` (see `backend/.env.example`). Never commit the file.
4. Add to `.env.production` (values stay on the server):
   ```bash
   BACKUP_R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
   BACKUP_R2_ACCESS_KEY_ID=<token key id>
   BACKUP_R2_SECRET_ACCESS_KEY=<token secret>
   BACKUP_R2_BUCKET=arghamart-backups
   BACKUP_ALERT_WEBHOOK_URL=<slack-or-discord-webhook>
   BACKUP_HEALTHCHECK_URL=<https://hc-ping.com/<uuid>>
   ```
5. Install the systemd timer (paths assume the repo lives at `/srv/arghamart`
   - adjust with `sed` if different):
   ```bash
   cd /srv/arghamart   # or wherever the repo is
   sed -i "s|/srv/arghamart|$(pwd)|" systemd/arghamart-backup.service
   sudo cp systemd/arghamart-backup.service systemd/arghamart-backup.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now arghamart-backup.timer
   sudo systemctl status arghamart-backup.timer --no-pager
   sudo systemctl list-timers --all | grep arghamart
   ```
   Cron alternative (no systemd): `crontab -e` then
   `15 20 * * * /srv/arghamart/scripts/backup_db.sh >>/var/log/arghamart-backup.log 2>&1`
6. Writable log file: `sudo touch /var/log/arghamart-backup.log && sudo chown ubuntu:ubuntu /var/log/arghamart-backup.log`
   (replace `ubuntu` with the user the timer/scripts run as; the script also
   works if the file is unwritable - it logs to stdout/journal instead).

## Manual backup

```bash
cd /srv/arghamart
./scripts/backup_db.sh
tail -n 30 /var/log/arghamart-backup.log
# list what is in R2 (needs BACKUP_* vars; source .env.production first):
set -a; . .env.production; set +a
aws --endpoint-url "$BACKUP_R2_ENDPOINT" s3 ls "s3://$BACKUP_R2_BUCKET/" | tail
```

## Test a restore (monthly, and after any backup-script change)

```bash
cd /srv/arghamart
# Restores into arghamart_restore_<stamp> - production is never touched:
./scripts/restore_db.sh latest
# Compare the printed spree_orders / spree_payments / spree_products counts.
# Clean up:
docker compose -p arghamart-prod -f docker-compose.prod.yml exec -T postgres \
  psql -U <user> -d <prod-db> -c 'DROP DATABASE "arghamart_restore_<stamp>"'
```

A real production restore requires the explicit flag (10 s abort window):
`./scripts/restore_db.sh <key> --target-db <prod-db> --confirm-production`

## Monthly checklist

- [ ] `systemctl list-timers | grep arghamart` shows the timer, last run OK.
- [ ] `/var/log/arghamart-backup.log` has 28-31 success lines, no ERROR.
- [ ] Healthcheck dashboard (if configured) shows no missed pings.
- [ ] R2 bucket object count sane (`14 daily + Sundays` ish, not growing forever).
- [ ] Restore `latest` into a temp DB, counts match, then drop the temp DB.
- [ ] R2 token still valid; rotation due? Alert webhook still delivers
      (send a test message).
- [ ] Disk use on EC2 sane (`du -sh backups/` - only 2 local copies).

## Troubleshooting

- `env file not found` / `compose file not found`: the scripts default to
  `.env.production` + `docker-compose.prod.yml` in the repo root with project
  `arghamart-prod`; override via `ENV_FILE=... COMPOSE_FILE=... COMPOSE_PROJECT=...`.
- `neither rclone nor aws-cli is installed`: install rclone (step 1) or set
  `BACKUP_UPLOADER=aws`.
- Upload 403: token scoped to the wrong bucket, or bucket name typo.
- Telegram alerts: raw Bot API needs `chat_id`; point `BACKUP_ALERT_WEBHOOK_URL`
  at a Slack/Discord webhook, or a small relay (e.g. ntfy/Pipedream) that maps
  `{"text"}` to Telegram.
- No alert arrived but backup failed: `BACKUP_ALERT_WEBHOOK_URL` unset - the
  script logs and exits non-zero so systemd/cron still reports failure.
