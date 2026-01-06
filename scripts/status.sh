#!/usr/bin/env bash
#
# status.sh — Display Gateway platform status
#
# Purpose:
#   Show system health, running services, network status, and enabled sites.
#
# Usage:
#   /srv/gateway/scripts/status.sh

set -euo pipefail

# Color output helpers
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

section() {
  echo -e "\n${BLUE}=== $* ===${NC}"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

failure() {
  echo -e "${RED}✗${NC} $*"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Gateway Platform Status${NC}"
echo -e "${BLUE}========================================${NC}"

# Docker version
section "Docker Version"
if command -v docker &> /dev/null; then
  success "Docker: $(docker --version)"
else
  failure "Docker not installed"
fi

# Docker Compose version
if docker compose version &> /dev/null; then
  success "Docker Compose: $(docker compose version --short)"
else
  failure "Docker Compose plugin not available"
fi

# Docker network
section "Docker Network"
if docker network inspect gateway_net &> /dev/null; then
  success "gateway_net exists"
  
  # List containers on gateway_net
  CONTAINERS=$(docker network inspect gateway_net -f '{{range .Containers}}{{.Name}} {{end}}')
  if [[ -n "$CONTAINERS" ]]; then
    echo "  Attached containers: $CONTAINERS"
  else
    warning "  No containers attached"
  fi
else
  failure "gateway_net does not exist"
fi

# Gateway container status
section "Gateway Stack"
cd /srv/gateway 2>/dev/null || {
  failure "Cannot access /srv/gateway"
  exit 1
}

if docker compose ps --format json 2>/dev/null | grep -q .; then
  docker compose ps --format table
else
  failure "No Gateway containers running"
fi

# Listening ports
section "Listening Ports"
if ss -tlnp 2>/dev/null | grep -E ':(80|443)\s' > /dev/null; then
  success "Ports 80/443 are listening:"
  ss -tlnp 2>/dev/null | grep -E ':(80|443)\s' | awk '{print "  "$4, $6}'
else
  warning "Ports 80/443 are not listening"
fi

# Enabled sites
section "Enabled Sites"
if [[ -d /srv/gateway/sites-enabled ]]; then
  SITE_COUNT=$(find /srv/gateway/sites-enabled -type l 2>/dev/null | wc -l)
  
  if [[ $SITE_COUNT -gt 0 ]]; then
    success "$SITE_COUNT site(s) enabled:"
    for site in /srv/gateway/sites-enabled/*; do
      if [[ -L "$site" ]]; then
        target=$(readlink "$site")
        echo "  $(basename "$site") -> $target"
      fi
    done
  else
    warning "No sites enabled"
  fi
else
  failure "/srv/gateway/sites-enabled does not exist"
fi

# Project stacks
section "Project Stacks"
if [[ -d /srv/projects ]]; then
  PROJECT_COUNT=$(find /srv/projects -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
  
  if [[ $PROJECT_COUNT -gt 0 ]]; then
    success "$PROJECT_COUNT project(s) found:"
    for project in /srv/projects/*; do
      if [[ -d "$project" ]]; then
        PROJECT_NAME=$(basename "$project")
        echo "  $PROJECT_NAME"
        
        # Check if compose stack is running
        if [[ -f "$project/deploy/compose.yml" ]]; then
          cd "$project/deploy"
          if docker compose ps --format json 2>/dev/null | grep -q .; then
            echo "    Status: running"
          else
            echo "    Status: not running"
          fi
        fi
      fi
    done
  else
    warning "No projects deployed"
  fi
else
  warning "/srv/projects does not exist"
fi

echo -e "\n${BLUE}========================================${NC}\n"
