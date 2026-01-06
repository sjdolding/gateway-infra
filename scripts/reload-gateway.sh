#!/usr/bin/env bash
#
# reload-gateway.sh — Reload Caddy configuration without recreating containers
#
# Purpose:
#   Tell Caddy to reload its configuration (picking up new sites-enabled/ symlinks)
#   without downtime or recreating the container.
#
# Usage:
#   /srv/gateway/scripts/reload-gateway.sh

set -euo pipefail

# Color output helpers
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() {
  echo -e "${GREEN}[reload-gateway]${NC} $*"
}

error() {
  echo -e "${RED}[reload-gateway]${NC} $*" >&2
}

# Change to gateway directory
cd /srv/gateway || {
  error "Cannot access /srv/gateway"
  exit 1
}

# Get the Caddy container name
CADDY_CONTAINER=$(docker compose ps -q caddy 2>/dev/null)

if [[ -z "$CADDY_CONTAINER" ]]; then
  error "Caddy container is not running"
  error "Start the Gateway stack first:"
  error "  cd /srv/gateway && docker compose up -d"
  exit 1
fi

# Reload Caddy config
info "Reloading Caddy configuration..."
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

if [[ $? -eq 0 ]]; then
  info "Gateway reloaded successfully"
else
  error "Gateway reload failed"
  exit 1
fi
