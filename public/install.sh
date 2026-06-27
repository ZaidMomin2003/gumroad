#!/bin/bash
set -e

# ============================================
# CleanMails — Self-Hosted Cold Email Platform
# One-command installer with auto-SSL
# ============================================

# Colors & Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="/opt/cleanmails"
S3_BASE="https://cleanmails-sending.s3.amazonaws.com"
RELEASE_URL="${S3_BASE}/latest.tar.gz"

# ---- Pretty helpers ----
banner() {
  clear
  echo ""
  echo -e "${MAGENTA}"
  echo "   ██████╗██╗     ███████╗ █████╗ ███╗   ██╗"
  echo "  ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║"
  echo "  ██║     ██║     █████╗  ███████║██╔██╗ ██║"
  echo "  ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║"
  echo "  ╚██████╗███████╗███████╗██║  ██║██║ ╚████║"
  echo "   ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Self-Hosted Cold Email Infrastructure${NC}"
  echo -e "  ${DIM}────────────────────────────────────────${NC}"
  echo ""
}

step() {
  echo ""
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${WHITE}${BOLD} $1${NC}"
  echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log() { echo -e "  ${GREEN}  ✓${NC} $1"; }
err() { echo -e "  ${RED}  ✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}  ⚠${NC} $1"; }
info() { echo -e "  ${BLUE}  →${NC} $1"; }

spinner() {
  local pid=$1
  local msg=$2
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}  %s${NC} %s" "${spin:i++%${#spin}:1}" "$msg"
    sleep 0.1
  done
  printf "\r"
}

fail() {
  echo ""
  err "$1"
  echo ""
  echo -e "  ${DIM}Need help? ${BOLD}hello@cleanmails.online${NC}"
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

# ---- Show banner ----
banner

if [ -z "$DOMAIN" ]; then
  fail "Domain required.\n\n  ${WHITE}Usage:${NC}\n  curl -fsSL https://cleanmails.online/install.sh | sudo bash -s -- --domain ${CYAN}app.yourdomain.com${NC}"
fi

echo -e "  ${WHITE}${BOLD}Domain:${NC}  ${CYAN}$DOMAIN${NC}"
echo ""

# ---- Preflight checks ----
step "⚡ Preflight Checks"

if [ "$EUID" -ne 0 ]; then
  fail "Run as root:\n  ${WHITE}curl -fsSL https://cleanmails.online/install.sh | ${BOLD}sudo${NC}${WHITE} bash -s -- --domain $DOMAIN${NC}"
fi
log "Root access"

TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 900 ]; then
  fail "Need at least 1GB RAM (found ${TOTAL_RAM}MB)"
fi
log "RAM: ${TOTAL_RAM}MB"

FREE_DISK=$(df / | awk 'NR==2 {print int($4/1024)}')
if [ "$FREE_DISK" -lt 5000 ]; then
  fail "Need at least 5GB disk (found ${FREE_DISK}MB)"
fi
log "Disk: ${FREE_DISK}MB free"

if ss -tlnp 2>/dev/null | grep -q ':80 '; then
  fail "Port 80 is occupied. Free it first."
fi
if ss -tlnp 2>/dev/null | grep -q ':443 '; then
  fail "Port 443 is occupied. Free it first."
fi
log "Ports 80 & 443 clear"

# ---- Docker ----
step "🐳 Docker Engine"

if command -v docker &> /dev/null; then
  log "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+') already installed"
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
  systemctl enable docker > /dev/null 2>&1
  systemctl start docker
  log "Docker installed"
fi

if docker compose version &> /dev/null; then
  log "Docker Compose ready"
else
  fail "Docker Compose plugin missing. Install docker-compose-plugin."
fi

# ---- Download ----
step "📦 Downloading CleanMails"

mkdir -p "$INSTALL_DIR"

info "Pulling latest release from CDN..."
curl -fsSL "$RELEASE_URL" -o /tmp/cleanmails-release.tar.gz &
spinner $! "Downloading..."
log "Downloaded $(du -h /tmp/cleanmails-release.tar.gz | cut -f1)"

tar -xzf /tmp/cleanmails-release.tar.gz -C "$INSTALL_DIR/"
rm -f /tmp/cleanmails-release.tar.gz
log "Extracted to $INSTALL_DIR"

# ---- Build images ----
step "🔨 Building Containers"

cd "$INSTALL_DIR"

if [ -f "Dockerfile.api" ]; then
  info "Building API server..."
  docker build -t cleanmails-api:latest -f Dockerfile.api . > /dev/null 2>&1
  log "cleanmails-api"
fi

if [ -f "Dockerfile.worker" ]; then
  info "Building background worker..."
  docker build -t cleanmails-worker:latest -f Dockerfile.worker . > /dev/null 2>&1
  log "cleanmails-worker"
fi

if [ -f "Dockerfile.frontend" ]; then
  info "Building frontend..."
  docker build -t cleanmails-frontend:latest -f Dockerfile.frontend . > /dev/null 2>&1
  log "cleanmails-frontend"
fi

# ---- Configure ----
step "🔐 Generating Secure Config"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null || echo "unknown")

DB_PASSWORD=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

cat > "$INSTALL_DIR/.env" <<EOF
# CleanMails — Generated $(date -u +"%Y-%m-%d %H:%M UTC")
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
log "Secrets generated"
log "AES-256 encryption key"
log "JWT signing key"

# Caddyfile
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

log "Caddy reverse proxy configured"
log "Auto-SSL via Let's Encrypt"

# DNS check
DNS_IP=$(dig +short "$DOMAIN" 2>/dev/null | head -1 || echo "")
if [ "$DNS_IP" = "$SERVER_IP" ]; then
  log "DNS verified: $DOMAIN → $SERVER_IP"
else
  warn "DNS: $DOMAIN → '${DNS_IP:-not resolving}' (server: $SERVER_IP)"
  warn "SSL will auto-provision once DNS propagates"
fi

# ---- Launch ----
step "🚀 Launching Services"

cd "$INSTALL_DIR"

info "Starting database & cache..."
docker compose -f docker-compose.prod.yml up -d postgres redis > /dev/null 2>&1
log "PostgreSQL 16 + Redis 7"

# Wait for postgres
for i in $(seq 1 20); do
  if docker compose -f docker-compose.prod.yml exec -T postgres pg_isready -U cleanmails > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
log "Database ready"

info "Starting application..."
docker compose -f docker-compose.prod.yml up -d api worker frontend caddy > /dev/null 2>&1
log "API server"
log "Background worker"
log "Frontend"
log "Caddy (SSL termination)"

# Health check
info "Waiting for health check..."
for i in $(seq 1 30); do
  if curl -s http://localhost:8080/health 2>/dev/null | grep -q "status"; then
    break
  fi
  sleep 3
done
log "All systems operational"

# ---- Done ----
echo ""
echo ""
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}${BOLD}  ✅  CleanMails is live!${NC}"
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${WHITE}${BOLD}  🌐 Dashboard:${NC}   ${CYAN}https://$DOMAIN${NC}"
echo ""
echo -e "  ${DIM}  Open the URL above to activate your license${NC}"
echo -e "  ${DIM}  and create your admin account.${NC}"
echo ""
echo -e "  ${WHITE}  ─── Commands ───────────────────────────────────${NC}"
echo -e "  ${DIM}  Status${NC}   cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml ps"
echo -e "  ${DIM}  Logs${NC}     cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml logs -f"
echo -e "  ${DIM}  Update${NC}   cd $INSTALL_DIR && bash scripts/update.sh"
echo -e "  ${DIM}  Backup${NC}   cd $INSTALL_DIR && bash scripts/backup.sh"
echo ""
echo -e "  ${WHITE}  ─── Important ──────────────────────────────────${NC}"
echo -e "  ${YELLOW}  ⚡${NC} Set rDNS/PTR on your VPS to: ${CYAN}$DOMAIN${NC}"
echo -e "  ${YELLOW}  ⚡${NC} SSL auto-provisions (may take 1-2 min)"
echo ""
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
