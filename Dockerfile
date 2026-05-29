# --- Stage 1: Build/Download Binaries ---
FROM alpine:latest AS builder
RUN apk add --no-cache curl unzip

WORKDIR /app

# Download latest Xray-core
RUN curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" && \
    mkdir -p /app/xray && \
    unzip xray.zip -d /app/xray

# Download latest Caddy
RUN caddy_url=$(curl -sIL -o /dev/null -w "%{url_effective}" "https://github.com/caddyserver/caddy/releases/latest") && \
    tag="${caddy_url##*/}" && \
    version="${tag#v}" && \
    curl -L -o caddy.tar.gz "https://github.com/caddyserver/caddy/releases/download/${tag}/caddy_${version}_linux_amd64.tar.gz" && \
    tar -xzf caddy.tar.gz caddy

# --- Stage 2: Final Run Image ---
FROM alpine:latest
RUN apk add --no-cache ca-certificates libc6-compat mailcap

WORKDIR /app

# Copy binaries from builder
COPY --from=builder /app/xray /app/xray
COPY --from=builder /app/caddy /usr/local/bin/caddy

# Copy configuration and project files
COPY config.json /app/config.json
COPY Caddyfile /app/Caddyfile
COPY public /app/public
COPY entrypoint.sh /app/entrypoint.sh
COPY server /app/server

# Expose ports
# 8080: main Caddy proxy port (HTTP/WS/gRPC)
# 10088: direct TCP VLESS port (optional for Railway TCP Proxy)
EXPOSE 8080 10088

# Setup permissions
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
