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

# Create backup user
RUN addgroup -g 3000 backup \
    && adduser -D -u 3000 -G backup -s /bin/sh backup

# Copy scripts
COPY bin/ /usr/local/bin/
COPY lib/ /usr/local/lib/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh /usr/local/lib/*.sh

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]