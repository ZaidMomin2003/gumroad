#!/bin/bash

# ============================================
# Cleanmails - Self-Hosted Cold Email Platform
# One-command installer with auto-SSL
# ============================================

# Colors
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

# ---- Helpers ----
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

log() { echo -e "  ${GREEN}  [ok]${NC} $1"; }
err() { echo -e "  ${RED}  [!!]${NC} $1"; }
warn() { echo -e "  ${YELLOW}  [--]${NC} $1"; }
info() { echo -e "  ${BLUE}  [..]${NC} $1"; }

fail() {
  echo ""
  err "$1"
  echo ""
  echo -e "  ${DIM}Need help? hello@coldmail.host${NC}"
  echo ""
  exit 1
}

# ---- Parse arguments (optional; interactive prompt if omitted) ----
DOMAIN=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --domain) DOMAIN="$2"; shift ;;
    --domain=*) DOMAIN="${1#*=}" ;;
    *) ;;
  esac
  shift
done

# ---- Banner ----
banner

# ---- Root check (before prompt so we don't waste user's input) ----
if [ "$EUID" -ne 0 ]; then
  fail "Run as root:\n\n  curl -fsSL https://coldmail.host/install.sh | sudo bash"
fi

# ---- Interactive domain prompt (if not passed via --domain) ----
if [ -z "$DOMAIN" ]; then
  # Piped-via-curl safety: read from the terminal directly, not stdin
  if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    fail "Cannot prompt for domain (no terminal detected).\n\n  Try:\n  curl -fsSL https://coldmail.host/install.sh -o coldmail.sh\n  sudo bash coldmail.sh"
  fi

  echo -e "  ${WHITE}${BOLD}Domain Setup${NC}"
  echo -e "  ${DIM}────────────────────────────────────────${NC}"
  echo ""
  echo -e "  Enter the domain (or subdomain) you'll use for your dashboard."
  echo -e "  ${DIM}Example: app.yourdomain.com${NC}"
  echo -e "  ${DIM}Make sure its A record already points to this server's IP.${NC}"
  echo ""

  while true; do
    printf "  ${CYAN}Domain: ${NC}"
    read DOMAIN < /dev/tty
    DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    if [ -z "$DOMAIN" ]; then
      err "Domain cannot be empty."
      continue
    fi

    if ! [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
      err "That doesn't look like a valid domain. Use something like app.yourdomain.com"
      continue
    fi

    echo ""
    printf "  ${YELLOW}Install Cleanmails at ${WHITE}https://${DOMAIN}${YELLOW}? [Y/n] ${NC}"
    read CONFIRM < /dev/tty
    CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')

    if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "no" ]; then
      DOMAIN=""
      echo ""
      continue
    fi
    echo ""
    break
  done
fi

echo -e "  ${WHITE}${BOLD}Domain:${NC}  ${CYAN}$DOMAIN${NC}"
echo ""

# ---- Preflight ----
step "Preflight Checks"

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
step "Docker Engine"

if command -v docker &> /dev/null; then
  log "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+') installed"
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
  fail "Docker Compose plugin missing."
fi

# Pre-pull alpine:3.19 so the first in-UI update doesn't have to fetch it
info "Pre-caching updater base image..."
docker pull alpine:3.19 > /dev/null 2>&1 &
DOCKER_PULL_PID=$!

# ---- Download ----
step "Downloading Cleanmails"

mkdir -p "$INSTALL_DIR"

info "Pulling latest release..."
if curl -fsSL "$RELEASE_URL" -o /tmp/cleanmails-release.tar.gz; then
  log "Downloaded $(du -h /tmp/cleanmails-release.tar.gz | cut -f1)"
else
  fail "Download failed. Check internet."
fi

tar -xzf /tmp/cleanmails-release.tar.gz -C "$INSTALL_DIR/"
rm -f /tmp/cleanmails-release.tar.gz
log "Extracted to $INSTALL_DIR"

# ---- Build images ----
step "Building Containers"

cd "$INSTALL_DIR"

if [ -f "Dockerfile.api" ]; then
  info "API server..."
  docker build -t cleanmails-api:latest -f Dockerfile.api . > /dev/null 2>&1
  log "cleanmails-api"
fi

if [ -f "Dockerfile.worker" ]; then
  info "Background worker..."
  docker build -t cleanmails-worker:latest -f Dockerfile.worker . > /dev/null 2>&1
  log "cleanmails-worker"
fi

