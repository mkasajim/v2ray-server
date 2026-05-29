#!/bin/sh

# Set fallback UUID if not defined
USER_UUID="${UUID:-d342d11e-d424-4583-b36e-524ab1f0afa4}"
echo "Configuring Xray-core with UUID: ${USER_UUID}"

# Replace the default placeholder UUID in config.json with the actual UUID
sed -i "s/d342d11e-d424-4583-b36e-524ab1f0afa4/${USER_UUID}/g" /app/config.json

# If ZERO_AUTH token is provided, run Cloudflare Tunnel in the background
if [ -n "$ZERO_AUTH" ]; then
    echo "ZERO_AUTH token detected. Starting Cloudflare Tunnel (server)..."
    chmod +x /app/server
    nohup /app/server tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token "$ZERO_AUTH" >/dev/null 2>&1 &
else
    echo "No ZERO_AUTH token set. Bypassing Cloudflare Tunnel (direct HTTPS/TCP mode)."
fi

# Start Xray-core in the background
echo "Starting Xray-core..."
/app/xray/xray -config /app/config.json &

# Start Caddy in the foreground to keep container running and handle proxy routing
echo "Starting Caddy reverse proxy on port ${PORT:-8080}..."
exec caddy run --config /app/Caddyfile --adapter caddyfile
