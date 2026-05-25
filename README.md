# ubuntu-docker

Bootstrap Docker stack trên **Ubuntu 24.04 LTS**: nginx, Nuxt (Node SSR), PHP-FPM, MariaDB, Redis.

Domain trong repo (`*.example.com`) **chỉ là ví dụ**. Thay bằng domain thật khi triển khai.

## Quick start

```bash
# Tùy chọn: domain thật
export APP_DOMAIN=app.yourdomain.com
export BLOG_DOMAIN=blog.yourdomain.com
export ADMIN_DOMAIN=admin.yourdomain.com

chmod +x setup-vps.sh
sudo ./setup-vps.sh
```

SSL do **Cloudflare** xử lý — VPS chỉ cần HTTP port 80.

Chi tiết kiến trúc và quy ước vận hành: [agents.md](./agents.md).
