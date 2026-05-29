#!/bin/sh
set -u

APP_PORT="${PORT:-8080}"

echo "===== Runtime diagnostics ====="
echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "PORT=${APP_PORT}"
echo "RAILWAY_PUBLIC_DOMAIN=${RAILWAY_PUBLIC_DOMAIN:-<unset>}"
echo "RAILWAY_STATIC_URL=${RAILWAY_STATIC_URL:-<unset>}"
echo "ZERO_AUTH set: $(if [ -n "${ZERO_AUTH:-}" ]; then echo yes; else echo no; fi)"
echo "Caddy version: $(caddy version 2>&1 || true)"
echo "Xray version:"
/app/xray/xray version 2>&1 || true
echo "==============================="

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

# Start Xray-core in the background
echo "Effective Xray config:"
sed "s/${USER_UUID}/<uuid-redacted>/g" /app/config.json

echo "Effective Caddyfile:"
cat /app/Caddyfile

echo "Starting Xray-core..."
/app/xray/xray -config /app/config.json &
XRAY_PID="$!"
echo "Xray PID: ${XRAY_PID}"

sleep 2
if kill -0 "${XRAY_PID}" 2>/dev/null; then
    echo "Xray is still running after startup delay."
else
    echo "ERROR: Xray exited during startup."
fi

echo "Process snapshot before Caddy:"
ps w 2>&1 || ps 2>&1 || true

echo "Listening sockets before Caddy:"
netstat -tulpn 2>&1 || ss -tulpn 2>&1 || true

startup_probe() {
    sleep 4
    echo "===== Post-start diagnostics ====="
    echo "Process snapshot:"
    ps w 2>&1 || ps 2>&1 || true
    echo "Listening sockets:"
    netstat -tulpn 2>&1 || ss -tulpn 2>&1 || true
    echo "Local Caddy /config probe:"
    wget -S -O - "http://127.0.0.1:${APP_PORT}/config" 2>&1 || true
    echo "Local Caddy /ws probe without WebSocket headers; HTTP 400/502 output here is useful:"
    wget -S -O - "http://127.0.0.1:${APP_PORT}/ws" 2>&1 || true
    echo "===== End post-start diagnostics ====="
}

startup_probe &

# Start Caddy in the foreground to keep container running and handle proxy routing
echo "Starting Caddy reverse proxy on port ${APP_PORT}..."
exec caddy run --config /app/Caddyfile --adapter caddyfile
