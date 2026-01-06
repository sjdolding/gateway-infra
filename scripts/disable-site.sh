#!/usr/bin/env bash
#
# disable-site.sh — Disable a Caddy site by removing its symlink
#
# Purpose:
#   Remove a site symlink from /srv/gateway/sites-enabled/
#
# Usage:
#   /srv/gateway/scripts/disable-site.sh <hostname_or_filename>
#
# Example:
#   /srv/gateway/scripts/disable-site.sh alpha.example.com.caddy

set -euo pipefail

# Color output helpers
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
  echo -e "${GREEN}[disable-site]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[disable-site]${NC} $*"
}

error() {
  echo -e "${RED}[disable-site]${NC} $*" >&2
}

# Parse arguments
SITE_NAME="${1:-}"

if [[ -z "$SITE_NAME" ]]; then
  error "Usage: disable-site.sh <hostname_or_filename>"
  error "Example: disable-site.sh alpha.example.com.caddy"
  exit 1
fi

# Ensure sites-enabled directory exists
SITES_ENABLED_DIR="/srv/gateway/sites-enabled"
if [[ ! -d "$SITES_ENABLED_DIR" ]]; then
  error "Directory not found: $SITES_ENABLED_DIR"
  exit 1
fi

# Determine symlink path
SYMLINK_PATH="$SITES_ENABLED_DIR/$SITE_NAME"

# Handle case where user might have included full path
if [[ "$SITE_NAME" == /* ]]; then
  SITE_NAME=$(basename "$SITE_NAME")
  SYMLINK_PATH="$SITES_ENABLED_DIR/$SITE_NAME"
fi

# Remove symlink
if [[ -L "$SYMLINK_PATH" ]]; then
  TARGET=$(readlink "$SYMLINK_PATH")
  rm "$SYMLINK_PATH"
  info "Site disabled: $SITE_NAME"
  info "  Was pointing to: $TARGET"
elif [[ -e "$SYMLINK_PATH" ]]; then
  error "$SYMLINK_PATH exists but is not a symlink"
  error "Remove it manually if needed."
  exit 1
else
  error "Site not found: $SITE_NAME"
  exit 1
fi

echo
warn "Remember to reload the Gateway to apply changes:"
warn "  /srv/gateway/scripts/reload-gateway.sh"
echo
