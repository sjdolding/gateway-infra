# Gateway Infrastructure

Repeatable deployment infrastructure for hosting multiple Dockerized applications on a single Ubuntu VM behind a shared Caddy reverse proxy.

## Overview

This repository implements the **Gateway Pattern** for VM deployments:

- **Single reverse proxy** (Caddy) owns ports 80/443 and routes hostnames to app containers
- **Sparse checkout model**: Only `deploy/` folders from app repos are checked out to the VM
- **Image-based deployment**: Apps run from pre-built GHCR images (no source code on VM)
- **Secure by default**: No public API/DB ports, everything routed through Gateway

See [comprehensive_alpha_vm_gateway_guide.md](./comprehensive_alpha_vm_gateway_guide.md) for the complete architecture specification.

## Quick Start

### 1. Bootstrap a Fresh VM (One Command)

SSH to your Ubuntu VM and run:

```bash
curl -fsSL https://raw.githubusercontent.com/yourorg/gateway-infra/main/stage0.sh \
  | sudo bash -s -- https://github.com/yourorg/gateway-infra.git main
```

**Important**: Start a new SSH session after this completes (for docker group membership).

### 2. Verify Setup

```bash
/srv/gateway/scripts/status.sh
```

### 3. Deploy Your First Project

Example deploying `myapp`:

```bash
# Sparse clone the app repo (deploy/ folder only)
cd /srv/projects
git clone --filter=blob:none --sparse https://github.com/yourorg/myapp.git
cd myapp
git sparse-checkout set deploy
git checkout main

# Configure environment
cd deploy
cp .env.example .env
nano .env  # Edit secrets

# Start the stack
docker compose up -d

# Enable routing
/srv/gateway/scripts/enable-site.sh \
  /srv/projects/myapp/deploy/caddy-sites/alpha.example.com.caddy

/srv/gateway/scripts/reload-gateway.sh
```

Your app is now live at `https://alpha.example.com` 🎉

## Repository Structure

```
gateway-infra/
├── stage0.sh                    # Fresh VM entrypoint (curl-able)
├── compose.yml                  # Gateway/Caddy Docker stack
├── Caddyfile                    # Base Caddy config
├── scripts/
│   ├── bootstrap.sh             # Platform provisioning
│   ├── status.sh                # System status viewer
│   ├── enable-site.sh           # Enable routing for a site
│   ├── disable-site.sh          # Disable routing for a site
│   └── reload-gateway.sh        # Reload Caddy config
└── deploy-template/             # Reference example for app repos
    ├── compose.yml              # Example API + DB stack
    ├── .env.example             # Environment template
    └── caddy-sites/
        └── alpha.example.com.caddy  # Example routing snippet
```

## Operator Scripts

All scripts are in `/srv/gateway/scripts/`:

| Script | Purpose |
|--------|---------|
| `status.sh` | Show Gateway status, enabled sites, running projects |
| `enable-site.sh <path>` | Symlink Caddy snippet to sites-enabled/ |
| `disable-site.sh <name>` | Remove site symlink |
| `reload-gateway.sh` | Reload Caddy config (no downtime) |

## Project Deploy Structure

Each app repo should contain a `deploy/` folder with:

```
your-app-repo/
└── deploy/
    ├── compose.yml           # API + DB stack (no Gateway)
    ├── .env.example          # Environment template
    └── caddy-sites/
        └── yourdomain.caddy  # Routing snippet
```

See [deploy-template/](./deploy-template/) for a complete reference example.

## Common Operations

### Update a Project

```bash
cd /srv/projects/myapp
git pull

cd deploy
docker compose pull
docker compose up -d

# If routing changed:
/srv/gateway/scripts/reload-gateway.sh
```

### Remove a Project

```bash
# Disable routing
/srv/gateway/scripts/disable-site.sh alpha.example.com.caddy
/srv/gateway/scripts/reload-gateway.sh

# Stop stack
cd /srv/projects/myapp/deploy
docker compose down

# Optional: remove data volumes
docker compose down -v
```

### View Logs

```bash
# Gateway logs
cd /srv/gateway
docker compose logs -f

# Project logs
cd /srv/projects/myapp/deploy
docker compose logs -f api
```

## Architecture Principles

### Non-Negotiable Rules

1. **Only the Gateway binds public ports** (80/443)
2. **Projects don't publish API host ports** (no `8000:8000`)
3. **Databases are private** (no public Postgres exposure)
4. **Use Docker Compose v2 plugin** (`docker compose`, not `docker-compose`)
5. **Canonical filesystem layout** under `/srv/`

### Naming Conventions

- Shared Docker network: `gateway_net`
- Gateway folder: `/srv/gateway`
- Projects root: `/srv/projects`
- Enabled sites: `/srv/gateway/sites-enabled/`

## Security

- **Firewall**: UFW allows only 22, 80, 443
- **No public DB ports**: Database access via SSH tunnel if needed
- **Automatic HTTPS**: Caddy handles Let's Encrypt certificates
- **Internal networking**: Apps communicate via `gateway_net`

### SSH Tunnel for DB Access

To inspect the database from your laptop:

```bash
ssh -L 5432:localhost:5433 user@your-vm
# Then connect to localhost:5432
```

## Troubleshooting

### Container not starting?

```bash
cd /srv/projects/myapp/deploy
docker compose logs api
```

### Site not routing?

```bash
/srv/gateway/scripts/status.sh
# Check if site is in "Enabled Sites"

# Verify symlink
ls -la /srv/gateway/sites-enabled/

# Reload Gateway
/srv/gateway/scripts/reload-gateway.sh
```

### Docker permission denied?

Start a new SSH session (docker group membership requires re-login).

## Contributing

See [comprehensive_alpha_vm_gateway_guide.md](./comprehensive_alpha_vm_gateway_guide.md) for the complete specification.

## License

MIT
