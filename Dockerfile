FROM alpine:3.23

# Install required packages
RUN apk add --no-cache \
        ca-certificates \
        coreutils \
        curl \
        msmtp \
        shadow \
        su-exec \
        tzdata \
    && update-ca-certificates

# Set working directory
WORKDIR /config

# Create backup user
RUN addgroup -g 3000 backup \
    && adduser -D -u 3000 -G backup -s /bin/sh backup

# Copy scripts
COPY entrypoint.sh backup.sh /config/

# Make scripts executable
RUN chmod +x /config/*.sh

# Entrypoint
ENTRYPOINT ["/config/entrypoint.sh"]