# Stage 1: Download PocketBase
FROM alpine:3 AS downloader

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=""
ARG VERSION=0.25.0  # Set default version

ENV BUILDX_ARCH="${TARGETOS}_${TARGETARCH}${TARGETVARIANT}"

RUN wget https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/pocketbase_${VERSION}_${BUILDX_ARCH}.zip \
    && unzip pocketbase_${VERSION}_${BUILDX_ARCH}.zip \
    && chmod +x pocketbase

# Stage 2: Build the final image
FROM alpine:3

# Set environment variables for runtime (these are used at runtime, NOT build time)
ENV MINIO_ENDPOINT="http://minio.example.com:9000"
ENV MINIO_BUCKET="pocketbase"
ENV MINIO_ACCESS_KEY="admin"
ENV MINIO_SECRET_KEY="password123"
ENV PB_PORT=8090
ENV DEV_MODE="false"

# Define static variables (used during build time)
ARG PB_BASE_DIR="/mnt/minio"
ARG PB_DATA_DIR="/mnt/minio/data"
ARG PB_PUBLIC_DIR="/mnt/minio/public"
ARG PB_HOOKS_DIR="/mnt/minio/hooks"
ARG PB_MIGRATIONS_DIR="/mnt/minio/migrations"

# Install dependencies (fixing s3fs issue)
RUN apk update && apk add --no-cache \
    ca-certificates \
    wget \
    unzip \
    bash \
    curl \
    fuse3 \
    s3fs-fuse \
    supervisor \
    && rm -rf /var/cache/apk/*

# ✅ Fix: Create directories using static paths
RUN mkdir -p "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR" /etc/supervisor.d

# Copy PocketBase binary (ensure build args are set)
COPY --from=downloader /pocketbase /usr/local/bin/pocketbase

# Add startup script
COPY <<EOF /entrypoint.sh
#!/bin/sh
set -e

# Enable debug mode if DEV_MODE is true
if [ "\$DEV_MODE" = "true" ]; then
    echo "DEV_MODE enabled: Showing detailed logs."
    set -x  # Enables debug logging for shell
    PB_LOG_LEVEL="debug"
    S3FS_DEBUG_FLAGS="-d -f -o dbglevel=info"
else
    PB_LOG_LEVEL="info"
    S3FS_DEBUG_FLAGS=""
fi

# Create credentials file for s3fs
echo "\$MINIO_ACCESS_KEY:\$MINIO_SECRET_KEY" > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs

# Mount MinIO bucket using s3fs with optional debug flags
s3fs "\$MINIO_BUCKET" "$PB_BASE_DIR" -o url="\$MINIO_ENDPOINT" -o use_path_request_style -o allow_other \$S3FS_DEBUG_FLAGS

# Ensure all directories exist inside the MinIO bucket
mkdir -p "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR"

# Start Supervisor (manages s3fs and PocketBase)
exec /usr/bin/supervisord -c /etc/supervisor.conf
EOF

RUN chmod +x /entrypoint.sh

# Supervisor configuration for managing processes
COPY <<EOF /etc/supervisor.conf
[supervisord]
nodaemon=true

[program:pocketbase]
command=/usr/local/bin/pocketbase serve --http=0.0.0.0:\$PB_PORT --dir=$PB_DATA_DIR --publicDir=$PB_PUBLIC_DIR --hooksDir=$PB_HOOKS_DIR --migrationsDir=$PB_MIGRATIONS_DIR --logLevel=\$PB_LOG_LEVEL
autostart=true
autorestart=true
stderr_logfile=/dev/stderr
stdout_logfile=/dev/stdout
EOF

# Expose PocketBase port
EXPOSE ${PB_PORT}

# Use custom entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
