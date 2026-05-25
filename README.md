# dpanel

Docker hosting control panel for **Ubuntu 24.04 LTS**: manage websites (Node/PHP) and MariaDB via a Nuxt web UI.

## Requirements

- Ubuntu 24.04 LTS (22.04 may work; not fully tested)
- Root or sudo
- 2 GB+ RAM recommended
- 10 GB+ free disk
- Ports **80** and **8080** available

## Install

```bash
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
sudo bash install.sh
```

You will be prompted for:

1. Panel domain (e.g. `panel.yourdomain.com`)
2. Login email
3. Password (min 8 characters)

Install takes about **15–30 minutes** on a fresh VPS (Docker + Nuxt build). Progress is written to `/var/log/dpanel-install.log`.

### Non-interactive install

```bash
export DPANEL_NONINTERACTIVE=1
export PANEL_DOMAIN=panel.example.com
export ADMIN_EMAIL=admin@example.com
export ADMIN_PASSWORD='your-secure-password'
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
sudo -E bash install.sh
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
- CLI: `dpanel status`, `dpanel health`, `dpanel update-panel`

```bash
dpanel status          # service status
dpanel health          # API health check
dpanel update-panel    # rebuild UI after git pull
dpanel credentials     # show CREDENTIALS.txt
dpanel logs dpanel     # follow panel logs
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
