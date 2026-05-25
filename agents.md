# dpanel — Kiến trúc & vận hành

Bootstrap Docker stack trên Ubuntu 24.04 LTS + **control panel Nuxt** (`panel/`).

> Domain trong tài liệu (`*.example.com`) **chỉ là ví dụ**. Khi triển khai thật, dùng domain của bạn trong panel hoặc `.env`.

## Kiến trúc

```
Ubuntu 24.04 LTS
└── Docker Engine
    └── docker-compose stack (/opt/stack)
        ├── nginx (reverse proxy + phpMyAdmin /mariadb/)
        ├── dpanel (Nuxt SSR — control panel)
        ├── php-fpm (các site PHP)
        ├── nuxt-<slug> (mỗi site Node — compose.d/)
        ├── mariadb
        ├── phpmyadmin
        └── redis
```

**SSL:** Cloudflare phía trước. Nginx chỉ HTTP :80 và :8080 (panel khi chưa có DNS).

## Bootstrap

```bash
curl -fsSLO https://raw.githubusercontent.com/vutong/dpanel/main/install.sh
sudo bash install.sh
```

Installer (`install.sh` v1.0.0):

1. Preflight (Ubuntu 24.04, RAM, disk, ports)  
2. Panel domain + email + password (or `DPANEL_NONINTERACTIVE=1`)  
3. Wait for apt lock; skip `dist-upgrade` by default (`DPANEL_FULL_UPGRADE=1` to enable)  
4. Clone repo → `/opt/stack`, build panel, `docker compose up`  
5. Health check, write `/opt/stack/CREDENTIALS.txt`, symlink `dpanel` CLI  

**CLI:** `dpanel status | health | update-panel | credentials | logs`

## Cấu trúc thư mục

### Repo GitHub (`dpanel/` — phát triển)

```
dpanel/
├── install.sh                 # Entry point cài VPS (hỏi domain, email, mật khẩu)
├── compose.yml                # Docker stack chính
├── README.md
├── AGENTS.md
├── .gitignore
│
├── panel/                     # Mã nguồn control panel (Nuxt 3)
│   ├── package.json
│   ├── nuxt.config.ts
│   ├── app.vue
│   ├── assets/css/
│   ├── layouts/
│   ├── pages/
│   │   ├── index.vue
│   │   ├── login.vue
│   │   ├── websites/
│   │   │   ├── index.vue
│   │   │   └── create.vue
│   │   └── databases/
│   │       ├── index.vue
│   │       ├── create.vue
│   │       └── phpmyadmin.vue
│   ├── middleware/
│   ├── server/
│   │   ├── api/               # auth, websites, databases, phpmyadmin
│   │   └── utils/
│   └── node_modules/          # (local dev, không commit)
│
└── infra/
    ├── nginx/
    │   ├── nginx.conf
    │   └── conf.d/
    │       ├── .gitkeep
    │       ├── 00-panel.conf      # sinh lại bởi nginx-reload.sh
    │       └── 00-panel.conf (/mariadb/ → phpMyAdmin)
    ├── docker/
    │   ├── node/
    │   │   ├── Dockerfile
    │   │   └── runtime/entrypoint.sh
    │   └── php/
    │       ├── Dockerfile
    │       └── config/99-custom.ini
    └── scripts/
        ├── site-create.sh
        ├── site-list.sh
        ├── db-list.sh
        ├── db-create.sh
        ├── db-delete.sh
        ├── nginx-reload.sh
        ├── deploy.sh
        ├── backup.sh
        └── cleanup.sh
```

### Trên VPS sau `install.sh` (`/opt/stack/`)

```
/opt/stack/
├── install.sh                 # Bản copy từ repo
├── compose.yml
├── compose.d/                 # Mỗi site Node → 1 file (tự sinh)
│   └── nuxt-<slug>.yml        # vd: nuxt-app-example-com.yml
├── .env                       # Mật khẩu DB, Redis, PANEL_DOMAIN, …
│
├── panel/                     # Mã nguồn panel (để build lại)
│   ├── package.json
│   ├── nuxt.config.ts
│   ├── pages/ …
│   └── server/ …
│
├── apps/                      # Mọi website — upload nằm TRONG từng project
│   │
│   ├── panel.example.com/     # Control panel (build Nuxt)
│   │   ├── package.json
│   │   ├── node_modules/
│   │   └── .output/
│   │       └── server/index.mjs
│   │
│   ├── blog.example.com/      # Ví dụ PHP — WordPress
│   │   ├── .gitkeep           # (nếu chưa clone GitHub)
│   │   ├── public/            # hoặc root WP tùy cấu trúc repo
│   │   ├── wp-content/
│   │   │   └── uploads/       # WordPress tự quản upload
│   │   └── …
│   │
│   ├── shop.example.com/      # Ví dụ PHP — Laravel
│   │   ├── public/            # nginx document root
│   │   │   └── index.php
│   │   ├── storage/
│   │   │   └── app/public/    # upload / media Laravel
│   │   └── …
│   │
│   └── app.example.com/       # Ví dụ Node — Nuxt site
│       ├── package.json
│       ├── public/              # static / file tùy app
│       ├── .output/
│       └── …
│
├── data/
│   ├── panel/
│   │   ├── auth.json          # email + password hash (install.sh)
│   │   └── sites.json         # danh sách site từ panel
│   ├── mariadb/
│   │   └── volume/            # dữ liệu MySQL persistent
│   └── redis/
│       ├── persistence/
│       └── dump/
│
├── infra/                     # Giống repo (nginx, docker, scripts)
│   ├── nginx/
│   │   ├── nginx.conf
│   │   └── conf.d/
│   │       ├── 00-panel.conf
│   │       ├── 00-panel.conf
│   │       ├── blog.example.com.conf
│   │       └── app.example.com.conf
│   ├── docker/
│   │   ├── node/
│   │   └── php/
│   └── scripts/
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

### Quy ước đặt tên

| Thành phần | Quy tắc |
|------------|---------|
| Thư mục site | `apps/<domain>/` — domain thật, vd `shop.mydomain.com` |
| Nginx vhost | `infra/nginx/conf.d/<domain>.conf` |
| Site Node (Docker) | `compose.d/nuxt-<slug>.yml`, `<slug>` = domain đổi `.` → `-` |
| Upload | **Không** có `data/uploads/` — mỗi framework tự quản trong `apps/<domain>/` |
| Panel | Luôn 1 domain riêng → `apps/<PANEL_DOMAIN>/` |

## Quy ước cho agent

- Tên dự án: **dpanel** (không còn ubuntu-docker).
- Entry point duy nhất cho VPS: `install.sh`.
- Panel API gọi script trong `infra/scripts/` — không shell tùy ý từ UI.
- Site PHP: nginx → php-fpm, root `apps/<domain>/public`.
- Site Node: service `nuxt-<slug>` trong `compose.d/`.
- **Upload:** không có `data/uploads/` — mỗi site tự quản trong `apps/<domain>/` (WordPress: `wp-content/uploads`, Laravel: `storage/app/public`, Nuxt: `public/` hoặc tùy app).
- Mật khẩu nhạy cảm chỉ trong `.env` và `data/panel/auth.json`.
- **Backup:** chưa triển khai — không tạo `data/mariadb/backup/`; `infra/scripts/backup.sh` là placeholder.
- Không SSL local trừ khi user yêu cầu.
