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

# Set environment variables for runtime (these can be overridden in your deployment)
ENV MINIO_ENDPOINT="http://minio.example.com:9000" \
    MINIO_BUCKET="pocketbase" \
    MINIO_ACCESS_KEY="admin" \
    MINIO_SECRET_KEY="password123" \
    PB_PORT=8090 \
    DEV_MODE="false"

# Define static variables (used during build time)
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

# Create required directories
RUN mkdir -p "$PB_DATA_DIR" "$PB_PUBLIC_DIR" "$PB_HOOKS_DIR" "$PB_MIGRATIONS_DIR" /etc/supervisor.d

# Copy PocketBase binary from the downloader stage
COPY --from=downloader /pocketbase /usr/local/bin/pocketbase

# Copy external entrypoint and supervisor configuration files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY supervisor.conf /etc/supervisor.conf

# Expose the PocketBase port
EXPOSE ${PB_PORT}

# Set the custom entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
