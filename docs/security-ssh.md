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

Bước optional **Security packages** (prompt mặc định):

```bash
# Non-interactive: cài luôn
DPANEL_INSTALL_SECURITY=1 sudo bash install.sh
```

Gọi `infra/scripts/host-security-install.sh` trên host.

### Từ panel

**Settings → Fail2ban** hoặc **ClamAV** → nút **Install security packages** nếu chưa có.

Script cài: `fail2ban`, `clamav`, `clamav-daemon`, `clamav-freshclam`, sync jail/filter từ repo, `systemctl enable --now`.

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

- Route: `/settings/fail2ban`
- Trạng thái service, danh sách jail, IP đang ban
- **Unban** IP (gọi `host-fail2ban-unban.sh`)

### Login rate limit (app layer)

Bổ sung trong panel (`POST /api/auth/login`):

- Tối đa **5 lần sai / 15 phút / IP** → HTTP 429
- Lưu persistent: `data/panel/login-attempts.json`
- Fail2ban là lớp host; rate limit là lớp app — dùng **cả hai**

---

## ClamAV

### Phase hiện tại (V1)

- Cài daemon + freshclam
- **Scan now** từ panel: toàn bộ `apps/` hoặc một site (`apps/<domain>/`)
- Kết quả infected → event `malware_found` + hiển thị path/domain

Chưa có: clamonacc on-access, quarantine tự động (xem next-step-security.md).

### Panel UI

- Route: `/settings/clamav`
- Trạng thái daemon, ngày signature, nút **Update signatures** (freshclam), **Scan all apps**

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

Overview hiển thị widget Security (5 event + trạng thái Fail2ban/ClamAV).

---

## API (session auth)

| Method | Path | Mô tả |
|--------|------|-------|
| GET | `/api/security/status` | Tổng quan Fail2ban + ClamAV |
| POST | `/api/security/install` | Cài packages trên host |
| GET | `/api/security/events` | Danh sách events |
| GET | `/api/security/fail2ban` | Chi tiết jails + banned IPs |
| POST | `/api/security/fail2ban/unban` | `{ "ip": "…" }` |
| GET | `/api/security/clamav` | Trạng thái ClamAV |
| POST | `/api/security/clamav/update` | freshclam |
| POST | `/api/security/clamav/scan` | `{ "domain?" }` — quét apps hoặc một site |

---

## Scripts

| Script | Vai trò |
|--------|---------|
| `host-chroot.sh` | Helper chroot host từ container |
| `host-security-status.sh` | JSON status |
| `host-security-install.sh` | apt + sync config + enable services |
| `host-fail2ban-unban.sh` | Unban IP |
| `host-clamav-update.sh` | freshclam |
| `host-clamav-scan.sh` | Quét path, JSON kết quả |

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
