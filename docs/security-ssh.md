# VPS Security Hub — Fail2ban & ClamAV

dpanel quản lý bảo vệ VPS ở tầng **host Ubuntu** (ngoài Docker stack): cài/giám sát **Fail2ban** và **ClamAV**, ghi nhận sự kiện bảo mật, rate limit login panel.

> Bảo vệ file PHP / hardening website: xem [next-step-security.md](../next-step-security.md) (chưa triển khai).

---

## Kiến trúc

```
Ubuntu 24.04 (host)
├── fail2ban          ← jails: sshd, nginx-dpanel-login, nginx-php-exploit
├── clamav-daemon     ← quét malware (manual / scheduled)
├── freshclam         ← cập nhật signature
└── /opt/stack/
    ├── logs/nginx/access.log   ← fail2ban đọc login 401
    ├── infra/security/fail2ban/  ← config mẫu (sync khi Install)
    └── data/panel/security-events.json

Docker: dpanel container
└── API /api/security/* → bash scripts → chroot host (giống vps-reboot.sh)
```

Panel **không** chạy Fail2ban/ClamAV trong container — gọi host qua `docker run --privileged chroot /host`.

---

## Cài đặt

### Lúc cài VPS (`install.sh`)

**VPS mới** (tạo `.env` lần đầu): tự động cài **cả Fail2ban và ClamAV** sau health check.

```bash
# Ép cài lại trên reinstall có .env sẵn:
DPANEL_INSTALL_SECURITY=1 sudo bash install.sh
```

Gọi `host-fail2ban-install.sh` + `host-clamav-install.sh` (wrapper `host-security-install.sh`).

### Từ panel (update / cài thiếu)

- **Fail2ban** → nút **Install Fail2ban** (chỉ khi chưa cài)
- **ClamAV** → nút **Install ClamAV** (chỉ khi chưa cài)

---

## Fail2ban

### Jails

| Jail | Log | Mục đích |
|------|-----|----------|
| `sshd` | `/var/log/auth.log` | Brute SSH |
| `nginx-dpanel-login` | `/opt/stack/logs/nginx/access.log` | `POST /api/auth/login` → 401 |
| `nginx-php-exploit` | cùng access.log | Bot quét `.env`, `.git`, … |

Config: [`infra/security/fail2ban/`](../infra/security/fail2ban/)

### Panel UI

- Route: `/settings/fail2ban` — tabs: **Overview**, **Jails & Settings**, **Banned IPs**, **Logs**, **Guide**
- Overview: service status, reload, recent Fail2ban events, unban my IP
- Jails & Settings: edit `enabled`, `maxretry`, `findtime`, `bantime` for all jails (including `sshd`); per-jail **incremental bantime** for `sshd` and `nginx-dpanel-login` (stepped ladder via native Fail2ban DB; `nginx-php-exploit` uses fixed bantime only); global `ignoreip` whitelist
- Banned IPs: searchable table with jail names, country (offline MaxMind GeoLite2), and unban
- Country DB: click **Sync** in the Banned IPs table header → downloads `GeoLite2-Country.mmdb` to `data/panel/geoip/`; sync state in `maxmind.json` (set `GEOIP_MAXMIND_LICENSE_KEY` in `/opt/stack/.env`; IP lookups cached in `lookup-cache.json`)
- Logs: tail `/var/log/fail2ban.log` with line count and filter
- Guide: in-panel help (jails, Cloudflare, whitelist, rate limit vs Fail2ban, CLI)
- **Unban** IP (gọi `host-fail2ban-unban.sh`)

Settings persist in `data/panel/fail2ban-settings.json`; panel regenerates `/etc/fail2ban/jail.d/dpanel*.conf` on save.

