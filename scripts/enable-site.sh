#!/usr/bin/env bash
#
# enable-site.sh — Enable a Caddy site by symlinking snippet to sites-enabled/
#
# Purpose:
#   Create a symlink in /srv/gateway/sites-enabled/ pointing to a project's
#   Caddy snippet file. Uses the snippet's hostname as the symlink name.
#
# Usage:
#   /srv/gateway/scripts/enable-site.sh <absolute_path_to_snippet>
#
# Example:
#   /srv/gateway/scripts/enable-site.sh /srv/projects/footie-quiz/deploy/caddy-sites/alpha.example.com.caddy

set -euo pipefail

# Color output helpers
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
  echo -e "${GREEN}[enable-site]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[enable-site]${NC} $*"
}

error() {
  echo -e "${RED}[enable-site]${NC} $*" >&2
}

# Parse arguments
SNIPPET_PATH="${1:-}"

if [[ -z "$SNIPPET_PATH" ]]; then
  error "Usage: enable-site.sh <absolute_path_to_snippet>"
  error "Example: enable-site.sh /srv/projects/myapp/deploy/caddy-sites/example.com.caddy"
  exit 1
fi

# Validate snippet file exists
if [[ ! -f "$SNIPPET_PATH" ]]; then
  error "Snippet file not found: $SNIPPET_PATH"
  exit 1
fi

# Derive symlink name from snippet filename
SNIPPET_FILENAME=$(basename "$SNIPPET_PATH")

# Ensure sites-enabled directory exists
SITES_ENABLED_DIR="/srv/gateway/sites-enabled"
if [[ ! -d "$SITES_ENABLED_DIR" ]]; then
  error "Directory not found: $SITES_ENABLED_DIR"
  error "Run bootstrap.sh first to create required directories."
  exit 1
fi

# Create symlink
SYMLINK_PATH="$SITES_ENABLED_DIR/$SNIPPET_FILENAME"

if [[ -L "$SYMLINK_PATH" ]]; then
  CURRENT_TARGET=$(readlink "$SYMLINK_PATH")
  if [[ "$CURRENT_TARGET" == "$SNIPPET_PATH" ]]; then
    info "Site already enabled: $SNIPPET_FILENAME"
    exit 0
  else
    warn "Updating existing symlink for $SNIPPET_FILENAME"
    warn "  Old target: $CURRENT_TARGET"
    warn "  New target: $SNIPPET_PATH"
    rm "$SYMLINK_PATH"
  fi
elif [[ -e "$SYMLINK_PATH" ]]; then
  error "A non-symlink file exists at $SYMLINK_PATH"
  error "Remove it manually before enabling this site."
  exit 1
fi

ln -s "$SNIPPET_PATH" "$SYMLINK_PATH"
info "Site enabled: $SNIPPET_FILENAME"
info "  Target: $SNIPPET_PATH"

echo
warn "Remember to reload the Gateway to apply changes:"
warn "  /srv/gateway/scripts/reload-gateway.sh"
echo
