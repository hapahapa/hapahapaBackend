#!/bin/sh
set -e

# Enable debug mode if DEV_MODE is true
if [ "$DEV_MODE" = "true" ]; then
    echo "DEV_MODE enabled: Showing detailed logs."
    set -x  # Enable shell debug logging
    PB_LOG_LEVEL="debug"
    S3FS_DEBUG_FLAGS="-d -f -o dbglevel=info"
else
    PB_LOG_LEVEL="info"
    S3FS_DEBUG_FLAGS=""
fi

# Create credentials file for s3fs
echo "$MINIO_ACCESS_KEY:$MINIO_SECRET_KEY" > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs

# Mount the MinIO bucket using s3fs with optional debug flags.
# Note: Ensure the mount point directory ($PB_BASE_DIR) exists.
s3fs "$MINIO_BUCKET" "$PB_BASE_DIR" -o url="$MINIO_ENDPOINT" -o use_path_request_style -o allow_other $S3FS_DEBUG_FLAGS

# Ensure all required directories exist inside the mounted bucket
mkdir -p "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR"

# Start Supervisor to manage PocketBase
exec /usr/bin/supervisord -c /etc/supervisor.conf
