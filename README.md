# dpanel

Docker hosting control panel for **Ubuntu 24.04 LTS**: manage websites (Node/PHP) and MariaDB via a Nuxt web UI.

## Requirements

- Ubuntu 24.04 LTS (22.04 may work; not fully tested)
- Root or sudo
- 2 GB+ RAM recommended
- 10 GB+ free disk
- Ports **80** and **8443** available (80 = sites + panel domain; 8443 = panel via IP only)

## Install

**SSH (recommended)** — step progress on screen; full log in `/var/log/dpanel-install.log`:

```bash
cd /tmp && curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh && curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install-screen.sh && grep '^INSTALLER_VERSION=' install.sh && sudo bash install-screen.sh
```

Detach: `Ctrl+A` `D` · Reattach: `sudo screen -r dpanel-install`

**Direct** (keep SSH open; do not pipe to `tee`):

```bash
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh && sudo bash install.sh
```

Install takes **15–30 minutes**. Terminal shows step lines only; details: `tail -f /var/log/dpanel-install.log`. Verbose terminal output: `DPANEL_VERBOSE=1`.

Check installer version before running (should be **1.0.36+**):

```bash
grep '^INSTALLER_VERSION=' install.sh
```

### Install failed or stopped mid-way

If `/opt/stack/.env` already exists (steps 1–6 done) but build or Docker failed:

```bash
sudo tail -50 /var/log/dpanel-install.log
sudo bash /opt/stack/infra/scripts/install-continue.sh
```

Common fixes:

| Problem | Action |
|---------|--------|
| `Identifier 'loading' has already been declared` | Pull latest repo (`install.sh` v1.0.35+ fixes panel build) |
| Build `Killed` | Add 2G swap, then `install-continue.sh` |
| `apt lock` | Wait or `sudo dpkg --configure -a`, re-run install |
| `dpanel: command not found` | `sudo ln -sf /opt/stack/infra/scripts/dpanel-cli.sh /usr/local/bin/dpanel` |

### Non-interactive install

```bash
export DPANEL_NONINTERACTIVE=1
export PANEL_DOMAIN=panel.example.com
export ADMIN_EMAIL=admin@example.com
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
sudo -E bash install.sh
```

Default login password is **12345678**. Change after install:

```bash
dpanel setpass 'Your_new_password'
```

### Options

| Variable | Default | Description |
|----------|---------|-------------|
| `DPANEL_SKIP_UPGRADE` | — | Use `DPANEL_FULL_UPGRADE=1` to run `apt upgrade` |
| `DPANEL_FORCE=1` | — | Reinstall over existing `/opt/stack` without prompt |
| `APT_LOCK_WAIT_SEC` | `600` | Max wait for apt lock (unattended-upgrades) |

## After install

- Panel: `https://<panel-domain>` (Cloudflare) or `http://<server-ip>:8443` (bootstrap, no domain yet)
- Summary file: `/opt/stack/CREDENTIALS.txt`
- Default password: `12345678` → `dpanel setpass 'new-password'`
- **MariaDB:** panel settings live in JSON files, not MySQL. MariaDB is for your PHP apps — create databases in the panel. New installs do not create a default `dpanel` database. Older VPS may still have an empty one; delete it in phpMyAdmin if you do not use it.

## Update (when repo changes)

```bash
dpanel update-check     # installed vs latest on GitHub
sudo dpanel update      # pull, rebuild, nginx-reload, health --fix (one command)
```

Keeps `.env`, `data/`, `apps/` (sites), `logs/`, `compose.d/`. Log: `/var/log/dpanel-update.log`.

| Command | Purpose |
|---------|---------|
| `dpanel update` | Full update: sync, rebuild, health `--fix`, **one** nginx-reload at end |
| `dpanel update --check` | Version check only |
| `dpanel update --no-build` | Sync files + restart containers, skip Nuxt rebuild |
| `dpanel update-panel` | Rebuild panel UI only (local `panel/` already changed) |
| `dpanel version` | Installed version JSON |

First run on an old install (before `update.sh` existed): `dpanel update` downloads the script automatically.

```bash
dpanel status
dpanel health              # full check: docker, nginx, ports, DB, panel API
sudo dpanel health --fix   # auto-fix common issues (nginx down, etc.)
dpanel credentials
dpanel logs dpanel
```

`dpanel update` runs health then a single `nginx-reload` (no duplicate site sync / nginx -t). Skip with `--no-nginx-reload` / `--no-health-fix`.

## SSH when the panel is unavailable

Use these on the VPS as **root** or **sudo**. Stack path: `/opt/stack`. Replace `shop.example.com` with your site’s primary domain (as in `sites.json`).

### Stack and panel

```bash
dpanel status
sudo dpanel health --fix
dpanel credentials
dpanel logs dpanel 200
dpanel logs nginx 100

# Panel UI won’t load — sync repo, rebuild panel, fix nginx
sudo dpanel update
sudo dpanel update-panel          # panel source already updated, skip git pull
sudo dpanel nginx-reload            # regenerate site vhosts from sites.json + routing, reload

# Install stopped after .env was written
sudo tail -50 /var/log/dpanel-install.log
sudo bash /opt/stack/infra/scripts/install-continue.sh

# Reset panel login password (no UI)
dpanel setpass 'Your_new_password'
```

