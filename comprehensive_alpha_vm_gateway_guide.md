# Comprehensive Deployment Guide — Alpha VM Gateway + Per-Project Deploy (Model A: Sparse Checkout)

---sjd: Audience
For you (and Copilot) to implement a repeatable deployment method you can reuse across projects.

---sjd: Outcome
A fresh Ubuntu VM can host multiple Dockerised apps behind one shared Gateway (Caddy), with:
- minimal host setup
- no app port collisions
- per-project deployment defined by a small `deploy/` folder checked out from the app repo (only), while the app itself is deployed from a published container image

---

## 0) Quick glossary (avoid jargon)
- **Gateway**: the shared reverse proxy (Caddy) that owns ports 80/443 and routes hostnames to app containers.
- **Project deploy descriptors**: a small set of runtime files (compose, env template, Caddy snippet) that tell the VM how to run a project’s containers.
- **Model A**: deploy descriptors are stored in the *app repo* under `deploy/` and the VM checks out only that folder using Git sparse checkout.

---

## 1) Non-negotiable rules (these prevent the “weekend clunk”)
1) **Only the Gateway binds public ports**
   - Gateway publishes: 80/tcp and 443/tcp
   - No project stack publishes 80/443
2) **Projects do not publish API host ports by default**
   - No `8000:8000` on the host
   - API is reachable only via Gateway routing on `gateway_net`
3) **Databases are private**
   - No public Postgres exposure (`0.0.0.0:5432` is forbidden)
   - GUI inspection from laptop is done via SSH tunnel when required (later)
4) **Use only Docker Compose v2 plugin**
   - The canonical command is `docker compose`
   - Do not install/use legacy `docker-compose`
5) **Canonical filesystem layout**
   - Everything lives under `/srv`

---

## 2) Naming conventions (lock these once)
- Shared Docker network: `gateway_net`
- Gateway folder: `/srv/gateway`
- Projects root: `/srv/projects`
- Gateway enabled-sites folder: `/srv/gateway/sites-enabled`

---

## 3) Repo model (what lives where)
### 3.1 Global repo: `gateway-infra`
Location on VM: `/srv/gateway`

Purpose:
- create and operate the shared Gateway
- establish common platform plumbing on the VM

Owns:
- the Gateway compose stack (Caddy container)
- persistent Caddy state directories
- `gateway_net` creation
- scripts that encode the operator “muscle memory”

Does NOT own:
- application source
- per-project `.env` values
- per-project compose stacks

### 3.2 Per project: app repo contains `deploy/`
Each app repo contains a folder `deploy/` which is the only part checked out to the VM.

`deploy/` contains only runtime descriptors:
- compose file for `api + db` (no Gateway)
- `.env.example` template
- `caddy-sites/*.caddy` snippets (one per hostname)
- optional deploy helper scripts (project-local)

The app itself is deployed via GHCR images referenced in the compose file.

---

## 4) Target VM directory layout (final state)
```
/srv
  /gateway                        (gateway-infra clone)
    stage0.sh                     (standalone stage-0 installer)
    compose.yml                   (Gateway / Caddy stack)
    Caddyfile                     (imports sites-enabled/*)
    /sites-enabled                (symlinks to project snippets)
    /caddy-data                   (persistent cert/state)
    /caddy-config                 (persistent config)
    /scripts
      bootstrap.sh
      status.sh
      reload-gateway.sh
      enable-site.sh
      disable-site.sh

  /projects
    /footie-quiz                  (app repo clone in sparse mode; only deploy/ checked out)
      /deploy
        compose.yml
        .env.example
        .env                       (created on VM; not committed)
        /caddy-sites
          alpha.example.com.caddy
```

---

## 5) The Gateway-infra operator interface (required scripts)

### 5.1 `stage0.sh` (standalone “fresh VM entrypoint”)
Purpose:
- make a fresh VM ready to run the Gateway, without needing git/docker preinstalled

Required behaviour:
- installs: `git`, `curl`, `ca-certificates` (minimum to fetch repos/scripts)
- creates `/srv`, `/srv/gateway`, `/srv/projects`
- clones or updates `gateway-infra` into `/srv/gateway`
- invokes `/srv/gateway/scripts/bootstrap.sh`
- prints a clear reminder to start a new SSH session for docker group membership to apply

Usage (placeholders):
- `curl -fsSL <RAW_STAGE0_URL> | sudo bash -s -- <GATEWAY_INFRA_REPO_URL> main`

### 5.2 `scripts/bootstrap.sh` (platform provisioning + gateway start)
Must be idempotent and safe to re-run.

Responsibilities:
- install Docker Engine if missing
- install Compose v2 plugin if missing (ensure `docker compose version` works)
- add the non-root user (`SUDO_USER`) to the `docker` group
- configure basic firewall (UFW):
  - allow: 22/tcp, 80/tcp, 443/tcp
  - deny others by default
- create `gateway_net` if missing
- ensure `/srv/gateway` directories exist:
  - `/srv/gateway/sites-enabled`
  - `/srv/gateway/caddy-data`
  - `/srv/gateway/caddy-config`
- start the Gateway stack (`docker compose up -d`) from `/srv/gateway`

### 5.3 `scripts/status.sh`
Must show, at minimum:
- docker version
- `docker compose version`
- whether `gateway_net` exists
- gateway container running status
- listening ports 80/443
- enabled site symlinks in `/srv/gateway/sites-enabled`

