#!/usr/bin/env bash
#
# stage0.sh — Fresh VM entrypoint for gateway-infra deployment
#
# Purpose:
#   Bootstrap a virgin Ubuntu VM to run the Gateway infrastructure.
#   This script is designed to be curl-able and run without any prerequisites.
#
# Usage:
#   curl -fsSL <RAW_STAGE0_URL> | sudo bash -s -- <GATEWAY_INFRA_REPO_URL> <BRANCH>
#
# Example:
#   curl -fsSL https://raw.githubusercontent.com/yourorg/gateway-infra/main/stage0.sh \
#     | sudo bash -s -- https://github.com/yourorg/gateway-infra.git main
#
# What it does:
#   1. Installs minimal dependencies (git, curl, ca-certificates)
#   2. Creates /srv directory structure
#   3. Clones/updates gateway-infra repo to /srv/gateway
#   4. Invokes bootstrap.sh for platform provisioning
#   5. Reminds operator to start new SSH session for docker group membership

set -euo pipefail

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
  echo -e "${GREEN}[stage0]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[stage0]${NC} $*"
}

error() {
  echo -e "${RED}[stage0]${NC} $*" >&2
}

# Validate we're running as root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root (use sudo)"
  exit 1
fi

# Parse arguments
REPO_URL="${1:-}"
BRANCH="${2:-main}"

if [[ -z "$REPO_URL" ]]; then
  error "Usage: sudo bash stage0.sh <GATEWAY_INFRA_REPO_URL> [branch]"
  error "Example: sudo bash stage0.sh https://github.com/yourorg/gateway-infra.git main"
  exit 1
fi

info "Gateway Infrastructure Stage-0 Bootstrap"
info "Repository: $REPO_URL"
info "Branch: $BRANCH"
echo

# Step 1: Install minimal dependencies
info "Installing minimal dependencies (git, curl, ca-certificates)..."
apt-get update -qq
apt-get install -y -qq git curl ca-certificates > /dev/null 2>&1

# Step 2: Create directory structure
info "Creating /srv directory structure..."
mkdir -p /srv/gateway
mkdir -p /srv/projects

# Step 3: Clone or update gateway-infra
if [[ -d /srv/gateway/.git ]]; then
  info "Updating existing gateway-infra repository..."
  cd /srv/gateway
  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git pull origin "$BRANCH"
else
  info "Cloning gateway-infra repository..."
  git clone --branch "$BRANCH" "$REPO_URL" /srv/gateway
fi

# Step 4: Ensure bootstrap.sh is executable
chmod +x /srv/gateway/scripts/*.sh 2>/dev/null || true

# Step 5: Invoke bootstrap.sh
info "Invoking bootstrap.sh for platform provisioning..."
echo
if [[ -f /srv/gateway/scripts/bootstrap.sh ]]; then
  /srv/gateway/scripts/bootstrap.sh
else
  error "bootstrap.sh not found in repository!"
  exit 1
fi

echo
info "=========================================="
info "Stage-0 complete!"
info "=========================================="
warn ""
warn "IMPORTANT: Start a NEW SSH session for docker group membership to take effect."
warn ""
info "After reconnecting, verify the setup:"
info "  /srv/gateway/scripts/status.sh"
echo
