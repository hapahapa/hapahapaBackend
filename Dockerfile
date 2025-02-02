# Stage 1: Download PocketBase
FROM alpine:3 AS downloader

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=""
ARG VERSION=0.25.0  # Default version

ENV BUILDX_ARCH="${TARGETOS}_${TARGETARCH}${TARGETVARIANT}"

RUN wget https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/pocketbase_${VERSION}_${BUILDX_ARCH}.zip \
    && unzip pocketbase_${VERSION}_${BUILDX_ARCH}.zip \
    && chmod +x pocketbase

# Stage 2: Build the final image
FROM alpine:3

# Runtime environment variables (can be overridden at deployment)
ENV MINIO_ENDPOINT="http://minio.example.com:9000" \
    MINIO_BUCKET="pocketbase" \
    MINIO_ACCESS_KEY="admin" \
    MINIO_SECRET_KEY="password123" \
    PB_PORT=8090 \
    DEV_MODE="false" \
    PB_BASE_DIR="/mnt/minio" \
    PB_DATA_DIR="/mnt/minio/data" \
    PB_PUBLIC_DIR="/mnt/minio/public" \
    PB_HOOKS_DIR="/mnt/minio/hooks" \
    PB_MIGRATIONS_DIR="/mnt/minio/migrations"

# Install dependencies
# Note: "mailcap" is installed so that a basic /etc/mime.types is available.
RUN apk update && apk add --no-cache \
    ca-certificates \
    wget \
    unzip \
    bash \
    curl \
    fuse3 \
    s3fs-fuse \
    supervisor \
    mailcap \
    && rm -rf /var/cache/apk/*

# Create required directories (including the mount point)
RUN mkdir -p "$PB_BASE_DIR" "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR" /etc/supervisor.d

# Optionally, if you prefer your own MIME types file, uncomment the following line
# and place your mime.types file in the build context.
# COPY mime.types /etc/mime.types

# Copy PocketBase binary from the downloader stage
COPY --from=downloader /pocketbase /usr/local/bin/pocketbase

# Copy the external entrypoint and supervisor configuration files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY supervisor.conf /etc/supervisor.conf

# Expose PocketBase port
EXPOSE ${PB_PORT}

# Set the custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]