### 5.4 `scripts/enable-site.sh <absolute_path_to_snippet>`
Must:
- validate snippet file exists
- create/replace a symlink in `/srv/gateway/sites-enabled/` using a stable filename
- avoid manual `ln -s` usage by the operator
- optionally call `reload-gateway.sh` (if not, doc must instruct to run reload)

### 5.5 `scripts/disable-site.sh <hostname_or_enabled_filename>`
Must:
- remove symlink from `/srv/gateway/sites-enabled/`
- optionally reload

### 5.6 `scripts/reload-gateway.sh`
Must:
- reload Caddy config without recreating containers
- return non-zero on failure

---

## 6) Gateway stack requirements (compose + Caddyfile)

### 6.1 Gateway compose requirements
Gateway service:
- image: `caddy:2`
- binds host ports: `80:80` and `443:443`
- mounts:
  - `/srv/gateway/Caddyfile` → `/etc/caddy/Caddyfile` (read-only)
  - `/srv/gateway/sites-enabled` → `/etc/caddy/sites-enabled` (read-only is acceptable)
  - `/srv/gateway/caddy-data` → `/data`
  - `/srv/gateway/caddy-config` → `/config`
- joins docker network: `gateway_net`

### 6.2 Base Caddyfile requirements
- contains only global settings (optional)
- imports snippet files:
  - `import /etc/caddy/sites-enabled/*`

---

## 7) Per-project deploy descriptors (Model A: sparse checkout of `deploy/`)

### 7.1 Project compose requirements (API + DB only)
Project compose must:
- define `db` and `api` services (plus any project extras)
- attach to `gateway_net` so Caddy can reach `api`
- NOT publish host ports for `api` by default (no `ports:` mapping for `api`)
- keep Postgres private:
  - no public DB port publishing
  - optional VM-local binding only on a unique port if you *explicitly* need it later
- persist DB data using a named volume (per project)

### 7.2 DB initialisation / migrations / seeding policy
- DB volume is authoritative state.
- Init scripts in `/docker-entrypoint-initdb.d` run only on first initialisation of an empty DB volume.
- Schema evolution after initial init is done by migrations in the API image.
- Seeding must be idempotent or gated by env variable.

### 7.3 Caddy snippet requirements
Per hostname, provide one snippet file:
- location: `deploy/caddy-sites/<hostname>.caddy`
- routes `<hostname>` to `api:<internal_port>` on `gateway_net`
- contains only site routing (avoid global policies here)

---

## 8) Implementation steps you will run (complete end-to-end)

### 8.1 Fresh VM: install the Gateway (ONE command)
1) SSH to VM.
2) Run the stage-0 command:
   - `curl -fsSL <RAW_STAGE0_URL> | sudo bash -s -- <GATEWAY_INFRA_REPO_URL> main`
3) Start a new SSH session (docker group membership applies after re-login).
4) Verify:
   - `/srv/gateway/scripts/status.sh`

### 8.2 Add a project (deploy descriptors only; app runs from image)
Example: `footie-quiz`

1) Sparse clone the app repo into `/srv/projects`:
```
cd /srv/projects
git clone --filter=blob:none --sparse <APP_REPO_URL> footie-quiz
cd footie-quiz
git sparse-checkout set deploy
git checkout main
git pull
```

2) Create `.env`:
```
cd /srv/projects/footie-quiz/deploy
cp .env.example .env
```
Edit `.env` and set secrets.

3) Start the project stack:
```
cd /srv/projects/footie-quiz/deploy
docker compose up -d
```

4) Enable routing for each hostname via gateway script (no manual symlink):
```
/srv/gateway/scripts/enable-site.sh /srv/projects/footie-quiz/deploy/caddy-sites/<hostname>.caddy
/srv/gateway/scripts/reload-gateway.sh
```

### 8.3 Update a project
1) Pull deploy descriptor updates:
```
cd /srv/projects/footie-quiz
git pull
```

2) Pull images + apply:
```
cd /srv/projects/footie-quiz/deploy
docker compose pull
docker compose up -d
```

3) If routing snippets changed:
```
/srv/gateway/scripts/reload-gateway.sh
```

### 8.4 Remove a project
1) Disable routing:
```
/srv/gateway/scripts/disable-site.sh <hostname>
/srv/gateway/scripts/reload-gateway.sh
```

2) Stop the stack:
```
cd /srv/projects/footie-quiz/deploy
docker compose down
```

3) Optional: delete volumes if you want to wipe data (irreversible).

---

## 9) Acceptance checks (prove the platform is “clean”)
After setup, confirm:
- Exactly one stack binds 80/443: the Gateway
- No project stack publishes `8000` on the host
- Postgres is not publicly exposed
- `gateway_net` exists and Gateway + project containers are attached
- Enabled sites are symlinked under `/srv/gateway/sites-enabled`

---

## 10) Optional hardening (footnote)
- Include `scripts/addFail2Ban.sh` in gateway-infra, but do NOT run automatically.
- Run it only once the VM setup is stable.

---

## 11) What you should NOT do (to avoid regressions)
- Do not run `docker compose up` from random directories (creates accidental projects).
- Do not publish `8000:8000` for API under the gateway model.
- Do not run Caddy inside each project stack once multi-project hosting is required.
