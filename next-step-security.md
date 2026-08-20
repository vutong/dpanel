# Next step — Bảo vệ file PHP & ý tưởng bổ sung

> **Trạng thái: chưa triển khai — cần suy nghĩ thêm.**  
> Tài liệu này gom **Phần 1** (chống sửa file từ website PHP) và **Phần 3** (bảng ý tưởng) từ kế hoạch bảo mật. Phần đã triển khai (Fail2ban, ClamAV, Security Hub) nằm ở [docs/security-ssh.md](docs/security-ssh.md).

---

## Bối cảnh

- PHP sites dùng **một pool php-fpm** (uid **82**), mount `./apps` read-write.
- `site_fix_permissions` chỉ chmod writable cho `storage/`, `bootstrap/cache/`, `wp-content/uploads`, `wp-content/cache`.
- Nginx PHP vhost **chưa** chặn thực thi `.php` trong uploads.

**Kết luận:** Không thể "cấm mọi thao tác tạo/sửa file từ web" mà vẫn giữ upload media + cài plugin/theme từ WP Admin (chế độ Balanced). Giải pháp đúng là **phân vùng ghi + chặn hành vi nguy hiểm + giám sát realtime**.

**Lựa chọn đã chốt (khi triển khai):**

- Áp dụng cho **mọi site PHP** (profile chung + whitelist tùy site).
- **Balanced:** WP Admin vẫn cài plugin/theme; chỉ chặn file manager / sửa code trực tiếp.

---

## Phần 1 — Chống sửa file từ website PHP

### Nguyên tắc: 3 lớp bảo vệ

1. **Lớp 1 — Ngăn:** `DISALLOW_FILE_EDIT`, nginx deny PHP in uploads, `disable_functions` (optional).
2. **Lớp 2 — Phát hiện:** inotify trên `apps/` + rule engine theo path/extension.
3. **Lớp 3 — Phản ứng:** quarantine, cảnh báo panel, ClamAV quét file mới.

### Profile per-site (`data/panel/site-security/<domain>.json`)

```json
{
  "mode": "balanced",
  "writablePaths": [
    "wp-content/uploads",
    "wp-content/cache",
    "wp-content/plugins",
    "wp-content/themes",
    "storage",
    "bootstrap/cache"
  ],
  "blockedExtensionsInUploads": [".php", ".phtml", ".phar", ".htaccess"],
  "alertOnPhpOutside": ["public", "wp-content/uploads"],
  "disallowFileEdit": true,
  "blockXmlRpc": true
}
```

### Balanced — vùng ghi

| Vùng | Ghi từ PHP? | Ghi từ dpanel FM? | Ghi chú |
|------|-------------|-------------------|---------|
| `wp-content/uploads/` | Có (media) | Có | Chỉ media/doc; **cấm `.php`** |
| `wp-content/plugins/`, `themes/` | Có (WP Admin) | Có | Quét ClamAV khi có file mới |
| `wp-content/cache/` | Có | Có | Cache plugin |
| `storage/`, `bootstrap/cache/` (Laravel) | Có | Có | Đã có trong `_helpers.sh` |
| `wp-admin/`, `wp-includes/`, `vendor/`, core | **Không** (chmod 555) | Có (FM + Fix permissions) | Chặn sửa core |
| `.env`, `wp-config.php` | **Không** | Có (cẩn thận) | Alert nếu PHP ghi |

**WordPress — chặn xmlrpc mặc định:** nginx `location = /xmlrpc.php { deny all; }` hoặc MU-plugin; giảm vector brute/spam.

### Cách chặn plugin file manager (vẫn cho WP Admin cài plugin)

1. **`DISALLOW_FILE_EDIT true`** — inject vào `wp-config.php` khi bật hardening.
2. **nginx** — deny PHP trong uploads; deny `xmlrpc.php`.
3. **Blocklist plugin** — MU-plugin cấm slug: `wp-file-manager`, `file-manager`, …
4. **`disable_functions`** (optional) — `exec`, `shell_exec`, …
5. **inotify** — phát hiện ghi ngoài whitelist.

### Script & API dự kiến (chưa code)

