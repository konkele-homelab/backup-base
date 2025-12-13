#!/bin/sh
# -----------------------------------------------------------------------------
# backup_common.sh v2.3
# Common snapshot + retention engine.
# Handles GFS/FIFO/Calendar retention safely in POSIX shells.
# -----------------------------------------------------------------------------

# Guard against direct execution
[ "${BACKUP_COMMON_LOADED:-}" = "true" ] && return 0
BACKUP_COMMON_LOADED=true

###############################################################################
# Defaults (override via environment)
###############################################################################
: "${BACKUP_DEST:=/backup}"
: "${RETENTION_POLICY:=gfs}"        # gfs | fifo | calendar
: "${DRY_RUN:=false}"

# GFS defaults
: "${GFS_DAILY:=7}"
: "${GFS_WEEKLY:=4}"
: "${GFS_MONTHLY:=6}"

# FIFO defaults
: "${FIFO_COUNT:=14}"

# Calendar defaults
: "${CALENDAR_DAYS:=30}"

###############################################################################
# Internal helpers
###############################################################################
_now_ts() {
    date '+%Y-%m-%d_%H-%M-%S'
}

_numeric_ts() {
    # Convert YYYY-MM-DD_HH-MM-SS → YYYYMMDDHHMMSS, digits only
    printf '%s\n' "$1" | tr -cd '0-9'
}

_cutoff_ts_days_ago() {
    days="$1"
    date -d "$days days ago" +%Y%m%d%H%M%S 2>/dev/null \
        || date -v -"${days}"d +%Y%m%d%H%M%S 2>/dev/null \
        || { echo "$(date +%Y%m%d%H%M%S)"; return 1; }
}

###############################################################################
# Snapshot helpers
###############################################################################
create_snapshot_dir() {
    snapshot_dir="$1"

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY-RUN] would create snapshot dir: $snapshot_dir"
        return 0
    fi

    mkdir -p "$snapshot_dir"
}

update_latest_symlink() {
    target="$1"   # relative path from BACKUP_DEST

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY-RUN] would update latest -> $target"
        return 0
    fi

    ( cd "$BACKUP_DEST" && ln -sfn "$target" latest )
}

###############################################################################
# Retention dispatch
###############################################################################
apply_retention() {
    case "$RETENTION_POLICY" in
        gfs)       _retention_gfs ;;
        fifo)      _retention_fifo ;;
        calendar)  _retention_calendar ;;
        *)
            log_error "Unknown RETENTION_POLICY: $RETENTION_POLICY"
            return 1
            ;;
    esac
}

###############################################################################
# GFS retention
###############################################################################
_retention_gfs() {
    log "Applying GFS retention (daily=$GFS_DAILY weekly=$GFS_WEEKLY monthly=$GFS_MONTHLY)"

    _prune_by_days "$BACKUP_DEST/daily"   "$GFS_DAILY"
    _prune_by_days "$BACKUP_DEST/weekly"  "$((GFS_WEEKLY * 7))"
    _prune_by_days "$BACKUP_DEST/monthly" "$((GFS_MONTHLY * 31))"
}

###############################################################################
# FIFO retention
###############################################################################
_retention_fifo() {
    dir="$BACKUP_DEST/daily"

    log "Applying FIFO retention (keep=$FIFO_COUNT)"

    [ -d "$dir" ] || return 0

    count=$(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ')
    excess=$((count - FIFO_COUNT))

    [ "$excess" -le 0 ] && return 0

    for f in $(ls -1 "$dir" | sort | head -n "$excess"); do
        if [ "$DRY_RUN" = "true" ]; then
            log "[DRY-RUN] would delete $dir/$f"
        else
            log "Deleting $dir/$f"
            rm -rf "$dir/$f"
        fi
    done
}

###############################################################################
# Calendar retention
###############################################################################
_retention_calendar() {
    log "Applying calendar retention (days=$CALENDAR_DAYS)"
    _prune_by_days "$BACKUP_DEST/daily" "$CALENDAR_DAYS"
}

###############################################################################
# Core pruning primitive (safe numeric comparisons)
###############################################################################
_prune_by_days() {
    dir="$1"
    keep_days="$2"

    [ -d "$dir" ] || return 0

    cutoff=$(_cutoff_ts_days_ago "$keep_days") || {
        log "Date arithmetic unsupported; skipping pruning"
        return 0
    }

    for path in "$dir"/*; do
        [ -e "$path" ] || continue

        name=${path##*/}
        ts=$(printf '%s\n' "$name" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')

        [ -n "$ts" ] || continue

        num=$(_numeric_ts "$ts")

        # Skip if num is empty
        [ -z "$num" ] && continue

        # Safe numeric comparison
        case "$num" in
            *[!0-9]*) continue ;;  # skip invalid numbers
        esac

        if [ "$num" -lt "$cutoff" ] 2>/dev/null; then
            if [ "$DRY_RUN" = "true" ]; then
                log "[DRY-RUN] would delete $path"
            else
                log "Deleting expired snapshot: $path"
                rm -rf "$path"
            fi
        fi
    done
}

###############################################################################
# Weekly / Monthly snapshot helpers (used by app scripts)
###############################################################################
maybe_create_weekly() {
    src="$1"
    dest="$BACKUP_DEST/weekly/$(_now_ts)"

    [ "$(date +%u)" -ne 7 ] && return 0

    log "Creating weekly snapshot"
    [ "$DRY_RUN" = "true" ] && log "[DRY-RUN] would cp -al $src $dest" \
        || cp -al "$src" "$dest"
}

maybe_create_monthly() {
    src="$1"
    dest="$BACKUP_DEST/monthly/$(_now_ts)"

    [ "$(date +%d)" != "01" ] && return 0

    log "Creating monthly snapshot"
    [ "$DRY_RUN" = "true" ] && log "[DRY-RUN] would cp -al $src $dest" \
        || cp -al "$src" "$dest"
}
