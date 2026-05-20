#!/bin/bash
set -euo pipefail

# ========================================================
# Cleanmails - Enterprise Installer
# One-command deployment with automatic SSL
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Parse Arguments ---
LICENSE_KEY=""
APP_DOMAIN=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --key) LICENSE_KEY="$2"; shift ;;
        --domain) APP_DOMAIN="$2"; shift ;;
        *) echo -e "${RED}Unknown parameter: $1${NC}"; exit 1 ;;
    esac
    shift
done

if [ -z "$LICENSE_KEY" ] || [ -z "$APP_DOMAIN" ]; then
    echo -e "${RED}Usage: ./install.sh --key YOUR_KEY --domain app.yourdomain.com${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}   Cleanmails — Installing on this server${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo ""

# --- Root Check ---
if [ "$EUID" -ne 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root.${NC}"
  echo -e "Run with: ${BOLD}sudo bash install.sh --key YOUR_KEY --domain YOUR_DOMAIN${NC}"
  echo -e "Or:       ${BOLD}curl -sSL https://cleanmails.online/install.sh | sudo bash -s -- --key YOUR_KEY --domain YOUR_DOMAIN${NC}"
  exit 1
fi

# --- Step 1: System Dependencies ---
echo -e "${YELLOW}[1/7]${NC} Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq jq curl unzip nginx certbot python3-certbot-nginx > /dev/null 2>&1
echo -e "${GREEN}  ✓ Dependencies installed${NC}"

# --- Step 2: License Activation ---
echo -e "${YELLOW}[2/7]${NC} Activating license..."

HW_ID="$(cat /etc/machine-id 2>/dev/null || hostname)"
DODO_URL="https://test.dodopayments.com"

ACTIVATE_RESP=$(curl -sf -X POST "${DODO_URL}/licenses/activate" \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"$LICENSE_KEY\",\"name\":\"$HW_ID\"}" 2>/dev/null || echo '{}')

LKI_ID=$(echo "$ACTIVATE_RESP" | jq -r '.id // empty')

if [ -z "$LKI_ID" ]; then
  echo -e "${RED}  ✗ License activation failed. Check your key.${NC}"
  echo "  Response: $ACTIVATE_RESP"
  exit 1
fi

# Validate
VALIDATE_RESP=$(curl -sf -X POST "${DODO_URL}/licenses/validate" \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"$LICENSE_KEY\",\"license_key_instance_id\":\"$LKI_ID\"}" 2>/dev/null || echo '{}')

VALID=$(echo "$VALIDATE_RESP" | jq -r '.valid // "false"')

if [ "$VALID" != "true" ]; then
  echo -e "${RED}  ✗ License is not valid for this server.${NC}"
  exit 1
fi

echo -e "${GREEN}  ✓ License activated (bound to ${HW_ID:0:8}...)${NC}"

# --- Step 3: Download Binary ---
echo -e "${YELLOW}[3/7]${NC} Downloading Cleanmails..."

APP_DIR="/opt/cleanmails"
mkdir -p ${APP_DIR}
cd ${APP_DIR}

BINARY_URL="https://cleanmails-selfhost-script.s3.us-east-1.amazonaws.com/cleanmails-linux-v1"
curl -sf -o cleanmails "$BINARY_URL"
chmod +x cleanmails

echo -e "${GREEN}  ✓ Binary downloaded${NC}"

# --- Step 4: Download Frontend Assets ---
echo -e "${YELLOW}[4/7]${NC} Downloading UI assets..."

UI_URL="https://cleanmails-selfhost-script.s3.us-east-1.amazonaws.com/public.zip"
if curl --output /dev/null --silent --head --fail "$UI_URL"; then
    curl -sf -o public.zip "$UI_URL"
    rm -rf ${APP_DIR}/public
    unzip -qo public.zip -d ${APP_DIR}/ 2>/dev/null || true
    rm -f public.zip
    echo -e "${GREEN}  ✓ UI assets deployed${NC}"
else
    echo -e "${YELLOW}  → Using embedded assets${NC}"
fi

# --- Step 5: Configure & Start Service ---
echo -e "${YELLOW}[5/7]${NC} Configuring service..."

# Generate a secure master key (32 chars for AES-256)
MASTER_KEY=$(openssl rand -hex 16)

# Create uploads directories
mkdir -p ${APP_DIR}/uploads
mkdir -p ${APP_DIR}/public/uploads

cat > /etc/systemd/system/cleanmails.service << EOF
[Unit]
Description=Cleanmails Engine
After=network.target

[Service]
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/cleanmails
Restart=always
RestartSec=5
Environment=APP_ENV=development
Environment=MASTER_KEY=${MASTER_KEY}
Environment=SITE_URL=https://${APP_DOMAIN}
Environment=ADDR=:8080
Environment=TRUST_PROXY=true
Environment=SMTP_FROM_EMAIL=verify@${APP_DOMAIN}
Environment=SMTP_HELO_NAME=${APP_DOMAIN}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cleanmails --quiet
systemctl restart cleanmails

# Wait for the app to be ready
echo -n "  Starting"
for i in {1..15}; do
    if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}  ✓ Cleanmails running on port 8080${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# --- Step 6: Configure Nginx + SSL ---
echo -e "${YELLOW}[6/7]${NC} Setting up Nginx reverse proxy..."

cat > /etc/nginx/sites-available/cleanmails << EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};
    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/cleanmails /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t -q && systemctl restart nginx

echo -e "${GREEN}  ✓ Nginx configured${NC}"

echo -e "${YELLOW}[7/7]${NC} Generating SSL certificate..."
certbot --nginx -d ${APP_DOMAIN} --non-interactive --agree-tos -m admin@${APP_DOMAIN} --quiet 2>/dev/null \
  && echo -e "${GREEN}  ✓ SSL certificate issued${NC}" \
  || echo -e "${YELLOW}  → SSL failed (DNS may not have propagated yet). Run later: certbot --nginx -d ${APP_DOMAIN}${NC}"

# --- Done ---
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}   ✓ Cleanmails is LIVE!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  https://${APP_DOMAIN}"
echo -e "  ${BOLD}Master Key:${NC} ${MASTER_KEY}"
echo -e ""
echo -e "  ${YELLOW}Save your master key somewhere safe.${NC}"
echo -e "  ${YELLOW}It's used to encrypt all stored passwords and tokens.${NC}"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "  1. Open https://${APP_DOMAIN} and create your admin account"
echo -e "  2. Add your sending domains"
echo -e "  3. Set rDNS/PTR record on your VPS to: ${GREEN}${APP_DOMAIN}${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
