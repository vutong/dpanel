# dpanel

Docker hosting control panel for **Ubuntu 24.04 LTS**: manage websites (Node/PHP) and MariaDB via a Nuxt web UI.

## Requirements

- Ubuntu 24.04 LTS (22.04 may work; not fully tested)
- Root or sudo
- 2 GB+ RAM recommended
- 10 GB+ free disk
- Ports **80** and **8080** available

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

### Non-interactive install

```bash
export DPANEL_NONINTERACTIVE=1
export PANEL_DOMAIN=panel.example.com
export ADMIN_EMAIL=admin@example.com
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
sudo -E bash install.sh
```

Default login password is **1234567**. Change after install:

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

- Panel: `http://<panel-domain>` or `http://<server-ip>:8080`
- Summary file: `/opt/stack/CREDENTIALS.txt`
- Default password: `1234567` → `dpanel setpass 'new-password'`

## Update (when repo changes)

```bash
dpanel update-check     # installed vs latest on GitHub
sudo dpanel update      # pull main, sync stack, rebuild panel & Docker
```

Keeps `.env`, `data/`, `apps/` (sites), `logs/`, `compose.d/`. Log: `/var/log/dpanel-update.log`.

| Command | Purpose |
|---------|---------|
| `dpanel update` | Full update from `DPANEL_REPO` / `DPANEL_BRANCH` (in `.env`) |
| `dpanel update --check` | Version check only |
| `dpanel update --no-build` | Sync files + restart containers, skip Nuxt rebuild |
| `dpanel update-panel` | Rebuild panel UI only (local `panel/` already changed) |
| `dpanel version` | Installed version JSON |

First run on an old install (before `update.sh` existed): `dpanel update` downloads the script automatically.

```bash
dpanel status
dpanel health
dpanel credentials
dpanel logs dpanel
```

## SSL

Use **Cloudflare** (or similar) in front of the VPS — nginx listens on HTTP only (ports 80 / 8080).

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

## Uninstall

```bash
sudo bash /opt/stack/infra/scripts/uninstall.sh
# type YES to confirm
```

## License

MIT (see repository).
