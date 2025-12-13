# Generic Backup Base Image

This repository provides a reusable Docker base image for application backup containers.
It includes a framework for:

- Structured snapshot creation
- Pluggable retention policies
- Logging and run log aggregation
- Email notifications (optional)
- A simple wrapper execution model

This base image does **not perform an application backup on its own** — it must be extended by a child image that provides an app‑specific backup script.

---

## Architectural Components

```
entrypoint.sh  (root init + exec)
    |
    v
backup.sh     (wrapper / orchestrator)
    |
    +-- sources backup_common.sh (core helpers)
    |
    +-- sources $APP_BACKUP     (app-specific logic)
```

### entrypoint.sh

- Runs as root
- Performs initial container setup (permissions, UID/GID)
- Executes `backup.sh` as a non‑root user

### backup.sh

The wrapper script:
- Defines logging (`log`, `log_error`)
- Manages run logs and cleanup
- Sources `backup_common.sh`
- Sources the application backup script (`APP_BACKUP`)
- Handles email notifications based on backup outcome

### backup_common.sh

A shared library (sourced, not executed) that provides:

- Snapshot helpers
- Retention engine
- Pluggable policies (GFS, FIFO, Calendar)
- No email or lifecycle logic (delegated to wrapper)

### APP_BACKUP

An executable script provided by extending images that:

- Defines what to back up
- Uses helpers from `backup_common.sh`
- Calls snapshot and retention logic

---

## Snapshot Directory Layout (GFS)

When using the **GFS retention policy**, backups are stored as independent snapshot tiers:

```
/backup
├── daily/
│   ├── 2025-12-01_02-00-00/
│   └── ...
├── weekly/
│   ├── 2025-12-07_02-00-00/
│   └── ...
├── monthly/
│   ├── 2025-12-01_02-00-00/
│   └── ...
├── latest -> daily/2025-12-08_02-00-00
└── logs/
    ├── backup.log
    └── ...
```

Notes:

- `daily/` contains a snapshot for every backup run
- `weekly/` contains hard‑linked snapshots promoted on Sundays
- `monthly/` contains hard‑linked snapshots promoted on the 1st of the month
- `latest` always points to the most recent daily snapshot
- Weekly and monthly snapshots are **not nested** inside daily

---

## Retention Policies

Retention behavior is controlled via environment variables.

### GFS (default)

```
RETENTION_POLICY=gfs
GFS_DAILY=7
GFS_WEEKLY=4
GFS_MONTHLY=6
```

Retention rules:

- Daily snapshots older than `GFS_DAILY` days are pruned
- Weekly snapshots older than `GFS_WEEKLY × 7` days are pruned
- Monthly snapshots older than `GFS_MONTHLY × 31` days are pruned

### FIFO

```
RETENTION_POLICY=fifo
FIFO_COUNT=14
```

Keeps only the newest `FIFO_COUNT` snapshots in `daily/`.

### Calendar

```
RETENTION_POLICY=calendar
CALENDAR_DAYS=30
```

Deletes snapshots older than `CALENDAR_DAYS` regardless of tier.

---

## Environment Variables

| Variable | Default | Description |
|--------|---------|-------------|
| BACKUP_DEST | `/backup` | Root backup directory |
| APP_BACKUP | `/default.sh` | Application backup script |
| DRY_RUN | `false` | Log actions without modifying data |
| RETENTION_POLICY | `gfs` | `gfs`, `fifo`, or `calendar` |
| GFS_DAILY | `7` | Daily snapshot retention |
| GFS_WEEKLY | `4` | Weekly snapshot retention |
| GFS_MONTHLY | `6` | Monthly snapshot retention |
| FIFO_COUNT | `14` | FIFO retention count |
| CALENDAR_DAYS | `30` | Calendar retention window |
| LOG_FILE | `/var/log/backup.log` | Persistent log file |
| EMAIL_ON_SUCCESS | `false` | Email on successful backup |
| EMAIL_ON_FAILURE | `false` | Email on failed backup |
| EMAIL_TO | `admin@example.com` | Email recipient |

---

## Example Application Backup Script

```sh
#!/bin/sh
set -e

snapshot="$BACKUP_DEST/daily/$TIMESTAMP"

create_snapshot_dir "$snapshot"

rsync -aH --delete   --link-dest="$BACKUP_DEST/latest"   "$BACKUP_SRC/" "$snapshot/"

update_latest_symlink "daily/$(basename "$snapshot")"

maybe_create_weekly "$snapshot"
maybe_create_monthly "$snapshot"

apply_retention
```

---

## Notes

- If `APP_BACKUP` points to `default.sh`, the container exits with a notice
- Email notifications require valid msmtp configuration
- Backup scripts should return meaningful exit codes
- The base image is designed to be extended

---

## License

MIT
