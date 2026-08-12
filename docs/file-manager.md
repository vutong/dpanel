# File Manager

Per-site file browser for `apps/<domain>/`. **V1 shipped** (session only).

Entry: **Websites → Manager → Files** → `/websites/:domain/files`  
Not a sidebar item. No API keys.

---

## Đã làm (V1)

Phạm vi: browse một cấp + upload/download + mkdir/rename/delete + preview text/ảnh.  
Không editor, zip, chmod, search.

### Backend

- [x] `panel/server/utils/site-files.ts` — `resolveJailPath` (realpath + chặn symlink thoát jail; cấm tạo symlink; cấm xóa/rename root `apps/<domain>/`).
- [x] API session-only:
  - `GET /api/websites/:domain/files?path=` — list 1 cấp (cap 2000), `disk{ usedBytes, limitBytes, freeHostBytes }`
  - `POST .../files/mkdir`
  - `POST .../files/rename` (API nhận full `to` path → move trong jail; UI chỉ rename cùng thư mục)
  - `POST .../files/delete` (bulk ≤ 50)
  - `GET .../files/download` — stream attachment
  - `GET .../files/preview` — text ≤ 256 KB hoặc image ≤ 10 MB
  - `POST .../files/upload` — multipart, dest dir + basename only, **64 MB/file**
- [x] Upload 64 MB: nginx `client_max_body_size 64m` + handler 413. Nitro `bodySizeLimit` 65 MB (Nitro không có limit per-route; API khác là JSON nhỏ).
- [x] Pending delete: list/preview/download OK; mutation → 409.
- [x] Soft quota: từ chối upload nếu vượt `diskGb` (khi > 0) hoặc host gần đầy (`df` + reserve 100 MB).
- [x] Owner: inherit từ thư mục cha. Fallback PHP uid 82 / Node uid hiện tại. Replace `.env` → mode `0o600`.
- [x] Panel domain: browse được; cấm xóa `.output/` và `node_modules/` của panel.

### UI

- [x] `pages/websites/[domain]/index.vue` + `[domain]/files.vue`.
- [x] Tile **Files** (PHP + Node), gỡ khỏi Coming soon.
- [x] Breadcrumb clickable, bảng name/size/mtime, toolbar Upload / New folder / Refresh, drag-drop, preview modal (không Save).
- [x] Confirm delete (dir / sensitive: gõ tên hoặc `DELETE`). Sensitive warning, không hard-block (trừ panel `.output`).
- [x] Icons: `upload`, `download`, `file`, `folder-plus`, `refresh`.
- [x] Banner: Git (khi site có GitHub); Node Rebuild hint; PHP thiếu `public/`; site-ops đang chạy; panel domain; list truncated.

Copy UI: English.

### Kiểm tra (khi deploy VPS)

- Jail: `../`, `..\\`, `%2e%2e`, symlink ra `/opt/stack/.env` và `/etc` → 403.
- Upload 1 byte / ~64 MB / >64 MB → 413; filename `../../x`.
- PHP: file FM tạo ra php-fpm ghi được (owner inherit).
- Pending delete: upload/delete 409; download 200.
- Preview: `.env` hiện text; binary không render như text; không `v-html`.
- Route: `/websites/:domain` manager không vỡ; `/files` load.

---

## Nền tảng sẵn có (không phải FM)

- Panel mount cả stack (`.:/opt/stack`).
- `.env` editor Node (`site-env.ts`) — tile Environment vẫn **chỉ Node**.
- `getAppDirSizeBytes` / `diskGb` (Docker `storage_opt` không chặn bind-mount `apps/`).
- Nginx 64m; PHP root luôn `public/`.

---

## Chưa làm (cố ý / sau V1)

### Cố ý không làm trong V1

- Code editor (textarea save / Monaco) — download hoặc upload đè.
- Zip / unzip (zip bomb).
- Chmod / chown UI.
- Search, dual-pane, virtual scroll, trash 24h, recursive download folder.
- Share public link, SFTP/FTP.
- API keys cho files.
- Browse ngoài `apps/<domain>/`.
- Auto-symlink `public → .` khi WP không có `public/`.
- CSRF token riêng cho FM.
- Chunked / resumable upload; lock chống race 2 upload.
- Mở tile Environment cho PHP.

### Phase 2+

- Textarea save + conflict mtime.
- Zip selected / extract.
- Trash 24h.
- API key read/write files — chỉ khi có use-case thật.
- Chmod UI sau khi permission model ổn.

### Nợ / rủi ro chấp nhận ở V1

- `diskGb` + `df` không atomic — 2 upload song song vẫn có thể đầy disk.
- Git pull sau upload FM = mất file (chỉ warn).
- Không trash — xóa là mất.
- List `node_modules` có thể chậm (cap 2000 + truncated).
- Nitro body limit là global 65 MB (không per-route).
- Panel không có CSRF token / login rate limit — không phải bug FM.

---

## Quyết định kiến trúc (không đổi trừ khi reopen)

| Cách | Kết luận |
|------|----------|
| Bash `file-*.sh` | Không — binary/stream/path injection. |
| FileBrowser sidecar | Không — auth/UI lệch, thêm service. |
| Node `fs` + jail trong panel | **Có** — giống `.env`; UI không gửi shell. |

Jail: mọi API qua `resolveJailPath(domain, relativePath)`. Input POSIX relative; không follow symlink ra ngoài `realpath(apps/<domain>)`.
