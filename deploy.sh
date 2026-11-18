#!/bin/bash
set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE="myapi"
TUNNEL="cf-tunnel"
PORT=8000
LOG="$APP_DIR/cloudflared.log"

echo "== venv + dependencies =="
cd "$APP_DIR"
python3 -m venv venv
source venv/bin/activate
pip install -q -r requirements.txt

echo "== API key =="
[ -f .env ] && source .env
if [ -z "$API_KEYS" ]; then
  API_KEYS=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")
  echo "API_KEYS=$API_KEYS" > .env
  echo "Notun API key: $API_KEYS"
fi

echo "== app service =="
sudo tee /etc/systemd/system/$SERVICE.service > /dev/null <<EOF
[Unit]
Description=$SERVICE
After=network.target

[Service]
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/venv/bin/gunicorn -w 3 -b 127.0.0.1:$PORT app:app
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE
sudo systemctl restart $SERVICE
sleep 2
if ! systemctl is-active --quiet $SERVICE; then
  echo "App start hoy nai. Log: sudo journalctl -u $SERVICE -n 50"
  exit 1
fi

echo "== cloudflared =="
if ! command -v cloudflared &> /dev/null; then
  curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
  chmod +x cloudflared
  sudo mv cloudflared /usr/local/bin/
fi

sudo tee /etc/systemd/system/$TUNNEL.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel for $SERVICE
After=network.target $SERVICE.service

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --url http://127.0.0.1:$PORT --logfile $LOG
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOF

rm -f "$LOG"
sudo systemctl daemon-reload
sudo systemctl enable $TUNNEL
sudo systemctl restart $TUNNEL

echo "== tunnel URL khujchi (max 30s) =="
URL=""
for i in $(seq 1 30); do
  [ -f "$LOG" ] && URL=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOG" | head -n1)
  [ -n "$URL" ] && break
  sleep 1
done

echo ""
echo "=========================================="
echo " Deployment complete!"
if [ -n "$URL" ]; then
  echo " API base URL : $URL"
  echo " Search       : $URL/search?key=$API_KEYS&q=rahul"
  echo " Status       : $URL/"
else
  echo " URL ekhono pawa jay ni. Dekho: sudo journalctl -u $TUNNEL -n 30"
fi
echo "=========================================="