Bootstrap panel (no DNS yet): `http://<server-ip>:8443`

### List sites

```bash
cat /opt/stack/data/panel/sites.json
bash /opt/stack/infra/scripts/site-list.sh
```

### Node (Nuxt) site — rebuild, restart, logs

```bash
# Rebuild (npm install + build in site container; applies nginx routing at end)
sudo bash /opt/stack/infra/scripts/site-rebuild.sh shop.example.com
tail -f /opt/stack/logs/node/site-rebuild-shop-example-com.log

# Restart app container only (after .env change)
sudo bash /opt/stack/infra/scripts/site-app-restart.sh shop.example.com

# Live container logs
sudo bash /opt/stack/infra/scripts/site-app-logs.sh shop.example.com
```

Rebuild runs in the background when started from the panel; from SSH the script stays attached until finished (or check the log file above).

### Wildcard subdomains and custom store domains

Configured in the panel under **Websites → Manager → globe (Wildcard)**. Stored in:

`/opt/stack/data/panel/site-routing/<slug>.json`  
(`<slug>` = domain with `.` → `-`, e.g. `shop.example.com` → `shop-example-com`)

```bash
# Show routing config
cat /opt/stack/data/panel/site-routing/shop-example-com.json

# Regenerate nginx vhost (wildcard + extraDomains) and reload — use after editing JSON or MongoDB sync
sudo bash /opt/stack/infra/scripts/site-routing-apply.sh shop.example.com

# Check nginx accepts the right hostnames
grep server_name /opt/stack/infra/nginx/conf.d/shop.example.com.conf

# Test nginx config
docker exec "$(docker ps -q -f name=nginx)" nginx -t
```

| Routing type | Where it is set | SSH apply |
|--------------|-----------------|----------|
| Wildcard (`*.base.com`, `shop.base.com`) | Panel → globe → **Base domain**, or edit `wildcardBase` in `site-routing/*.json` | `site-routing-apply.sh` (or full **Rebuild**) |
| Custom merchant domains | App / MongoDB → `npm run sync:dpanel-routing` | Reconcile updates JSON; then `site-routing-apply.sh` or **Rebuild** |

Sync custom domains from inside the site container (app must define `sync:dpanel-routing` in `package.json`):

```bash
# Container name: <compose-project>-nuxt-<slug> (see: docker ps | grep nuxt)
docker exec -it dpanel-nuxt-shop-example-com sh -c 'cd /app && set -a && [ -f .env ] && . ./.env; set +a && npm run sync:dpanel-routing'
sudo bash /opt/stack/infra/scripts/site-routing-apply.sh shop.example.com
```

DNS (Cloudflare): for wildcard base `dutabi.com`, add proxied **A** records `@`, `*`, and usually `www` → VPS IP. App `.env` often needs `HUB_BASE_DOMAIN` / `ADMIN_HOST` — then **Rebuild** or restart the site container.

### Pull site code from Git (no panel)

```bash
# Optional: private repo token for this run only
export GITHUB_TOKEN=ghp_xxxx
sudo bash /opt/stack/infra/scripts/site-update.sh shop.example.com
sudo bash /opt/stack/infra/scripts/site-rebuild.sh shop.example.com
```

### Remove a site

```bash
sudo dpanel site-remove shop.example.com
# or
sudo bash /opt/stack/infra/scripts/site-delete.sh shop.example.com
```

## SSL

Use **Cloudflare** (or similar) in front of the VPS — nginx listens on HTTP only (port 80 for domains; port 8443 for direct IP panel access).

## Stack layout

```
/opt/stack/
├── compose.yml
├── .env
├── CREDENTIALS.txt
├── panel/              # panel source
├── apps/<domain>/      # each website
├── data/panel/         # auth, sites registry
└── infra/              # nginx, docker, scripts
```

Details: [AGENTS.md](./AGENTS.md) (or `agents.md` on case-sensitive systems).

## API Keys (machine auth)

Panel UI: **Settings → API Keys**.

- Create keys with **Read Only** (`GET /api/sites/check`) or **Read & Write** (check + nginx routing sync).
- Secret is shown **once** at creation — copy into each Node site `apps/<domain>/.env` as `DPANEL_API_KEY` / `DPANEL_API_SECRET`.
- Request headers: `x-dpanel-api-key`, `x-dpanel-api-secret`.
- Failed auth is limited to about **1 request/second per IP**; valid credentials are not rate-limited (verification always runs first — only repeated 401s are throttled).
- `GET /api/sites/check?domain=example.com` → `{ "available": true|false }` (exact hostname match across site domains / extraDomains / wildcard apex+www).

Legacy `DPANEL_INTERNAL_SECRET` / `x-dpanel-internal` are removed.

## Uninstall

```bash
sudo bash /opt/stack/infra/scripts/uninstall.sh
# type YES to confirm
```

## License

MIT (see repository).
