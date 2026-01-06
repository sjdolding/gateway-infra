#!/usr/bin/env bash
set -euo pipefail

# Clone a project's deploy/ folder using SSH deploy key (sparse checkout)
# Usage: clone-project.sh <project-name> <github-org/repo>
# Example: clone-project.sh footie-quiz sjdolding/footie-quiz

if [ $# -ne 2 ]; then
    echo "Usage: $0 <project-name> <github-org/repo>"
    echo "Example: $0 footie-quiz sjdolding/footie-quiz"
    exit 1
fi

PROJECT_NAME="$1"
GITHUB_REPO="$2"
DEPLOY_KEYS_DIR="$HOME/.ssh/deploy-keys"
KEY_PATH="$DEPLOY_KEYS_DIR/$PROJECT_NAME"
PROJECTS_ROOT="/srv/projects"
PROJECT_PATH="$PROJECTS_ROOT/$PROJECT_NAME"

echo "==> Cloning project: $PROJECT_NAME"
echo "    Repository: $GITHUB_REPO"
echo ""

# Create deploy-keys directory if it doesn't exist
mkdir -p "$DEPLOY_KEYS_DIR"
chmod 700 "$DEPLOY_KEYS_DIR"

# Check if key already exists
if [ ! -f "$KEY_PATH" ]; then
    echo "==> Deploy key not found. Generating new key..."
    ssh-keygen -t ed25519 -C "${PROJECT_NAME}-vm-deploy" -f "$KEY_PATH" -N ""
    echo ""
    echo "==> Deploy key generated at: $KEY_PATH"
    echo ""
    echo "┌────────────────────────────────────────────────────────────────┐"
    echo "│ ACTION REQUIRED: Add this public key to GitHub                │"
    echo "└────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Public key:"
    echo "───────────────────────────────────────────────────────────────────"
    cat "${KEY_PATH}.pub"
    echo "───────────────────────────────────────────────────────────────────"
    echo ""
    echo "Steps:"
    echo "1. Go to: https://github.com/$GITHUB_REPO/settings/keys"
    echo "2. Click 'Add deploy key'"
    echo "3. Title: 'VM Deploy - $PROJECT_NAME'"
    echo "4. Paste the public key above"
    echo "5. Leave 'Allow write access' UNCHECKED (read-only)"
    echo "6. Click 'Add key'"
    echo ""
    read -p "Press Enter after adding the key to GitHub..."
    echo ""
else
    echo "==> Using existing deploy key: $KEY_PATH"
    echo ""
fi

# Check if project already exists
if [ -d "$PROJECT_PATH" ]; then
    echo "ERROR: Project directory already exists: $PROJECT_PATH"
    echo "       Remove it first or use update-project.sh to pull changes"
    exit 1
fi

# Ensure /srv/projects exists
sudo mkdir -p "$PROJECTS_ROOT"
sudo chown "$USER:$USER" "$PROJECTS_ROOT"

# Clone with sparse checkout
echo "==> Cloning $GITHUB_REPO (deploy/ only)..."
cd "$PROJECTS_ROOT"

GIT_SSH_COMMAND="ssh -i $KEY_PATH -o StrictHostKeyChecking=accept-new" \
    git clone --filter=blob:none --sparse "git@github.com:${GITHUB_REPO}.git" "$PROJECT_NAME"

cd "$PROJECT_NAME"
git sparse-checkout set deploy
git checkout main

echo ""
echo "✓ Project cloned successfully to: $PROJECT_PATH"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_PATH/deploy"
echo "  cp .env.example .env"
echo "  nano .env  # Configure secrets"
echo "  docker compose up -d"
