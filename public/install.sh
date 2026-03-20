#!/bin/bash
set -euo pipefail

# ========================================================
# Cleanmails - Enterprise Installer (Dodo Authorized)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 1. Parse Arguments
LICENSE_KEY=""
APP_DOMAIN=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --key) LICENSE_KEY="$2"; shift ;;
        --domain) APP_DOMAIN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$LICENSE_KEY" ] || [ -z "$APP_DOMAIN" ]; then
    echo -e "${RED}Error: Provider requires both --key and --domain arguments.${NC}"
    echo "Usage: ./install.sh --key CK-XXXX --domain app.yours.com"
    exit 1
fi

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}   Cleanmails Enterprise Installer Initializing  ${NC}"
echo -e "${CYAN}=================================================${NC}"

# 2. Dependency Check (Need jq for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing required dependencies (jq)...${NC}"
    sudo apt-get update -y -q
    sudo apt-get install -y jq curl unzip nginx certbot python3-certbot-nginx
fi

# 3. Dodo Payments Machine-Binding (Anti-Piracy)
echo -e "${YELLOW}Authenticating License with Dodo Payments...${NC}"

HW_ID="$(cat /etc/machine-id 2>/dev/null || hostname)"

# Activate (Bind to this VPS)
ACTIVATE_RESP=$(curl -s -X POST https://live.dodopayments.com/licenses/activate \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"$LICENSE_KEY\",\"name\":\"$HW_ID\"}")

LKI_ID=$(echo "$ACTIVATE_RESP" | jq -r '.id')

if [ -z "$LKI_ID" ] || [ "$LKI_ID" = "null" ]; then
  echo -e "${RED}Activation failed. Invalid or expired License Key.${NC}"
  echo "$ACTIVATE_RESP"
  exit 1
fi

# Validate (Strict check for this specific instance)
VALIDATE_RESP=$(curl -s -X POST https://live.dodopayments.com/licenses/validate \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"$LICENSE_KEY\",\"license_key_instance_id\":\"$LKI_ID\"}")

VALID=$(echo "$VALIDATE_RESP" | jq -r '.valid')

if [ "$VALID" != "true" ]; then
  echo -e "${RED}License invalid for this server instance.${NC}"
  exit 1
fi

echo -e "${GREEN}✓ License Authorized & Locked to Server [${HW_ID}]${NC}"

# 4. Download Core Software
APP_DIR="/var/www/cleanmails"
sudo mkdir -p ${APP_DIR}
cd ${APP_DIR}

AWS_BINARY_URL="https://cleanmails-software-dist.s3.us-east-1.amazonaws.com/cleanmails-linux-v1"
echo -e "\n${YELLOW}Downloading Cleanmails Enterprise Binary...${NC}"
sudo curl -s -o cleanmails-engine $AWS_BINARY_URL
sudo chmod +x cleanmails-engine

# Note: Assuming the standalone binary serves everything smoothly from memory or /public. 
# We maintain the generic public.zip pull in case it's still needed from earlier setups.
AWS_UI_URL="https://cleanmails-software-dist.s3.us-east-1.amazonaws.com/public.zip"
if curl --output /dev/null --silent --head --fail "$AWS_UI_URL"; then
    sudo curl -s -o public.zip $AWS_UI_URL
    sudo rm -rf ${APP_DIR}/public
    sudo unzip -q public.zip -d ${APP_DIR}/ || echo "Using embedded assets instead."
    sudo rm public.zip
fi

# 5. Background Service Configuration
echo -e "${YELLOW}Configuring Daemon...${NC}"
sudo bash -c "cat > /etc/systemd/system/cleanmails.service << EOF
[Unit]
Description=Cleanmails Engine
After=network.target

[Service]
User=root
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/cleanmails-engine
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable cleanmails
sudo systemctl restart cleanmails

# 6. Proxy & SSL Magic (Reverse Proxy to 8080)
echo -e "${YELLOW}Configuring Reverse Proxy & SSL for ${APP_DOMAIN}...${NC}"

sudo bash -c "cat > /etc/nginx/sites-available/cleanmails << EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
EOF"

sudo ln -sf /etc/nginx/sites-available/cleanmails /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

echo -e "${YELLOW}Generating Let's Encrypt SSL Certificate...${NC}"
# Non-interactive automatic SSL issue
sudo certbot --nginx -d ${APP_DOMAIN} --non-interactive --agree-tos -m admin@${APP_DOMAIN} || echo -e "${RED}SSL Generation failed. Check if DNS propagated!${NC}"

# 7. Final Success Output
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${GREEN}  🚀 Cleanmails Enterprise is LIVE!  ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "Dashboard URL: https://${APP_DOMAIN}"
echo -e ""
echo -e "${YELLOW}IMPORTANT NEXT STEP: rDNS Configuration${NC}"
echo -e "To ensure emails land in the Inbox, you MUST configure rDNS (Reverse DNS) on your VPS provider's dashboard."
echo -e "Set your rDNS / PTR Record value to: ${GREEN}${APP_DOMAIN}${NC}"
echo -e "Failure to set rDNS will result in emails going to Spam."
echo -e "================================================="
