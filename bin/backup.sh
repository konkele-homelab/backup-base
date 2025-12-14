#!/bin/sh
set -eu

# ----------------------
# Default variables
# ----------------------
: "${BACKUP_DEST:=/backup}"
: "${LOG_FILE:=/var/log/backup.log}"
: "${RUN_LOG:=/tmp/backup_run_$$.log}"

: "${MSMTP_CONFIG:=/etc/msmtp/msmtprc}"
: "${EMAIL_ON_SUCCESS:=false}"
: "${EMAIL_ON_FAILURE:=false}"
: "${EMAIL_TO:=admin@example.com}"

: "${APP_BACKUP:=/default.sh}"
: "${DRY_RUN:=false}"

# ----------------------
# Cleanup
# ----------------------
cleanup() {
    rm -f "$RUN_LOG"
}
trap cleanup EXIT

# ----------------------
# Logging
# ----------------------
log() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" | tee -a "$LOG_FILE" -a "$RUN_LOG"
}

log_error() {
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] ERROR: $*" | tee -a "$LOG_FILE" -a "$RUN_LOG" >&2
}

# ----------------------
# Load common backup library
# ----------------------
COMMON_LIB="/usr/local/lib/backup_common.sh"
if [ ! -r "$COMMON_LIB" ]; then
    log_error "backup_common.sh not found at $COMMON_LIB"
    exit 1
fi
. "$COMMON_LIB"

# ----------------------
# Email
# ----------------------
send_email() {
    subject="$1"
    status="$2"

    app_name="${APP_NAME:-BackupJob}"

    subject="${app_name} ${subject}"

    case "$status:$EMAIL_ON_SUCCESS:$EMAIL_ON_FAILURE" in
        success:true:*) ;;
        failure:*:true) ;;
        *) return ;;
    esac

    body=$(cat "$RUN_LOG" 2>/dev/null || true)

    printf "To: %s\nSubject: %s\n\n%s" "$EMAIL_TO" "$subject" "$body" \
        | msmtp --file "$MSMTP_CONFIG" -t >>"$LOG_FILE" 2>&1 \
        || log_error "Email send failed"
}

# ----------------------
# Create snapshot directory
# ----------------------
TIMESTAMP=$(_now_ts)
SNAPSHOT_DIR="$BACKUP_DEST/daily/$TIMESTAMP"
create_snapshot_dir "$SNAPSHOT_DIR"

# ----------------------
# Execute application backup
# ----------------------
if [ "${APP_BACKUP##*/}" = "default.sh" ]; then
    log "No application backup configured (APP_BACKUP not set)"
    exit 0
fi

if [ ! -x "$APP_BACKUP" ]; then
    log_error "Backup script not executable: $APP_BACKUP"
    send_email "Backup Failed" "failure"
    exit 1
fi

log "Starting application backup: $APP_BACKUP"

# Provide SNAPSHOT_DIR to app script
export SNAPSHOT_DIR

if . "$APP_BACKUP"; then
    log "Backup completed successfully"

    # Update latest symlink
    update_latest_symlink "daily/$TIMESTAMP"

    # GFS snapshot promotion
    create_gfs_snapshots "$SNAPSHOT_DIR"

    # Apply retention based on configured policy
    apply_retention

    send_email "Backup Succeeded" "success"
else
    log_error "Backup script failed"
    send_email "Backup Failed" "failure"
    exit 1
fi
