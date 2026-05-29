#!/bin/sh
set -u

APP_PORT="${PORT:-8080}"

log_diag() {
    echo "[diag] $*"
}

# Set fallback UUID if not defined
USER_UUID="${UUID:-d342d11e-d424-4583-b36e-524ab1f0afa4}"
echo "Configuring Xray-core with UUID: ${USER_UUID}"

# Replace the default placeholder UUID in config.json with the actual UUID
sed -i "s/d342d11e-d424-4583-b36e-524ab1f0afa4/${USER_UUID}/g" /app/config.json

# If ZERO_AUTH token is provided, run Cloudflare Tunnel in the background
if [ -n "${ZERO_AUTH:-}" ]; then
    echo "ZERO_AUTH token detected. Starting Cloudflare Tunnel (server)..."
    chmod +x /app/server
    nohup /app/server tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token "$ZERO_AUTH" >/dev/null 2>&1 &
else
    echo "No ZERO_AUTH token set. Bypassing Cloudflare Tunnel (direct Railway HTTP/WS mode)."
fi

echo "Starting Xray-core..."
/app/xray/xray -config /app/config.json &
XRAY_PID="$!"
echo "Xray PID: ${XRAY_PID}"

startup_probe() {
    sleep 3
    log_diag "===== runtime diagnostics ====="
    log_diag "date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    log_diag "PORT=${APP_PORT}"
    log_diag "RAILWAY_PUBLIC_DOMAIN=${RAILWAY_PUBLIC_DOMAIN:-<unset>}"
    log_diag "RAILWAY_STATIC_URL=${RAILWAY_STATIC_URL:-<unset>}"
    log_diag "ZERO_AUTH set=$(if [ -n "${ZERO_AUTH:-}" ]; then echo yes; else echo no; fi)"
    log_diag "Caddy version: $(caddy version 2>&1 || true)"
    log_diag "Xray version:"
    /app/xray/xray version 2>&1 | sed 's/^/[diag] /' || true
    if kill -0 "${XRAY_PID}" 2>/dev/null; then
        log_diag "Xray is running."
    else
        log_diag "ERROR: Xray exited."
    fi
    log_diag "effective Xray config follows; UUID redacted"
    sed "s/${USER_UUID}/<uuid-redacted>/g" /app/config.json | sed 's/^/[xray-config] /'
    log_diag "effective Caddyfile follows"
    sed 's/^/[caddyfile] /' /app/Caddyfile
    log_diag "process snapshot"
    ps w 2>&1 || ps 2>&1 || true
    log_diag "listening sockets"
    netstat -tulpn 2>&1 || ss -tulpn 2>&1 || true
    log_diag "local Caddy /config probe"
    wget -S -O - "http://127.0.0.1:${APP_PORT}/config" 2>&1 || true
    log_diag "local Caddy /ws probe without WebSocket headers; HTTP 400/502 output here is useful"
    wget -S -O - "http://127.0.0.1:${APP_PORT}/ws" 2>&1 || true
    log_diag "===== end runtime diagnostics ====="
}

startup_probe &

# Start Caddy in the foreground to keep container running and handle proxy routing
echo "Starting Caddy reverse proxy on port ${APP_PORT}..."
exec caddy run --config /app/Caddyfile --adapter caddyfile
