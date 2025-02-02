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

# Set runtime environment variables
ENV MINIO_ENDPOINT="http://minio.example.com:9000"
ENV MINIO_BUCKET="pocketbase"
ENV MINIO_ACCESS_KEY="admin"
ENV MINIO_SECRET_KEY="password123"
ENV PB_PORT=8090
ENV DEV_MODE="false"

# Define build-time variables
ARG PB_BASE_DIR="/mnt/minio"
ARG PB_DATA_DIR="/mnt/minio/data"
ARG PB_PUBLIC_DIR="/mnt/minio/public"
ARG PB_HOOKS_DIR="/mnt/minio/hooks"
ARG PB_MIGRATIONS_DIR="/mnt/minio/migrations"

# Install dependencies
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

# ✅ Fix: Use build-time variables in `RUN` commands instead of `ENV`
RUN mkdir -p "$PB_BASE_DIR/data" "$PB_BASE_DIR/public" "$PB_BASE_DIR/hooks" "$PB_BASE_DIR/migrations" /etc/supervisor.d

# Copy PocketBase binary
COPY --from=downloader /pocketbase /usr/local/bin/pocketbase

# Add startup script
COPY <<EOF /entrypoint.sh
#!/bin/sh
set -e

echo "✅ ENTRYPOINT STARTED"
echo "📌 Checking MinIO credentials..."
echo "MINIO_ENDPOINT=\$MINIO_ENDPOINT"
echo "MINIO_BUCKET=\$MINIO_BUCKET"

# ✅ Validate MINIO_ENDPOINT before using it
if [ -z "\$MINIO_ENDPOINT" ] || ! echo "\$MINIO_ENDPOINT" | grep -qE '^https?://'; then
  echo "❌ ERROR: MINIO_ENDPOINT is not set or invalid!"
  exit 1
fi

# Debug if s3fs is available
if ! command -v s3fs > /dev/null 2>&1; then
  echo "❌ ERROR: s3fs-fuse is not installed!"
  exit 1
fi

echo "📌 Mounting MinIO storage..."
s3fs "\$MINIO_BUCKET" "$PB_BASE_DIR" -o url="\$MINIO_ENDPOINT" -o use_path_request_style -o allow_other || {
  echo "❌ ERROR: Failed to mount MinIO!"
  exit 1
}

echo "✅ MinIO storage mounted successfully."

exec /usr/local/bin/pocketbase serve --http=0.0.0.0:\$PB_PORT --dir="$PB_BASE_DIR/data" --publicDir="$PB_BASE_DIR/public" --hooksDir="$PB_BASE_DIR/hooks" --migrationsDir="$PB_BASE_DIR/migrations" --logLevel=info
EOF

RUN chmod +x /entrypoint.sh

# Supervisor configuration
COPY <<EOF /etc/supervisor.conf
[supervisord]
nodaemon=true

[program:pocketbase]
command=/usr/local/bin/pocketbase serve --http=0.0.0.0:\$PB_PORT --dir="$PB_BASE_DIR/data" --publicDir="$PB_BASE_DIR/public" --hooksDir="$PB_BASE_DIR/hooks" --migrationsDir="$PB_BASE_DIR/migrations" --logLevel=info
autostart=true
autorestart=true
stderr_logfile=/dev/stderr
stdout_logfile=/dev/stdout
EOF

# Expose PocketBase port
EXPOSE ${PB_PORT}

# Use custom entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
