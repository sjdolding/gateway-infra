#!/usr/bin/env bash
#
# bootstrap.sh — Platform provisioning and Gateway startup
#
# Purpose:
#   Provision a VM with Docker, configure firewall, create networks,
#   and start the Gateway stack. Safe to re-run (idempotent).
#
# Usage:
#   sudo /srv/gateway/scripts/bootstrap.sh
#
# What it does:
#   1. Install Docker Engine and Compose v2 plugin
#   2. Add non-root user to docker group
#   3. Configure UFW firewall (22, 80, 443 allowed)
#   4. Create gateway_net Docker network
#   5. Create required directories (sites-enabled, caddy-data, caddy-config)
#   6. Start Gateway stack

set -euo pipefail

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() {
  echo -e "${GREEN}[bootstrap]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[bootstrap]${NC} $*"
}

error() {
  echo -e "${RED}[bootstrap]${NC} $*" >&2
}

# Validate we're running as root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
  exit 1
fi

# Detect the non-root user who invoked sudo
REAL_USER="${SUDO_USER:-}"
if [[ -z "$REAL_USER" ]]; then
  error "Could not detect non-root user. Run this script via sudo."
  exit 1
fi

info "Platform provisioning for Gateway infrastructure"
info "Target user: $REAL_USER"
echo

# Step 1: Install Docker Engine if not present
if command -v docker &> /dev/null; then
  info "Docker already installed: $(docker --version)"
else
  info "Installing Docker Engine..."
  
  # Install prerequisites
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release
  
  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  
  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install Docker Engine and plugins
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  
  info "Docker installed: $(docker --version)"
fi

# Step 2: Verify Docker Compose v2 plugin
if docker compose version &> /dev/null; then
  info "Docker Compose plugin available: $(docker compose version)"
else
  error "Docker Compose plugin not available. Installation may have failed."
  exit 1
fi

# Step 3: Add user to docker group
if groups "$REAL_USER" | grep -q '\bdocker\b'; then
  info "User $REAL_USER already in docker group"
else
  info "Adding $REAL_USER to docker group..."
  usermod -aG docker "$REAL_USER"
  warn "User added to docker group. Requires new SSH session to take effect."
fi

# Step 4: Configure UFW firewall
if command -v ufw &> /dev/null; then
  info "Configuring UFW firewall..."
  
  # Enable UFW if not already enabled
  ufw --force enable
  
  # Allow SSH, HTTP, HTTPS
  ufw allow 22/tcp comment 'SSH'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  
  # Set default policies
  ufw default deny incoming
  ufw default allow outgoing
  
  info "UFW configured: 22, 80, 443 allowed"
else
  warn "UFW not found. Skipping firewall configuration."
fi

# Step 5: Create gateway_net Docker network
if docker network inspect gateway_net &> /dev/null; then
  info "Docker network 'gateway_net' already exists"
else
  info "Creating Docker network 'gateway_net'..."
  docker network create gateway_net
fi

# Step 6: Create required directories
info "Creating Gateway directories..."
mkdir -p /srv/gateway/sites-enabled
mkdir -p /srv/gateway/caddy-data
mkdir -p /srv/gateway/caddy-config

# Set proper ownership
chown -R "$REAL_USER:$REAL_USER" /srv/gateway
chown -R "$REAL_USER:$REAL_USER" /srv/projects

# Step 7: Start Gateway stack
info "Starting Gateway stack..."
cd /srv/gateway

if [[ ! -f /srv/gateway/compose.yml ]]; then
  error "compose.yml not found in /srv/gateway"
  exit 1
fi

if [[ ! -f /srv/gateway/Caddyfile ]]; then
  error "Caddyfile not found in /srv/gateway"
  exit 1
fi

# Start as the non-root user
sudo -u "$REAL_USER" docker compose up -d

echo
info "=========================================="
info "Bootstrap complete!"
info "=========================================="
info "Gateway stack is running."
info "Verify status: /srv/gateway/scripts/status.sh"
echo
