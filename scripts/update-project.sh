#!/usr/bin/env bash
set -euo pipefail

# Update a project's deploy/ folder from Git
# Usage: update-project.sh <project-name>
# Example: update-project.sh footie-quiz

if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-name>"
    echo "Example: $0 footie-quiz"
    exit 1
fi

PROJECT_NAME="$1"
DEPLOY_KEYS_DIR="$HOME/.ssh/deploy-keys"
KEY_PATH="$DEPLOY_KEYS_DIR/$PROJECT_NAME"
PROJECTS_ROOT="/srv/projects"
PROJECT_PATH="$PROJECTS_ROOT/$PROJECT_NAME"

echo "==> Updating project: $PROJECT_NAME"
echo ""

# Check if key exists
if [ ! -f "$KEY_PATH" ]; then
    echo "ERROR: Deploy key not found at: $KEY_PATH"
    echo "       Run clone-project.sh first to set up the project"
    exit 1
fi

# Check if project exists
if [ ! -d "$PROJECT_PATH" ]; then
    echo "ERROR: Project directory not found: $PROJECT_PATH"
    echo "       Run clone-project.sh first to clone the project"
    exit 1
fi

# Pull latest changes
cd "$PROJECT_PATH"

echo "==> Pulling latest deploy/ changes..."
GIT_SSH_COMMAND="ssh -i $KEY_PATH" git pull

echo ""
echo "✓ Project updated successfully"
echo ""
echo "To apply changes:"
echo "  cd $PROJECT_PATH/deploy"
echo "  docker compose pull"
echo "  docker compose up -d"
