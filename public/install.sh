#!/bin/bash
set -e

# ========================================================
# Cleanmails - One-Line Commercial Installer
# ========================================================

# Colors for pretty output
RED='\03[0;31m'
GREEN='\03[0;32m'
YELLOW='\03[1;33m'
CYAN='\03[0;36m'
NC='\03[0m' # No Color

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}   Welcome to the Cleanmails Engine Installer    ${NC}"
echo -e "${CYAN}=================================================${NC}"

# 1. Ask for License Key right away
echo -e "\n${YELLOW}Please enter your DodoPayments License Key:${NC}"
read -p "> " LICENSE_KEY < /dev/tty

if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}Error: License Key is required.${NC}"
    exit 1
fi

MACHINE_NAME=$(hostname)

echo -e "\n${CYAN}Verifying License Key with central server...${NC}"
# Ping our secure Vercel Middleman at cleanmails.online
HTTP_STATUS=$(curl -s -w "%{http_code}" -X POST https://cleanmails.online/api/verify-license \
  -H "Content-Type: application/json" \
  -d "{\"license_key\":\"${LICENSE_KEY}\", \"instance_name\":\"${MACHINE_NAME}\"}" \
  -o /tmp/cleanmails-auth-response.json)

if [ "$HTTP_STATUS" != "200" ]; then
    ERROR_MSG=$(grep -o '"message":"[^"]*' /tmp/cleanmails-auth-response.json | cut -d'"' -f4)
    echo -e "${RED}License Verification Failed: ${ERROR_MSG:-"Invalid License Key or Server Error."}${NC}"
    exit 1
fi

echo -e "${GREEN}✔ License Verified successfully! Starting installation...${NC}"

# 2. Setup Directory and Download Binary
APP_DIR="/var/www/cleanmails"
echo -e "\n${YELLOW}Creating App Directory at ${APP_DIR}...${NC}"
sudo mkdir -p ${APP_DIR}
cd ${APP_DIR}

# Download the compiled binary from AWS S3 (you must configure this URL in your S3)
# Currently points to a public S3 URL where your binary lives.
AWS_BINARY_URL="https://your-cleanmails-bucket.s3.amazonaws.com/cleanmails-v1-linux-amd64"

echo -e "${YELLOW}Downloading Cleanmails Engine Binary...${NC}"
sudo wget -q -O cleanmails-engine $AWS_BINARY_URL
sudo chmod +x cleanmails-engine

# Save the license key to a .env file so the app knows it's activated
sudo bash -c "echo 'DODO_LICENSE_KEY=${LICENSE_KEY}' > ${APP_DIR}/.env"

# 3. Setting up SystemD Service
echo -e "${YELLOW}Configuring Auto-Boot SystemD Service...${NC}"
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
sudo systemctl start cleanmails

# 4. Final Output
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${GREEN}  Cleanmails has been installed successfully!  ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "Your engine is now running on Port 8080."
echo -e "Open your browser to: http://$(curl -s ifconfig.me):8080"
echo -e "\n${YELLOW}Note: To stop the service run 'systemctl stop cleanmails'${NC}"
