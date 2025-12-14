#!/bin/sh
set -eu

# ----------------------
# Set default variables
# ----------------------
: "${TZ:=America/Chicago}"

: "${RUN_AS_ROOT:=false}"

: "${SCRIPT_USER:=backup}"
: "${USER_UID:=3000}"
: "${USER_GID:=3000}"

: "${SMTP_SERVER:=smtp.example.com}"
: "${SMTP_PORT:=25}"
: "${SMTP_TLS:=off}"
: "${SMTP_USER:=}"
: "${SMTP_USER_FILE:=}"
: "${SMTP_PASS:=}"
: "${SMTP_PASS_FILE:=}"
: "${EMAIL_FROM:=backup@example.com}"

: "${BACKUP_DEST:=/backup}"
: "${LOG_FILE:=/var/log/backup.log}"

export BACKUP_DEST LOG_FILE

# ----------------------
# Set timezone
# ----------------------
if [ -n "${TZ:-}" ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# ----------------------
# Configure user (ONLY if not running as root)
# ----------------------
if [ "$RUN_AS_ROOT" != "true" ]; then
    # Ensure group exists and has correct GID
    if ! getent group "$SCRIPT_USER" >/dev/null 2>&1; then
        addgroup -g "$USER_GID" "$SCRIPT_USER"
    else
        CURRENT_GID=$(getent group "$SCRIPT_USER" | cut -d: -f3)
        if [ "$CURRENT_GID" != "$USER_GID" ]; then
            delgroup "$SCRIPT_USER"
            addgroup -g "$USER_GID" "$SCRIPT_USER"
        fi
    fi

    # Ensure user exists and has correct UID/GID
    if ! id "$SCRIPT_USER" >/dev/null 2>&1; then
        adduser -D -u "$USER_UID" -G "$SCRIPT_USER" -s /bin/sh "$SCRIPT_USER"
    else
        CURRENT_UID=$(id -u "$SCRIPT_USER")
        if [ "$CURRENT_UID" != "$USER_UID" ]; then
            deluser "$SCRIPT_USER"
            adduser -D -u "$USER_UID" -G "$SCRIPT_USER" -s /bin/sh "$SCRIPT_USER"
        fi
    fi
fi

# ----------------------
# Generate msmtp config dynamically
# ----------------------
MSMTP_CONF="/etc/msmtp/msmtprc"
MSMTP_LOG="/var/log/msmtp.log"

mkdir -p -m 700 "$(dirname "$MSMTP_CONF")"

AUTH_LINE="off"
[ -s "$SMTP_USER_FILE" ] && SMTP_USER=$(tr -d '\r\n' < "$SMTP_USER_FILE")
[ -n "$SMTP_USER" ] && AUTH_LINE="on"

TLS_LINE="off"
[ "$SMTP_TLS" = "on" ] && TLS_LINE="on"

PASS_EVAL=""
if [ -s "$SMTP_PASS_FILE" ]; then
    PASS_EVAL="tr -d '\r\n' < $SMTP_PASS_FILE"
elif [ -n "$SMTP_PASS" ]; then
    PASS_EVAL="echo $SMTP_PASS"
fi

cat > "$MSMTP_CONF" <<EOF
defaults
auth $AUTH_LINE
tls $TLS_LINE
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile $MSMTP_LOG

account default
host $SMTP_SERVER
port $SMTP_PORT
from $EMAIL_FROM
user $SMTP_USER
passwordeval "$PASS_EVAL"
EOF

chmod 600 "$MSMTP_CONF"

if [ "$RUN_AS_ROOT" != "true" ]; then
    chown -R "$USER_UID:$USER_GID" "$(dirname "$MSMTP_CONF")"
fi

export MSMTP_CONFIG="$MSMTP_CONF"

# ----------------------
# Prepare log files
# ----------------------
touch "$LOG_FILE" "$MSMTP_LOG"
chmod 600 "$LOG_FILE" "$MSMTP_LOG"

if [ "$RUN_AS_ROOT" != "true" ]; then
    chown "$USER_UID:$USER_GID" "$LOG_FILE" "$MSMTP_LOG"
fi

# ----------------------
# Prepare backup destination
# ----------------------
mkdir -p "$BACKUP_DEST"
chmod 700 "$BACKUP_DEST"

if [ "$RUN_AS_ROOT" != "true" ]; then
    chown "$USER_UID:$USER_GID" "$BACKUP_DEST"
fi

# ----------------------
# Execute backup
# ----------------------
if [ "$RUN_AS_ROOT" = "true" ]; then
    exec backup.sh
else
    exec su-exec "$USER_UID:$USER_GID" backup.sh
fi