**Incremental bantime (native Fail2ban):** when enabled for a jail, Fail2ban uses `bantime.increment = true` with multipliers `1 6 24 72 168 720 4320` × base `bantime` (cap `bantime.maxtime = bantime × 4320`). Example with base 3600s: 1h → 6h → 24h → 72h → 7d → 30d → 180d. Repeat offenders stay on the ladder until ban history expires in Fail2ban’s DB — **not** reset after one successful login. Default **on** for `sshd` and `nginx-dpanel-login`; **off** (fixed bantime) for `nginx-php-exploit`.

**Performance:** host queries use `host-fail2ban-query.sh` — **one chroot session** per API call (not one Docker run per `fail2ban-client` command). Overview loads via `GET /api/security/fail2ban` (`summary` mode); tab **Jails** and **Banned IPs** fetch lazily when opened. No server-side TTL cache — data is always live from the host.

### Login rate limit (app layer)

Bổ sung trong panel (`POST /api/auth/login`):

- Tối đa **5 lần sai / 15 phút / IP** → HTTP 429
- Lưu persistent: `data/panel/login-attempts.json`
- Fail2ban là lớp host; rate limit là lớp app — dùng **cả hai**

---

## ClamAV

### Tính năng (panel)

- Cài daemon + freshclam (background install + poll)
- **Start services** khi daemon/freshclam inactive
- **Scan background** — toàn bộ `apps/` hoặc từng site; một scan tại một thời điểm (global lock)
- Lịch sử quét lưu tại `data/panel/clamav-scans/` (index + `by-domain/`)
- Kết quả infected → event `malware_found` + hiển thị path/domain
- Scan từ **Websites → [domain] → Scan Virus**

Chưa có: clamonacc on-access, quarantine tự động (xem next-step-security.md).

### Panel UI

- Route: `/settings/clamav` — tabs: **Overview**, **Scan**, **Results**, **Logs**, **Guide**
- Overview: trạng thái daemon/freshclam, cài/update/start, recent malware events
- Scan: quét all apps hoặc chọn site; hiển thị lock khi scan đang chạy
- Results: lịch sử + chi tiết file infected
- Logs: tail clamav / freshclam / clamd / latest panel scan log
- Guide: hướng dẫn in-panel + CLI
- **Websites → [domain] → Security → Scan Virus** — modal pre-check ClamAV, badge last scan

**Performance:** host queries use `host-clamav-query.sh` — **one chroot session** per API call. Overview loads via `GET /api/security/clamav` (`summary`); tab **Results** / **Logs** / **Scan** mount lazily; scan history via `GET /api/security/clamav/scans`. No server-side TTL cache.

### Background scan UX

- POST scan trả về ngay (`scanId`); **không** báo success trước khi job xong
- UI poll `/api/security/clamav/scans?id=` hoặc `?active=1` mỗi ~4s
- Alert success/error chỉ khi scan hoàn tất (composable `useClamavScan`)

---

## Security events

Lưu tại `data/panel/security-events.json` (tối đa ~500 bản ghi).

| Field | Ý nghĩa |
|-------|---------|
| `kind` | `fail2ban_ban`, `login_brute`, `malware_found`, … |
| `source` | `fail2ban`, `panel_login`, `clamav`, `unknown` |
| `domain` | Site liên quan (nếu path trong `apps/<domain>/`) |
| `ip` | IP attacker (Fail2ban / login) |
| `path` | File bị phát hiện |
| `action` | `banned_ip`, `alert_only`, `scan_infected` |

Route: `/security/events` — bảng sự kiện gần nhất.

Dashboard hiển thị widget Security (5 event + trạng thái Fail2ban/ClamAV).

---

## API (session auth)

