# Bootstrap Instructions

## Fresh VM Setup (One Command)

To deploy the Gateway infrastructure on a fresh Ubuntu VM, run this single command:

```bash
curl -fsSL https://raw.githubusercontent.com/YOURORG/gateway-infra/main/stage0.sh \
  | sudo bash -s -- https://github.com/YOURORG/gateway-infra.git main
```

**Replace `YOURORG` with your GitHub organization/username.**

## What This Does

1. Installs minimal dependencies (git, curl, ca-certificates)
2. Creates `/srv/gateway` and `/srv/projects` directories
3. Clones this repository to `/srv/gateway`
4. Installs Docker Engine and Compose v2 plugin
5. Adds your user to the `docker` group
6. Configures UFW firewall (allows 22, 80, 443)
7. Creates `gateway_net` Docker network
8. Starts the Gateway (Caddy) stack

## After Bootstrap

**Important:** Log out and start a new SSH session for docker group membership to take effect.

Then verify the setup:

```bash
/srv/gateway/scripts/status.sh
```

You should see:
- Docker and Docker Compose installed
- `gateway_net` network exists
- Gateway container running
- Ports 80/443 listening

## Next Steps

See [README.md](./README.md) for:
- Deploying your first project
- Managing sites
- Common operations
- Troubleshooting

---

**Need help?** See the complete guide: [comprehensive_alpha_vm_gateway_guide.md](./comprehensive_alpha_vm_gateway_guide.md)
