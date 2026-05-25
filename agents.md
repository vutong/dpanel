# ubuntu-docker — Kiến trúc & vận hành

Dự án bootstrap Docker stack trên Ubuntu 24.04 LTS. Tài liệu tham chiếu cho agent và người vận hành khi triển khai, cấu hình hoặc debug.

> **Lưu ý:** Mọi domain trong tài liệu này (`app.example.com`, `blog.example.com`, …) **chỉ là ví dụ minh họa cấu trúc**. Khi triển khai thật, thay bằng domain của bạn trong `.env`, nginx `conf.d/` và tên thư mục tương ứng dưới `apps/` / `data/uploads/`.

## Kiến trúc

```
Ubuntu 24.04 LTS
└── Docker Engine
    └── docker-compose stack
        ├── nginx (reverse proxy)
        ├── nuxt (node runtime SSR)
        ├── php-fpm (backend PHP)
        ├── mariadb (database)
        └── redis (cache/queue)
```

**SSL:** Không cấu hình SSL trên VPS. Cloudflare xử lý HTTPS phía trước (Flexible hoặc Full). Nginx chỉ lắng nghe HTTP / port 80.

## Cấu trúc thư mục

Tên thư mục app/upload theo **domain thật** của bạn. Ví dụ dưới đây dùng placeholder `*.example.com`:

```
/opt/stack
├── compose.yml
├── .env
│
├── infra/
│   ├── nginx/
│   │   ├── conf.d/
│   │   ├── templates/
│   │   └── nginx.conf
│   │
│   ├── docker/
│   │   ├── node/                 (Nuxt SSR + Node workers)
│   │   │   ├── Dockerfile
│   │   │   └── runtime/
│   │   │
│   │   ├── php/                  (Laravel / WordPress)
│   │   │   ├── Dockerfile
│   │   │   └── config/
│   │   │
│   │   └── base/
│   │       ├── node/
│   │       └── php/
│   │
│   └── scripts/
│       ├── deploy.sh
│       ├── backup.sh
│       ├── migrate.sh
│       └── cleanup.sh
│
├── apps/
│   ├── app.example.com/          (Nuxt SSR — ví dụ)
│   ├── blog.example.com/         (PHP — ví dụ)
│   └── admin.example.com/        (Admin — ví dụ)
│
├── data/
│   ├── mariadb/
│   │   ├── volume/
│   │   └── backup/
│   │
│   ├── redis/
│   │   ├── dump/
│   │   └── persistence/
│   │
│   └── uploads/
│       ├── app.example.com/      (app tự quy tắc)
│       ├── blog.example.com/
│       └── admin.example.com/
│
└── logs/
    ├── nginx/
    │   ├── access.log
    │   └── error.log
    ├── node/
    ├── php/
    ├── mariadb/
    └── redis/
```

## Ứng dụng & domain (ví dụ)

| Domain (ví dụ) | Runtime | Ghi chú |
|----------------|---------|---------|
| `app.example.com` | Nuxt SSR (Node) | Frontend chính |
| `blog.example.com` | PHP (Laravel / WordPress) | Blog / CMS |
| `admin.example.com` | Node hoặc PHP | Backend quản trị |

Thay `example.com` bằng domain thật. Có thể thêm/bớt site — mỗi site = một `server {}` trong nginx + thư mục trong `apps/` và `data/uploads/`.

## Dịch vụ Docker

| Service | Vai trò |
|---------|---------|
| **nginx** | Reverse proxy, route theo `Host`, phục vụ static/upload |
| **nuxt** | SSR Nuxt, Node workers |
| **php-fpm** | Laravel / WordPress |
| **mariadb** | Database chính |
| **redis** | Cache, session, queue |

## Cloudflare

- DNS trỏ A/AAAA về IP VPS.
- SSL/TLS mode: **Flexible** hoặc **Full** (nếu sau này bật cert nội bộ).
- Bật proxy (orange cloud) cho subdomain public.
- Nginx đã cấu hình tin `CF-Connecting-IP` cho log IP thật.

## Bootstrap VPS mới

```bash
# Domain tùy chỉnh (tùy chọn, trước khi chạy script)
export APP_DOMAIN=app.yourdomain.com
export BLOG_DOMAIN=blog.yourdomain.com
export ADMIN_DOMAIN=admin.yourdomain.com

chmod +x setup-vps.sh && sudo ./setup-vps.sh
```

Script sẽ:

1. Cập nhật Ubuntu 24.04, cài Docker Engine + Compose plugin.
2. Tạo cây thư mục `/opt/stack`.
3. Sinh `compose.yml`, `.env`, nginx, Dockerfile, script vận hành.
4. Không cài certbot / Let's Encrypt.

## Sau bootstrap

1. Chỉnh `.env` (mật khẩu DB, domain thật).
2. Cập nhật `server_name` trong `infra/nginx/conf.d/` nếu đổi domain sau bootstrap.
3. Deploy mã nguồn vào `apps/<domain-của-bạn>/`.
4. `cd /opt/stack && docker compose up -d --build`.
5. Trỏ DNS Cloudflare về VPS.

## Script vận hành

| Script | Mục đích |
|--------|----------|
| `infra/scripts/deploy.sh` | Pull/build/restart stack |
| `infra/scripts/backup.sh` | Backup MariaDB + uploads |
| `infra/scripts/migrate.sh` | Chạy migration (Laravel/Node tùy app) |
| `infra/scripts/cleanup.sh` | Dọn image/volume/log cũ |

## Quy ước cho agent

- Domain trong repo **luôn là placeholder** trừ khi user cung cấp domain thật.
- Mọi thay đổi infra nằm trong `/opt/stack/infra/`.
- Upload persistent: `data/uploads/<domain>/` — mỗi app tự quy tắc thư mục con.
- Log ghi ra `logs/<service>/`.
- Không thêm SSL local trừ khi user yêu cầu; ưu tiên Cloudflare.
- Biến nhạy cảm chỉ trong `.env`, không commit.