| Method | Path | Mô tả |
|--------|------|-------|
| GET | `/api/security/status` | Tổng quan Fail2ban + ClamAV |
| POST | `/api/security/fail2ban/install` | Cài Fail2ban |
| POST | `/api/security/clamav/install` | Cài ClamAV |
| GET | `/api/security/events` | Danh sách events (`?source=fail2ban` filter) |
| GET | `/api/security/fail2ban` | Overview nhanh (installed, counts, settings) |
| GET | `/api/security/fail2ban/jails` | Jails + runtime config (tab Jails & Settings) |
| GET | `/api/security/fail2ban/banned` | Banned IPs + GeoIP (tab Banned IPs) |
| PUT | `/api/security/fail2ban/settings` | Lưu settings; `{ resetJail: "sshd" }` reset một jail |
| GET | `/api/security/fail2ban/logs` | Tail log (`?lines=200&grep=`) |
| POST | `/api/security/fail2ban/reload` | Reload fail2ban |
| POST | `/api/security/fail2ban/unban` | `{ "ip": "…", "jail?": "…" }` |
| GET | `/api/security/clamav` | Overview nhanh (installed, services, activeScan) |
| GET | `/api/security/clamav/detail` | Version, binary paths, log paths |
| POST | `/api/security/clamav/start` | Start clamav-daemon + freshclam |
| GET | `/api/security/clamav/logs` | Tail log (`?lines=200&grep=&source=clamav\|freshclam\|clamd\|scan`) |
| GET | `/api/security/clamav/scans` | Lịch sử (`?limit=&domain=&active=1&id=`) |
| POST | `/api/security/clamav/update` | freshclam |
| POST | `/api/security/clamav/scan` | `{ "domain?", "background?" }` — mặc định background |
| GET | `/api/websites/[domain]/clamav-scan` | Last scan + active scan cho site |
| POST | `/api/websites/[domain]/clamav-scan` | Bắt đầu scan site (background) |

---

## Scripts

| Script | Vai trò |
|--------|---------|
| `host-chroot.sh` | Helper chroot host từ container |
| `host-security-status.sh` | JSON status |
| `host-fail2ban-query.sh` | Một lần chroot/mode: `summary` \| `jails` \| `banned` |
| `host-fail2ban-query.py` | Logic query (gọi từ `.sh` trên host) |
| `host-fail2ban-detail.sh` | Deprecated — gọi `host-fail2ban-query.sh jails` |
| `host-fail2ban-logs.sh` | Tail fail2ban.log |
| `host-fail2ban-config-apply.sh` | Ghi config từ `fail2ban-settings.json` + reload |
| `host-fail2ban-reload.sh` | Reload service |
| `host-security-install.sh` | apt + sync config + enable services |
| `host-fail2ban-unban.sh` | Unban IP |
| `host-clamav-query.sh` | Một lần chroot/mode: `summary` \| `detail` |
| `host-clamav-query.py` | Logic query (gọi từ `.sh` trên host) |
| `host-clamav-detail.sh` | Deprecated — gọi `host-clamav-query.sh detail` |
| `host-clamav-start.sh` | Start/restart daemon + freshclam |
| `host-clamav-logs.sh` | Tail log ClamAV |
| `host-clamav-scan-bg.sh` | Scan background → ghi `data/panel/clamav-scans/` |
| `host-clamav-update.sh` | freshclam |
| `host-clamav-scan.sh` | Quét path (foreground), JSON kết quả |

---

## Vận hành & rủi ro

1. **Ban nhầm SSH** — luôn test jail trước; giữ session SSH mở khi bật Fail2ban lần đầu.
2. **Cloudflare** — `real_ip` đã cấu hình nginx; Fail2ban thấy IP client qua access log.
3. **Port 8443** — panel qua IP; jail `nginx-dpanel-login` áp dụng cùng log.
4. **RAM thấp** — ClamAV scan full `apps/` tốn CPU/RAM; scan từng site khi VPS nhỏ.
5. **freshclam** — lần đầu tải DB có thể mất vài phút.

---

## CLI (host)

```bash
sudo bash /opt/stack/infra/scripts/host-security-status.sh
sudo bash /opt/stack/infra/scripts/host-security-install.sh
sudo bash /opt/stack/infra/scripts/host-fail2ban-unban.sh 1.2.3.4
sudo bash /opt/stack/infra/scripts/host-clamav-scan.sh apps/example.com
```
