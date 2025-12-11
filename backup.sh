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
: "${KEEP_DAYS:=30}"

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

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
# Email sending
# ----------------------
send_email() {
    subject="$1"
    status="$2"

    [ -n "${APP_NAME:-}" ] && subject="${APP_NAME} ${subject}"

    send="no"
    if [ "$status" = "success" ] && [ "$EMAIL_ON_SUCCESS" = "true" ]; then
        send="yes"
    elif [ "$status" = "failure" ] && [ "$EMAIL_ON_FAILURE" = "true" ]; then
        send="yes"
    fi

    [ "$send" = "no" ] && return

    if ! body=$(cat "$RUN_LOG"); then
        log_error "Failed to read run log for email body."
        return
    fi

    if ! printf "To: %s\nSubject: %s\n\n%s" "$EMAIL_TO" "$subject" "$body" \
        | msmtp --file "$MSMTP_CONFIG" -t >>"$LOG_FILE" 2>&1; then
        log_error "Email send failed. Check SMTP server or credentials."
    fi
}

# ----------------------
# Prune Backups
# ----------------------
prune_by_timestamp() {
    tag="$1"
    keep_days="${2:-0}"
    dir="${3:-$BACKUP_DEST}"

    [ "$keep_days" -eq 0 ] && {
        log "KEEP_DAYS=0; skipping pruning."
        return
    }

    log "Pruning files and directories matching '$tag' older than $keep_days days..."

    # Compute cutoff timestamp in numeric form (YYYYMMDDHHMMSS)
    cutoff_ts=$(date -d "$keep_days days ago" +%Y%m%d%H%M%S 2>/dev/null \
        || date -v -"${keep_days}"d +%Y%m%d%H%M%S 2>/dev/null \
        || printf "%s" "$(date +%Y%m%d%H%M%S)")

    [ "$cutoff_ts" = "$(date +%Y%m%d%H%M%S)" ] && {
        log "WARNING: Your 'date' command lacks -d/-v support. Pruning skipped."
        return
    }

    # shellglob expansion check
    set -- "$dir"/$tag
    [ -e "$1" ] || {
        log "No files or directories matching pattern '$tag' found in $dir. Nothing to prune."
        return
    }

    for f in "$dir"/$tag; do
        [ -e "$f" ] || continue  # include files and directories

        # Extract timestamp (YYYY-MM-DD_HH-MM-SS) from filename
        basename=${f##*/}

        # Search for timestamp pattern manually
        ts=""
        i=0
        len=${#basename}
        while [ $i -le $((len - 19)) ]; do
            substr=${basename:$i:19}
            case "$substr" in
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                    ts=$substr
                    break
                    ;;
            esac
            i=$((i + 1))
        done

        [ -n "$ts" ] || {
            log "Skipping (timestamp not found): $f"
            continue
        }

        # Convert timestamp to numeric YYYYMMDDHHMMSS
        file_ts="${ts%_*}${ts#*_}"      # remove underscore
        file_ts="${file_ts//-/}"        # remove dashes

        if [ "$file_ts" -lt "$cutoff_ts" ]; then
            if [ "$DRY_RUN" = "true" ]; then
                log "[DRY RUN] Would delete old backup: $f"
            else
                log "Deleting old backup: $f"
                rm -rf "$f"
            fi
        fi
    done

    log "Pruning completed."
}

# ----------------------
# Execute Backup
# ----------------------
if [ "${APP_BACKUP##*/}" = "default.sh" ]; then
    log "No custom application backup script specified.  Configure APP_BACKUP to run a backup."
    exit 0
fi

if [ -x "$APP_BACKUP" ]; then
    if . "$APP_BACKUP"; then
        log "Backup completed successfully."
        send_email "Backup Succeeded" "success"
    else
        log_error "Backup script failed."
        send_email "Backup Failed" "failure"
        exit 1
    fi
else
    log_error "Backup script not found or not executable: $APP_BACKUP"
    send_email "Backup Failed" "failure"
    exit 1
fi
