# Multi-stage lightweight Dockerfile for YouTube Rain Ambience Live Streaming
FROM alpine:3.19

# Install FFmpeg, Bash, Tzdata, Procps, Coreutils, and Curl
RUN apk add --no-cache \
    bash \
    ffmpeg \
    tzdata \
    procps \
    coreutils \
    curl \
    grep \
    sed \
    gawk

# Configure System Timezone
ENV TZ=Asia/Kolkata
RUN cp /usr/share/zoneinfo/${TZ} /etc/localtime && echo "${TZ}" > /etc/timezone

# Create non-root user and application directories
RUN addgroup -g 1000 streamer && \
    adduser -u 1000 -G streamer -s /bin/bash -D streamer

WORKDIR /app

# Copy application files
COPY --chown=streamer:streamer config/ ./config/
COPY --chown=streamer:streamer scripts/ ./scripts/
COPY --chown=streamer:streamer videos/ ./videos/
COPY --chown=streamer:streamer logs/ ./logs/

# Ensure scripts are executable
RUN chmod +x scripts/*.sh

USER streamer

# Define volume mount points for persistent external video library and logs
VOLUME ["/app/videos", "/app/config", "/app/logs"]

# Healthcheck configuration
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
  CMD bash /app/scripts/health-check.sh || exit 1

# Default Entrypoint launches the streaming supervisor
CMD ["bash", "scripts/stream.sh"]
