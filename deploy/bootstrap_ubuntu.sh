#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/feishu-bot}"
APP_DOMAIN="${APP_DOMAIN:-lmf.hszk365.cn}"
APP_USER="${APP_USER:-${SUDO_USER:-$USER}}"
APP_GROUP="${APP_GROUP:-$APP_USER}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

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

echo "[5/8] Installing systemd service..."
sudo tee /etc/systemd/system/feishu-bot.service >/dev/null <<EOF
[Unit]
Description=Feishu Enrollment Bot
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_GROUP}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/.venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable feishu-bot
sudo systemctl restart feishu-bot

echo "[6/8] Installing nginx config..."
sudo tee /etc/nginx/sites-available/feishu-bot.conf >/dev/null <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};

    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/feishu-bot.conf /etc/nginx/sites-enabled/feishu-bot.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo "[7/8] Checking local service..."
curl -fsS http://127.0.0.1:8000/healthz || true

echo "[8/8] Done."
echo "Next steps:"
echo "  1. Point DNS of ${APP_DOMAIN} to this Ubuntu server."
echo "  2. Run: sudo apt install -y certbot python3-certbot-nginx"
echo "  3. Run: sudo certbot --nginx -d ${APP_DOMAIN}"
echo "  4. In Feishu backend, set callback URL to: https://${APP_DOMAIN}/feishu/events"
