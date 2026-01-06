# Migrating footie-quiz to Gateway Infrastructure

## Overview

Refactor footie-quiz app to deploy using the Gateway pattern:
- Move deployment descriptors to a `deploy/` folder
- Build and publish Docker image to GHCR
- Use sparse checkout on VM (only `deploy/` folder)
- App runs from pre-built image (no source code on VM)

---

## Step 1: Prepare footie-quiz Repository

### 1.1 Create `deploy/` folder structure

In your footie-quiz repo, create:

```
footie-quiz/
├── deploy/
│   ├── compose.yml           # API + DB stack (NO Gateway here)
│   ├── .env.example           # Environment template
│   └── caddy-sites/
│       └── alpha.footie-quiz.sjdolding.com.caddy
```

### 1.2 Create `deploy/compose.yml`

```yaml
services:
  db:
    image: postgres:16-alpine
    container_name: footie-quiz-db
    restart: unless-stopped
    
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    
    volumes:
      - db-data:/var/lib/postgresql/data
    
    networks:
      - default
      - gateway_net
    
    # Keep DB private (no public port)
    # For local inspection via SSH tunnel:
    # ssh -L 5432:localhost:5433 ubuntu@vm
    # ports:
    #   - "127.0.0.1:5433:5432"
    
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    image: ghcr.io/sjdolding/footie-quiz:${APP_VERSION:-latest}
    container_name: footie-quiz-api
    restart: unless-stopped
    
    environment:
      # App configuration
      NODE_ENV: production
      PORT: 8000
      
      # Database connection
      DB_HOST: db
      DB_PORT: 5432
      DB_NAME: ${DB_NAME}
      DB_USER: ${DB_USER}
      DB_PASSWORD: ${DB_PASSWORD}
      
      # API secrets
      JWT_SECRET: ${JWT_SECRET}
      SESSION_SECRET: ${SESSION_SECRET}
      
      # App-specific env vars
      FRONTEND_URL: ${FRONTEND_URL}
    
    depends_on:
      db:
        condition: service_healthy
    
    networks:
      - default
      - gateway_net
    
    # NO host port binding - Gateway routes via gateway_net
    
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  db-data:
    driver: local

networks:
  default:
    name: footie-quiz-internal
  gateway_net:
    external: true
```

### 1.3 Create `deploy/.env.example`

```bash
# App version (Git tag or commit SHA)
APP_VERSION=latest

# Database configuration
DB_NAME=footie_quiz_db
DB_USER=footie_quiz_user
DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD

# API secrets (generate with: openssl rand -base64 32)
JWT_SECRET=CHANGE_ME_JWT_SECRET
SESSION_SECRET=CHANGE_ME_SESSION_SECRET

# Frontend URL
FRONTEND_URL=https://alpha.footie-quiz.sjdolding.com
```

### 1.4 Create `deploy/caddy-sites/alpha.footie-quiz.sjdolding.com.caddy`

```caddy
# Footie Quiz Alpha - API routing
alpha.footie-quiz.sjdolding.com {
	# Reverse proxy to API container
	reverse_proxy api:8000 {
		# Health check
		health_uri /health
		health_interval 30s
		health_timeout 10s
		
		# Connection settings
		lb_try_duration 5s
	}
	
	# Security headers
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "SAMEORIGIN"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
	
	# Logging
	log {
		output file /var/log/caddy/footie-quiz.log {
			roll_size 100mb
			roll_keep 5
		}
	}
}
```

### 1.5 Update `.gitignore`

Add to footie-quiz `.gitignore`:

```
# Deploy secrets
deploy/.env
```

### 1.6 Commit and push

```bash
cd /path/to/footie-quiz
git add deploy/
git commit -m "Add deploy/ folder for Gateway infrastructure deployment"
git push
```

---

## Step 2: Build and Publish Docker Image

### 2.1 Create Dockerfile (if not exists)

Ensure your footie-quiz repo has a Dockerfile. Example:

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Expose port
EXPOSE 8000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8000/health || exit 1

# Start app
CMD ["node", "server.js"]
```

### 2.2 Build and tag image

```bash
cd /path/to/footie-quiz
docker build -t ghcr.io/sjdolding/footie-quiz:latest .
docker tag ghcr.io/sjdolding/footie-quiz:latest ghcr.io/sjdolding/footie-quiz:v1.0.0
```

### 2.3 Push to GHCR

Login to GitHub Container Registry:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u sjdolding --password-stdin
```

Push images:

```bash
docker push ghcr.io/sjdolding/footie-quiz:latest
docker push ghcr.io/sjdolding/footie-quiz:v1.0.0
```

### 2.4 Make GHCR package public (if needed)

1. Go to https://github.com/users/sjdolding/packages/container/footie-quiz/settings
2. Change visibility to "Public" (or configure package permissions)

---

## Step 3: Deploy to VM

### 3.1 SSH to VM

```bash
ssh ubuntu@your-vm-ip
```

### 3.2 Setup Deploy Key (for private repos)

**Note:** If your repository is public, skip to step 3.3 and use HTTPS clone.