if [ -f "Dockerfile.frontend" ]; then
  info "Frontend..."
  docker build -t cleanmails-frontend:latest -f Dockerfile.frontend . > /dev/null 2>&1
  log "cleanmails-frontend"
fi

# ---- Configure ----
step "Generating Secure Config"

SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null || echo "unknown")

DB_PASSWORD=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)

cat > "$INSTALL_DIR/.env" <<EOF
# Cleanmails - Generated $(date -u +"%Y-%m-%d %H:%M UTC")
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

# Readable by root and docker (not world-readable, but group-readable for docker)
chmod 640 "$INSTALL_DIR/.env"
log "Secrets generated"
log "AES-256 encryption key"
log "JWT signing key"

# Caddyfile - lb_try_duration keeps clients waiting during upstream restarts
# instead of returning 502s. Critical for graceful in-place updates.
cat > "$INSTALL_DIR/Caddyfile" <<EOF
$DOMAIN {
    handle /api/* {
        reverse_proxy api:8080 {
            lb_try_duration 30s
            lb_try_interval 1s
        }
    }
    handle /health {
        reverse_proxy api:8080 {
            lb_try_duration 30s
            lb_try_interval 1s
        }
    }
    handle /t/* {
        reverse_proxy api:8080 {
            lb_try_duration 30s
            lb_try_interval 1s
        }
    }
    handle /unsubscribe/* {
        reverse_proxy api:8080 {
            lb_try_duration 30s
            lb_try_interval 1s
        }
    }
    handle {
        reverse_proxy frontend:3000 {
            lb_try_duration 30s
            lb_try_interval 1s
        }
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
  log "DNS verified: $DOMAIN -> $SERVER_IP"
else
  warn "DNS: $DOMAIN -> '${DNS_IP:-not resolving}' (server: $SERVER_IP)"
  warn "SSL will provision once DNS propagates"
fi

# ---- Launch ----
step "Launching Services"

cd "$INSTALL_DIR"

info "Starting database & cache..."
docker compose -f docker-compose.prod.yml up -d postgres redis 2>/dev/null </dev/null
sleep 8 </dev/null

# Wait for postgres
info "Waiting for database..."
DB_READY=false
for i in $(seq 1 30); do
  if docker compose -f docker-compose.prod.yml exec -T postgres pg_isready -U cleanmails > /dev/null 2>&1 </dev/null; then
    DB_READY=true
    break
  fi
  sleep 2 </dev/null
done

if [ "$DB_READY" = true ]; then
  log "Database ready"
else
  warn "Database slow to start (continuing anyway...)"
fi

info "Starting application..."
docker compose -f docker-compose.prod.yml up -d api worker frontend caddy 2>/dev/null </dev/null
log "All containers started"

# Reap the background alpine pull if it hasn't finished
wait $DOCKER_PULL_PID 2>/dev/null || true

# Health check
info "Waiting for API health..."
API_READY=false
for i in $(seq 1 30); do
  if curl -s http://localhost:8080/health 2>/dev/null | grep -q "status"; then
    API_READY=true
    break
  fi
  sleep 3 </dev/null
done

if [ "$API_READY" = true ]; then
  log "System operational"
else
  warn "API not responding yet. It may still be starting."
  warn "Check: sudo docker compose -f docker-compose.prod.yml logs api"
fi

# ---- Done ----
echo ""
echo ""
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}${BOLD}  Cleanmails is LIVE!${NC}"
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${WHITE}${BOLD}  Dashboard:${NC}   ${CYAN}https://$DOMAIN${NC}"
echo ""
echo -e "  ${DIM}  Open the URL above to activate your license${NC}"
echo -e "  ${DIM}  and create your admin account.${NC}"
echo ""
echo -e "  ${WHITE}  --- Commands -----------------------------------------------${NC}"
echo -e "  ${DIM}  Status${NC}   cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml ps"
echo -e "  ${DIM}  Logs${NC}     cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml logs -f"
echo -e "  ${DIM}  Update${NC}   cd $INSTALL_DIR && bash scripts/update.sh"
echo -e "  ${DIM}  Backup${NC}   cd $INSTALL_DIR && bash scripts/backup.sh"
echo ""
echo -e "  ${WHITE}  --- Important ----------------------------------------------${NC}"
echo -e "  ${YELLOW}  *${NC} Set rDNS/PTR on your VPS to: ${CYAN}$DOMAIN${NC}"
echo -e "  ${YELLOW}  *${NC} SSL auto-provisions (may take 1-2 min)"
echo ""
echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
