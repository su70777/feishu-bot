#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/feishu-bot}"
APP_DOMAIN="${APP_DOMAIN:-lmf.hszk365.cn}"
APP_PATH="${APP_PATH:-/feishu-bot}"
APP_PORT="${APP_PORT:-18080}"
SERVICE_NAME="${SERVICE_NAME:-feishu-bot}"
NGINX_SNIPPET="${NGINX_SNIPPET:-/etc/nginx/snippets/${SERVICE_NAME}-locations.conf}"
APP_USER="${APP_USER:-${SUDO_USER:-$USER}}"
APP_GROUP="${APP_GROUP:-$APP_USER}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

APP_PATH="/${APP_PATH#/}"
APP_PATH="${APP_PATH%/}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://${APP_DOMAIN}${APP_PATH}}"

echo "[1/8] Installing system packages..."
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx

echo "[2/8] Preparing app directory..."
sudo mkdir -p "${APP_DIR}"
sudo chown -R "${APP_USER}:${APP_GROUP}" "${APP_DIR}"

echo "[3/8] Creating virtualenv..."
"${PYTHON_BIN}" -m venv "${APP_DIR}/.venv"
"${APP_DIR}/.venv/bin/python" -m pip install --upgrade pip
"${APP_DIR}/.venv/bin/pip" install -r "${APP_DIR}/requirements.txt"

echo "[4/8] Ensuring writable runtime directories..."
mkdir -p "${APP_DIR}/data"
touch "${APP_DIR}/data/.keep"

echo "[5/8] Updating PUBLIC_BASE_URL..."
if [ -f "${APP_DIR}/.env" ]; then
    if grep -q '^PUBLIC_BASE_URL=' "${APP_DIR}/.env"; then
        sed -i.bak "s|^PUBLIC_BASE_URL=.*|PUBLIC_BASE_URL=${PUBLIC_BASE_URL}|" "${APP_DIR}/.env"
    else
        printf '\nPUBLIC_BASE_URL=%s\n' "${PUBLIC_BASE_URL}" >> "${APP_DIR}/.env"
    fi
else
    printf 'PUBLIC_BASE_URL=%s\n' "${PUBLIC_BASE_URL}" > "${APP_DIR}/.env"
    echo "Created ${APP_DIR}/.env with PUBLIC_BASE_URL only. Add Feishu credentials before production use."
fi

echo "[6/8] Installing systemd service..."
sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=Feishu Enrollment Bot
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/.venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port ${APP_PORT}
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

echo "[7/8] Writing nginx location snippet..."
sudo mkdir -p "$(dirname "${NGINX_SNIPPET}")"
sudo tee "${NGINX_SNIPPET}" >/dev/null <<EOF
location = ${APP_PATH} {
    return 301 ${APP_PATH}/;
}

location ^~ ${APP_PATH}/ {
    proxy_pass http://127.0.0.1:${APP_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF

if sudo grep -Rqs "$(basename "${NGINX_SNIPPET}")" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null; then
    sudo nginx -t
    sudo systemctl reload nginx
else
    echo "Nginx snippet was written but not enabled yet."
    echo "Add this line inside the existing server block for ${APP_DOMAIN}:"
    echo "    include ${NGINX_SNIPPET};"
    echo "Then run: sudo nginx -t && sudo systemctl reload nginx"
fi

echo "[8/8] Checking local service..."
curl -fsS "http://127.0.0.1:${APP_PORT}/healthz" || true

echo "Done."
echo "Next steps:"
echo "  1. Ensure the existing ${APP_DOMAIN} nginx server block includes: include ${NGINX_SNIPPET};"
echo "  2. Verify public health: https://${APP_DOMAIN}${APP_PATH}/healthz"
echo "  3. In Feishu backend, set callback URL to: https://${APP_DOMAIN}${APP_PATH}/feishu/events"
echo "  4. Set OAuth redirect URL to: https://${APP_DOMAIN}${APP_PATH}/auth/feishu/callback"
