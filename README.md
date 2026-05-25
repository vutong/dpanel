# dpanel

Bootstrap **Ubuntu 24.04 LTS** + Docker stack + **control panel Nuxt** — quản lý website và MariaDB qua giao diện web.

## Cài đặt (một lệnh)

Trên VPS mới (SSH):

```bash
curl -fsSL https://raw.githubusercontent.com/vutong/dpanel/main/install.sh | sudo bash
```

Hoặc clone repo rồi chạy:

```bash
git clone https://github.com/vutong/dpanel.git
cd dpanel
chmod +x install.sh
sudo ./install.sh
```

Script sẽ hỏi lần lượt:

1. **Panel domain** (vd: `panel.yourdomain.com`)  
2. **Email** đăng nhập panel  
3. **Mật khẩu** + nhập lại  

Sau đó tự cài Docker, clone/sync mã, build panel, khởi động stack tại `/opt/stack`.

Truy cập: `http://<panel-domain>` hoặc `http://<IP-VPS>:8080` (nếu chưa có DNS).

### Tùy chọn (không bắt buộc)

```bash
export DPANEL_REPO=https://github.com/vutong/dpanel.git
export PANEL_DOMAIN=panel.yourdomain.com   # bỏ qua prompt domain nếu đã set
sudo ./install.sh
```

SSL: **Cloudflare** (Flexible/Full) — VPS chỉ HTTP port 80.

## Control panel

| Menu | Chức năng |
|------|-----------|
| **Website → Tạo** | Domain, Node/PHP, GitHub + token (tùy chọn), deploy |
| **Website → Danh sách** | Các site đã tạo |
| **MariaDB → Danh sách / Tạo / Xóa** | Quản lý database |
| **MariaDB → phpMyAdmin** | Mở `/pma/` qua nginx |

GitHub để trống → chỉ tạo `apps/<domain>/` + cấu hình nginx. Upload do từng dự án tự quản (vd. WordPress `wp-content/uploads`).

## Cấu trúc trên VPS

```
/opt/stack/
├── install.sh (bản copy từ repo)
├── compose.yml
├── panel/              # mã nguồn panel
├── apps/<domain>/      # từng website
├── data/panel/         # auth, sites.json
└── infra/              # nginx, docker, scripts
```

Chi tiết kiến trúc: [AGENTS.md](./AGENTS.md).

## Đổi tên repo GitHub

Repo mới: `https://github.com/vutong/dpanel` — đổi tên từ `ubuntu-docker` trên GitHub Settings → General → Repository name.
