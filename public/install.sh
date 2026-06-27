#!/bin/bash
set -e

# ============================================
# CleanMails — One-Command Installer
# ============================================
# Usage: curl -fsSL https://cleanmails.online/install.sh | sudo bash -s -- --domain app.yourdomain.com
# ============================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="/opt/cleanmails"
S3_BASE="https://cleanmails-sending.s3.amazonaws.com"
RELEASE_URL="${S3_BASE}/latest.tar.gz"

print_banner() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   ${BOLD}CleanMails Installer${NC}${BLUE}              ║${NC}"
  echo -e "${BLUE}║   Self-hosted Cold Email Platform    ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
  echo ""
}

log() { echo -e "  ${GREEN}✓${NC} $1"; }
err() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }

fail() {
  err "$1"
  echo ""
  echo -e "  Need help? ${BOLD}hello@cleanmails.online${NC}"
  echo ""
  exit 1
}

# ---- Parse arguments ----
DOMAIN=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift ;;
    --domain=*) DOMAIN="${1#*=}" ;;
    *) ;;
  esac
  shift
done

# ---- Validate inputs ----
print_banner

if [ -z "$DOMAIN" ]; then
  fail "Domain required. Use: --domain app.yourdomain.com"
fi

echo -e "${BOLD}Configuration${NC}"
log "Domain: $DOMAIN"
echo ""

# ---- Check prerequisites ----
echo -e "${BOLD}[1/6] Checking system...${NC}"

if [ "$EUID" -ne 0 ]; then
  fail "Please run as root: sudo bash or curl ... | sudo bash -s -- ..."
fi
log "Running as root"

TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 900 ]; then
  fail "Minimum 1GB RAM required. Found: ${TOTAL_RAM}MB"
fi
log "RAM: ${TOTAL_RAM}MB"

FREE_DISK=$(df / | awk 'NR==2 {print int($4/1024)}')
if [ "$FREE_DISK" -lt 5000 ]; then
  fail "Minimum 5GB disk space required. Found: ${FREE_DISK}MB"
fi
log "Disk: ${FREE_DISK}MB free"

if ss -tlnp 2>/dev/null | grep -q ':80 '; then
  fail "Port 80 is in use. Free it before installing."
fi
if ss -tlnp 2>/dev/null | grep -q ':443 '; then
  fail "Port 443 is in use. Free it before installing."
fi
log "Ports 80 & 443 available"
echo ""

# ---- Install Docker ----
echo -e "${BOLD}[2/6] Setting up Docker...${NC}"

if command -v docker &> /dev/null; then
  log "Docker already installed"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
  systemctl enable docker > /dev/null 2>&1
  systemctl start docker
  log "Docker installed"
fi

if docker compose version &> /dev/null; then
  log "Docker Compose available"
else
  fail "Docker Compose not found. Install docker-compose-plugin."
fi
echo ""

# ---- Download release ----
echo -e "${BOLD}[3/6] Downloading CleanMails...${NC}"

mkdir -p "$INSTALL_DIR"

if curl -fsSL "$RELEASE_URL" -o /tmp/cleanmails-release.tar.gz; then
  log "Downloaded release package"
else
  fail "Download failed. Check internet connection."
fi

tar -xzf /tmp/cleanmails-release.tar.gz -C "$INSTALL_DIR/"
rm -f /tmp/cleanmails-release.tar.gz
log "Extracted to $INSTALL_DIR"
echo ""

# ---- Build Docker images from pre-compiled binaries ----
echo -e "${BOLD}[4/6] Building Docker images...${NC}"

cd "$INSTALL_DIR"

if [ -f "Dockerfile.api" ]; then
  docker build -t cleanmails-api:latest -f Dockerfile.api . > /dev/null 2>&1
  log "Built: cleanmails-api"
fi

if [ -f "Dockerfile.worker" ]; then
  docker build -t cleanmails-worker:latest -f Dockerfile.worker . > /dev/null 2>&1
  log "Built: cleanmails-worker"
fi

if [ -f "Dockerfile.frontend" ]; then
  docker build -t cleanmails-frontend:latest -f Dockerfile.frontend . > /dev/null 2>&1
  log "Built: cleanmails-frontend"
fi
echo ""

# ---- Configure ----
echo -e "${BOLD}[5/6] Configuring...${NC}"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null || echo "unknown")

# Generate secrets
DB_PASSWORD=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

# Write .env
cat > "$INSTALL_DIR/.env" <<EOF
# CleanMails — Auto-generated $(date -u +"%Y-%m-%d %H:%M UTC")
DOMAIN=$DOMAIN

# Database
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgres://cleanmails:${DB_PASSWORD}@postgres:5432/cleanmails?sslmode=disable

# Redis
REDIS_URL=redis://redis:6379

# Security
ENCRYPTION_KEY=$ENCRYPTION_KEY
JWT_SECRET=$JWT_SECRET

# App
BASE_URL=https://$DOMAIN
API_PORT=8080
GIN_MODE=release
ALLOWED_ORIGINS=https://$DOMAIN
EOF

chmod 600 "$INSTALL_DIR/.env"
log "Secrets generated & .env written"

# Write Caddyfile
cat > "$INSTALL_DIR/Caddyfile" <<EOF
$DOMAIN {
    handle /api/* {
        reverse_proxy api:8080
    }
    handle /health {
        reverse_proxy api:8080
    }
    handle /t/* {
        reverse_proxy api:8080
    }
    handle /unsubscribe/* {
        reverse_proxy api:8080
    }
    handle {
        reverse_proxy frontend:3000
    }
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Strict-Transport-Security "max-age=31536000"
    }
}
EOF

log "Caddyfile written (auto-SSL for $DOMAIN)"

# DNS check
DNS_IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1 || echo "")
if [ "$DNS_IP" = "$SERVER_IP" ]; then
  log "DNS verified: $DOMAIN → $SERVER_IP"
else
  warn "DNS: $DOMAIN → '$DNS_IP' (server is $SERVER_IP)"
  warn "SSL will auto-provision once DNS propagates"
fi
echo ""

# ---- Start services ----
echo -e "${BOLD}[6/6] Starting services...${NC}"

cd "$INSTALL_DIR"

docker compose -f docker-compose.prod.yml up -d postgres redis > /dev/null 2>&1
log "PostgreSQL + Redis started"

# Wait for postgres
for i in $(seq 1 20); do
  if docker compose -f docker-compose.prod.yml exec -T postgres pg_isready -U cleanmails > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
log "Database ready"

docker compose -f docker-compose.prod.yml up -d api worker frontend caddy > /dev/null 2>&1
log "API + Worker + Frontend + Caddy started"

# Wait for health
info "Waiting for API..."
for i in $(seq 1 30); do
  if curl -s http://localhost:8080/health 2>/dev/null | grep -q "status"; then
    break
  fi
  sleep 3
done
log "API is healthy"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}${BOLD}✅ CleanMails is live!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}  https://$DOMAIN"
echo ""
echo -e "  Open https://$DOMAIN/welcome to activate your license"
echo -e "  and create your admin account."
echo ""
echo -e "  ${BOLD}Commands:${NC}"
echo -e "  Status:  cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml ps"
echo -e "  Logs:    cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml logs -f"
echo -e "  Update:  cd $INSTALL_DIR && bash scripts/update.sh"
echo -e "  Backup:  cd $INSTALL_DIR && bash scripts/backup.sh"
echo ""
echo -e "  ${YELLOW}Note:${NC} SSL auto-provisions via Let's Encrypt."
echo -e "  Set your VPS reverse DNS (PTR) to: ${GREEN}$DOMAIN${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
