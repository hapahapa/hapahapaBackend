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

# Runtime environment variables (can be overridden in your deployment)
ENV MINIO_ENDPOINT="http://minio.example.com:9000" \
    MINIO_BUCKET="pocketbase" \
    MINIO_ACCESS_KEY="admin" \
    MINIO_SECRET_KEY="password123" \
    PB_PORT=8090 \
    DEV_MODE="false" \
    # Ensure these are available at runtime:
    PB_BASE_DIR="/mnt/minio" \
    PB_DATA_DIR="/mnt/minio/data" \
    PB_PUBLIC_DIR="/mnt/minio/public" \
    PB_HOOKS_DIR="/mnt/minio/hooks" \
    PB_MIGRATIONS_DIR="/mnt/minio/migrations"

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

# Create required directories (including the mount base directory)
RUN mkdir -p "$PB_BASE_DIR" "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR" /etc/supervisor.d

# Copy the PocketBase binary from the downloader stage
COPY --from=downloader /pocketbase /usr/local/bin/pocketbase

# Copy the external entrypoint and supervisor configuration files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY supervisor.conf /etc/supervisor.conf

# Expose the PocketBase port
EXPOSE ${PB_PORT}

# Set the custom entrypoint
ENTRYPOINT ["/entrypoint.sh"]
