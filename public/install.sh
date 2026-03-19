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

# 1. Setup Directory and Download Binary
APP_DIR="/var/www/cleanmails"
echo -e "\n${YELLOW}Creating App Directory at ${APP_DIR}...${NC}"
sudo mkdir -p ${APP_DIR}
cd ${APP_DIR}

# Download the compiled binary from AWS S3
AWS_BINARY_URL="https://cleanmails-selfhost-script.s3.us-east-1.amazonaws.com/cleanmails-linux-v1"

echo -e "${YELLOW}Downloading Cleanmails Engine Binary...${NC}"
sudo wget -q -O cleanmails-engine $AWS_BINARY_URL
sudo chmod +x cleanmails-engine

# 2. Download and Extract Dashboard UI
AWS_UI_URL="https://cleanmails-selfhost-script.s3.us-east-1.amazonaws.com/public.zip"
echo -e "${YELLOW}Downloading and Extracting Dashboard UI...${NC}"
sudo apt-get update -y && sudo apt-get install -y unzip
sudo wget -q -O public.zip $AWS_UI_URL
sudo rm -rf ${APP_DIR}/public
sudo python3 -m zipfile -e public.zip ${APP_DIR}
sudo rm public.zip



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
sudo systemctl restart cleanmails

# 4. Final Output
echo -e "\n${CYAN}=================================================${NC}"
echo -e "${GREEN}  Cleanmails has been installed successfully!  ${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "Your engine is now running on Port 8080."
echo -e "Open your browser to: http://$(curl -s ifconfig.me):8080"
echo -e "\n${YELLOW}Note: To stop the service run 'systemctl stop cleanmails'${NC}"
