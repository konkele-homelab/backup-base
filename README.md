# Generic Backup Base Image

This repository provides a lightweight, extensible Docker image that
serves as a **base layer for application-specific backup containers**.
It includes a robust backup framework with logging, retention pruning,
optional email notifications, and a standardized execution model for
pluggable backup scripts.

---

## Features

-   Provides a **general-purpose backup execution framework**
-   Supports **custom backup scripts** via `APP_BACKUP`
-   Email notification support (success and failure)
-   Automatic pruning of old backups using timestamp parsing
-   Runs as a non-root user with configurable UID/GID
-   Fully environment-driven configuration
-   Clean, isolated logs (run log + persistent log)
-   Lightweight Alpine base image

---

## Environment Variables

| Variable          | Default                | Description |
|-------------------|------------------------|-------------|
| BACKUP_DEST       | `/backup`              | Directory where backup output is stored |
| LOG_FILE          | `/var/log/backup.log`  | Persistent log file |
| EMAIL_ON_SUCCESS  | `off`                  | Enable sending email when backup succeeds (`on`/`off`) |
| EMAIL_ON_FAILURE  | `off`                  | Enable sending email when backup fails (`on`/`off`) |
| EMAIL_TO          | `admin@example.com`    | Recipient of status notifications |
| EMAIL_FROM        | `backup@example.com`   | Sender of status notifications |
| APP_BACKUP        | `/default.sh`          | Path to backup script executed by the container |
| KEEP_DAYS         | `30`                   | Number of days to retain backups |
| USER_UID          | `3000`                 | UID of backup user |
| USER_GID          | `3000`                 | GID of backup user |
| DRY_RUN           | `off`                  | If `on`, prune logic logs actions but does not delete anything |
| TZ                | `UTC`                  | Timezone used for timestamps |

---

## How Application-Specific Images Extend This Base Image

Child images typically:

1.  **Copy their backup script** into `/config/app-backup.sh`
2.  **Set `APP_BACKUP` to point to it**
3.  Optionally add environment variables or additional tooling

Example Dockerfile for an extending image:

``` dockerfile
FROM your-org/backup-base:latest

COPY myapp-backup.sh /config/myapp-backup.sh
ENV APP_BACKUP=/config/myapp-backup.sh
```

---

## Backup Script Requirements for Extending Images

A custom backup script must:

-   Be an executable file
-   Return exit code `0` on success and non-zero on failure
-   Produce output in `$BACKUP_DEST` (recommended)
-   Log using `log` or simply print lines (captured automatically)

The base container handles:

-   Timestamps
-   Error handling
-   Logging aggregation
-   Email notifications
-   Pruning

Example minimal extension script:

``` sh
#!/bin/sh
set -eu

OUT="$BACKUP_DEST/myapp_backup_$(date '+%Y-%m-%d_%H-%M-%S').tar.gz"

tar -czf "$OUT" /data/myapp
```

---

## Docker Compose Example

``` yaml
version: "3.9"

services:
  backup-base-example:
    image: your-dockerhub-username/backup-base:latest
    environment:
      BACKUP_DEST: /backup
      APP_BACKUP: /config/app-backup.sh
      KEEP_DAYS: 30
      EMAIL_ON_FAILURE: "on"
    volumes:
      - /backup:/backup
      - ./app-backup.sh:/config/app-backup.sh
```

---

## Logging

The base image produces:

-   **Persistent Log:** `/var/log/backup.log`
-   **Per-run Log:** Temporary file printed at the end and used for
    email bodies

Includes:

-   Backup start/end timestamps
-   Script output
-   Prune operations
-   Errors and failures

---

## Notes

-   If `APP_BACKUP` remains `default.sh`, the container exits cleanly
    with a notice.
-   msmtp must be configured if email alerts are enabled.
-   Backup scripts should be deterministic and return meaningful exit
    codes.
-   This base image is intended to be extended --- it does not perform
    any application backup on its own.