Generate an SSH deploy key on the VM:

```bash
# Generate deploy key (no passphrase for unattended access)
ssh-keygen -t ed25519 -C "footie-quiz-vm-deploy" -f ~/.ssh/footie-quiz-deploy

# Display public key
cat ~/.ssh/footie-quiz-deploy.pub
```

Add the public key to GitHub:
1. Go to: `https://github.com/sjdolding/footie-quiz/settings/keys`
2. Click "Add deploy key"
3. Paste the public key
4. Title: "VM Alpha Deploy"
5. **Leave "Allow write access" unchecked** (read-only is sufficient)

### 3.3 Sparse clone footie-quiz (deploy/ only)

**For private repos (with deploy key):**

```bash
cd /srv/projects

# Clone using deploy key
GIT_SSH_COMMAND="ssh -i ~/.ssh/footie-quiz-deploy -o StrictHostKeyChecking=accept-new" \
  git clone --filter=blob:none --sparse git@github.com:sjdolding/footie-quiz.git

cd footie-quiz
git sparse-checkout set deploy
git checkout main
```

**For public repos:**

```bash
cd /srv/projects
git clone --filter=blob:none --sparse https://github.com/sjdolding/footie-quiz.git
cd footie-quiz
git sparse-checkout set deploy
git checkout main
```

### 3.4 Configure environment

```bash
cd /srv/projects/footie-quiz/deploy
cp .env.example .env
nano .env
```

Set real values:
- `APP_VERSION=latest` (or specific tag like `v1.0.0`)
- `DB_PASSWORD=<strong-password>`
- `JWT_SECRET=<generate-with-openssl>`
- `SESSION_SECRET=<generate-with-openssl>`
- `FRONTEND_URL=https://alpha.footie-quiz.sjdolding.com`

### 3.5 Start the stack

```bash
cd /srv/projects/footie-quiz/deploy
docker compose pull
docker compose up -d
```

### 3.6 Enable Gateway routing

```bash
/srv/gateway/scripts/enable-site.sh \
  /srv/projects/footie-quiz/deploy/caddy-sites/alpha.footie-quiz.sjdolding.com.caddy

/srv/gateway/scripts/reload-gateway.sh
```

### 3.7 Verify deployment

```bash
# Check status
/srv/gateway/scripts/status.sh

# Check footie-quiz logs
cd /srv/projects/footie-quiz/deploy
docker compose logs -f api

# Test endpoint
curl http://localhost:8000/health
```

---

## Step 4: DNS Configuration

Point your domain to the VM:

1. Go to your DNS provider
2. Create an A record:
   - Name: `alpha.footie-quiz.sjdolding.com`
   - Type: `A`
   - Value: `<VM-IP-ADDRESS>`
   - TTL: `300` (5 minutes)

Wait a few minutes for DNS propagation, then test:

```bash
curl https://alpha.footie-quiz.sjdolding.com/health
```

Caddy will automatically provision Let's Encrypt SSL certificate.

---

## Step 5: Future Updates

### Update app code:

```bash
# 1. Build and push new image locally
cd /path/to/footie-quiz
docker build -t ghcr.io/sjdolding/footie-quiz:v1.0.1 .
docker push ghcr.io/sjdolding/footie-quiz:v1.0.1

# 2. Update on VM
ssh ubuntu@your-vm
cd /srv/projects/footie-quiz/deploy
nano .env  # Update APP_VERSION=v1.0.1
docker compose pull
docker compose up -d
```

### Update deploy descriptors:

```bash
# On VM
cd /srv/projects/footie-quiz

# For private repos with deploy key:
GIT_SSH_COMMAND="ssh -i ~/.ssh/footie-quiz-deploy" git pull

# For public repos:
git pull

cd deploy
docker compose up -d

# If Caddy snippet changed:
/srv/gateway/scripts/reload-gateway.sh
```

---

## Troubleshooting

### Container not starting?

```bash
cd /srv/projects/footie-quiz/deploy
docker compose logs api
docker compose logs db
```

### Can't pull image?

Check GHCR permissions or login:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u sjdolding --password-stdin
```

### Site not routing?

```bash
/srv/gateway/scripts/status.sh
# Check if site is enabled

docker compose exec -it gateway-caddy caddy validate --config /etc/caddy/Caddyfile
```

### Database issues?

Reset database (WARNING: destroys data):

```bash
cd /srv/projects/footie-quiz/deploy
docker compose down -v
docker compose up -d
```

---

## Quick Reference

**Deploy folder structure:**
```
deploy/
├── compose.yml
├── .env.example
├── .env (created on VM, not in git)
└── caddy-sites/
    └── alpha.footie-quiz.sjdolding.com.caddy
```

**Common commands:**
```bash
# Status
/srv/gateway/scripts/status.sh

# Logs
cd /srv/projects/footie-quiz/deploy && docker compose logs -f

# Restart
cd /srv/projects/footie-quiz/deploy && docker compose restart

# Update
git pull && docker compose pull && docker compose up -d
```