| Thành phần | Mục đích |
|------------|----------|
| `infra/scripts/site-harden.sh` | apply / status / relax |
| `infra/scripts/file-watch.sh` + systemd | theo dõi `/opt/stack/apps/` |
| `panel/server/api/websites/[domain]/security.*` | GET/PUT profile |
| `pages/websites/[domain]/security.vue` | UI whitelist + hardening |

### Phân biệt nguồn ghi file

| Nguồn | Cách nhận diện |
|-------|----------------|
| Website PHP | uid **82** + path `apps/<domain>/` |
| dpanel File Manager | uid container khác hoặc marker `.dpanel-write` |
| Git deploy | log trong `data/panel/site-ops/` |
| SSH / cron | uid ≠ 82 |
| Tấn công IP | Fail2ban (correlate thời gian) |

---

## Phần 3 — Bảng ý tưởng bổ sung

| Ý tưởng | Mô tả | Ưu điểm | Nhược điểm | Kết quả | Rủi ro |
|---------|-------|---------|------------|---------|--------|
| **Vùng ghi whitelist** | Chỉ vài thư mục writable; core read-only | Chặn sửa core | WP update core cần "Relax" tạm | Giảm ~80% ghi độc | Quên relax → update lỗi |
| **DISALLOW_FILE_EDIT** | WP không menu Editor | Chặn editor built-in | Không chặn FM plugin riêng | Chặn UI editor | Không đủ một mình |
| **Blocklist plugin FM** | MU-plugin cấm slug | WP Admin cài plugin khác OK | Danh sách cần cập nhật | Chặn FM phổ biến | Plugin đổi tên |
| **nginx deny PHP uploads** | Không chạy `.php` trong uploads | Chặn webshell upload | Shell ở chỗ khác vẫn OK | Rất hiệu quả WP | Cần ClamAV bổ sung |
| **disable_functions PHP** | Tắt exec, shell_exec… | Hạ webshell | Plugin backup hỏng | Giảm RCE impact | False positive |
| **inotify + rule engine** | Ghi ngoài whitelist → alert | Bắt mọi nguồn | CPU/RAM VPS nhỏ | Cảnh báo rõ path | Noise |
| **ClamAV on new file** | Quét file mới | Bắt malware known | Zero-day, CPU | Virus phổ biến | False positive hiếm |
| **Fail2ban panel login** | Ban IP sau N lần 401 | Brute panel + :8443 | Tune CF IP | Giảm brute | Ban NAT |
| **Login rate limit app** | 429 trước bcrypt | Không phụ thuộc host | Cần persistent store | Làm chậm attacker | — |
| **Quarantine tự động** | Move file nghi | Site vẫn chạy | Admin xử lý queue | Giảm thiệt hại | Quarantine nhầm |
| **Auditd uid 82** | Kernel log ghi file | Forensic chính xác | Log lớn, phức tạp | Biết process | Overhead |
| **Per-site php-fpm pool** | User Linux riêng/site | Cách ly site | Refactor lớn | Site A ≠ site B | Effort cao |
| **AppArmor php-fpm** | Giới hạn path kernel | Mạnh hơn chmod | Maintain per framework | Chặn escape | Profile sai → down |
| **Cloudflare WAF** | Rate limit login | Không sửa code | 8443 bypass | Bảo panel domain | Origin lộ |
| **Immutable deploy (Git)** | Code read-only runtime | Workflow sạch | Không cài từ WP Admin | Bảo mật cao | Trái Balanced |
| **CSRF token panel** | Bảo session admin | Chống hijack FM | Không bảo WP | Giảm abuse session | Effort UI |

---

## Rủi ro cần cân nhắc trước khi code

1. **Balanced + WP Admin** — vẫn ghi PHP vào `plugins/`; bảo vệ = quét + giám sát.
2. **Panel mount rw toàn stack** — session lộ → FM sửa mọi site.
3. **VPS 1GB RAM** — inotify + ClamAV on-access nặng; nên nightly scan trước.

---

## Lộ trình đề xuất (khi reopen)

1. nginx deny PHP uploads + `DISALLOW_FILE_EDIT` + chặn xmlrpc.
2. `file-watch.sh` + security events (bổ sung nguồn `website_php`).
3. Per-site security profile + UI.
4. Blocklist MU-plugin, quarantine workflow.
