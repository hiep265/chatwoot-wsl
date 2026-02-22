# Hướng Dẫn Cài Đặt Chatwoot từ Source Code trên Docker

## Yêu Cầu Hệ Thống

- **Docker**: >= 20.10
- **Docker Compose**: >= 2.0
- **RAM**: Tối thiểu 4GB (khuyến nghị 8GB)
- **Disk**: Tối thiểu 20GB trống (do build từ source)

## Cấu Trúc Dự Án

```
chatwoot-wsl/
├── .env                           # File biến môi trường
├── docker-compose.production.yaml # Docker Compose cho production
├── docker/
│   ├── Dockerfile                 # Dockerfile chính (build từ source)
│   └── entrypoints/
│       └── rails.sh               # Script khởi động Rails
└── ...
```

## Bước 1: Chuẩn Bị File Môi Trường

### 1.1. Tạo file `.env` từ template

```bash
cp .env.example .env
```

### 1.2. Cấu hình các biến môi trường quan trọng

Chỉnh sửa file `.env`:

```bash
# URL frontend (thay bằng domain của bạn)
FRONTEND_URL=https://your-domain.com

# Cấu hình SSL
FORCE_SSL=false

# Cho phép đăng ký tài khoản
ENABLE_ACCOUNT_SIGNUP=true

# Cấu hình Redis (mạng nội bộ Docker)
REDIS_URL=redis://:chatwoot_redis@redis:6379
REDIS_PASSWORD=chatwoot_redis

# Cấu hình PostgreSQL (mạng nội bộ Docker)
POSTGRES_DATABASE=chatwoot
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_PORT=5432

# Môi trường Rails
RAILS_ENV=production

# Secret key (tạo key mới bằng: openssl rand -hex 64)
SECRET_KEY_BASE=your_secret_key_here

# Log settings
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
```

### 1.3. Tạo SECRET_KEY_BASE mới (bắt buộc cho production)

```bash
openssl rand -hex 64
```

Sau đó copy kết quả vào `SECRET_KEY_BASE` trong file `.env`.

### 1.4. Cấp quyền execute cho entrypoint scripts

```bash
chmod +x docker/entrypoints/*.sh
```

## Bước 2: Build Image từ Source Code

### 2.1. Build Docker image

Quá trình này sẽ mất **10-20 phút** tùy vào cấu hình máy.

```bash
sudo docker compose -f docker-compose.production.yaml build
```

Để xem chi tiết quá trình build:

```bash
sudo docker compose -f docker-compose.production.yaml build --progress=plain
```

### 2.2. Kiểm tra image đã build

```bash
sudo docker images | grep chatwoot
```

**Kết quả mong đợi:**

```
chatwoot:production-local   xxxxx   ~800MB
```

## Bước 3: Chạy Docker Compose

### 3.1. Khởi động tất cả các services

```bash
sudo docker compose -f docker-compose.production.yaml up -d
```

### 3.2. Kiểm tra trạng thái containers

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Kết quả mong đợi:**

| Container | Status | Ports |
|-----------|--------|-------|
| chatwoot-rails-1 | Up | 0.0.0.0:3000→3000/tcp |
| chatwoot-sidekiq-1 | Up | (internal) |
| chatwoot-postgres-1 | Up | 5432/tcp (internal) |
| chatwoot-redis-1 | Up | 6379/tcp (internal) |

## Bước 4: Migrate Database

### 4.1. Chạy migration database

```bash
sudo docker compose -f docker-compose.production.yaml exec -T rails bundle exec rails db:chatwoot_prepare
```

### 4.2. Kiểm tra logs để đảm bảo không có lỗi

```bash
sudo docker logs chatwoot-rails-1 --tail 50
```

## Bước 5: Truy Cập Chatwoot

Sau khi hoàn tất, truy cập Chatwoot tại:

- **Local**: http://localhost:3000
- **Production**: https://your-domain.com (nếu đã cấu hình reverse proxy)

## Cấu Trúc Mạng

```
┌─────────────────────────────────────────────────────────┐
│                   chatwoot_network                       │
│  (Mạng nội bộ Docker - các service giao tiếp với nhau)  │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │   postgres   │    │    redis     │                   │
│  │   Port 5432  │    │   Port 6379  │                   │
│  │  (internal)  │    │  (internal)  │                   │
│  └──────────────┘    └──────────────┘                   │
│         ▲                   ▲                            │
│         │                   │                            │
│         └─────────┬─────────┘                            │
│                   │                                      │
│  ┌──────────────────────────────────────┐               │
│  │              rails                    │               │
│  │         Port 3000:3000               │◄──── Internet  │
│  │     (exposed to host)                │               │
│  └──────────────────────────────────────┘               │
│                   │                                      │
│  ┌──────────────────────────────────────┐               │
│  │            sidekiq                    │               │
│  │      (background jobs)               │               │
│  └──────────────────────────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

**Lưu ý:**
- PostgreSQL và Redis chỉ có thể truy cập từ bên trong mạng Docker (bảo mật)
- Chỉ có Rails được expose ra port 3000 để truy cập từ bên ngoài

## Các Lệnh Thường Dùng

### Xem logs

```bash
# Logs của Rails
sudo docker logs chatwoot-rails-1 -f

# Logs của Sidekiq
sudo docker logs chatwoot-sidekiq-1 -f

# Logs tất cả services
sudo docker compose -f docker-compose.production.yaml logs -f
```

### Restart services

```bash
# Restart tất cả
sudo docker compose -f docker-compose.production.yaml restart

# Restart một service cụ thể
sudo docker compose -f docker-compose.production.yaml restart rails
```

### Dừng services

```bash
sudo docker compose -f docker-compose.production.yaml down
```

### Dừng và xóa dữ liệu (CẢNH BÁO: Mất hết dữ liệu!)

```bash
sudo docker compose -f docker-compose.production.yaml down -v
```

### Vào shell của container

```bash
# Rails console
sudo docker compose -f docker-compose.production.yaml exec rails bundle exec rails console

# Bash shell
sudo docker compose -f docker-compose.production.yaml exec rails /bin/sh
```

### Backup Database

```bash
# Backup
sudo docker compose -f docker-compose.production.yaml exec postgres pg_dump -U postgres chatwoot > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore
sudo docker compose -f docker-compose.production.yaml exec -T postgres psql -U postgres chatwoot < backup_file.sql
```

## Cấu Hình Reverse Proxy (Nginx)

Nếu bạn muốn sử dụng domain với HTTPS, cấu hình Nginx như sau:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket support
    location /cable {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Troubleshooting

### 1. Lỗi "permission denied" khi chạy entrypoint

**Nguyên nhân**: File entrypoint chưa có quyền execute

**Giải pháp**:
```bash
chmod +x docker/entrypoints/*.sh
sudo docker compose -f docker-compose.production.yaml build --no-cache
sudo docker compose -f docker-compose.production.yaml up -d
```

### 2. Container Rails liên tục restart

**Nguyên nhân**: Database chưa được migrate

**Giải pháp**:
```bash
sudo docker compose -f docker-compose.production.yaml exec -T rails bundle exec rails db:chatwoot_prepare
```

### 3. Không kết nối được PostgreSQL/Redis

**Kiểm tra**:
```bash
# Kiểm tra network
sudo docker network ls
sudo docker network inspect chatwoot-wsl_chatwoot_network

# Kiểm tra kết nối từ Rails container
sudo docker compose -f docker-compose.production.yaml exec rails ping postgres
sudo docker compose -f docker-compose.production.yaml exec rails ping redis
```

### 4. Lỗi permission denied khi chạy Docker

**Giải pháp**: Thêm user vào group docker
```bash
sudo usermod -aG docker $USER
# Sau đó logout và login lại
```

### 5. Build thất bại do thiếu bộ nhớ

**Triệu chứng**: Build bị killed

**Giải pháp**: Tăng RAM hoặc thêm swap
```bash
# Tạo swap 4GB
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 6. Build quá chậm

**Giải pháp**: Sử dụng BuildKit cache
```bash
DOCKER_BUILDKIT=1 sudo docker compose -f docker-compose.production.yaml build
```

## Cập Nhật Chatwoot (Từ Source Code)

### Khi có code mới:

```bash
# 1. Pull code mới
git pull origin main

# 2. Cấp quyền execute (nếu có file mới)
chmod +x docker/entrypoints/*.sh

# 3. Rebuild image
sudo docker compose -f docker-compose.production.yaml build

# 4. Restart với image mới
sudo docker compose -f docker-compose.production.yaml up -d

# 5. Chạy migrations
sudo docker compose -f docker-compose.production.yaml exec -T rails bundle exec rails db:chatwoot_prepare
```

## Cấu Hình Docker Compose

File `docker-compose.production.yaml`:

```yaml
services:
  base: &base
    build:
      context: .
      dockerfile: ./docker/Dockerfile
      args:
        RAILS_ENV: 'production'
        RAILS_SERVE_STATIC_FILES: 'true'
    image: chatwoot:production-local
    env_file: .env
    volumes:
      - storage_data:/app/storage
    networks:
      - chatwoot_network

  rails:
    <<: *base
    depends_on:
      - postgres
      - redis
    ports:
      - '3000:3000'
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
    restart: always

  sidekiq:
    <<: *base
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
    restart: always

  postgres:
    image: pgvector/pgvector:pg16
    restart: always
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    networks:
      - chatwoot_network

  redis:
    image: redis:alpine
    restart: always
    command: ["sh", "-c", "redis-server --requirepass \"$REDIS_PASSWORD\""]
    env_file: .env
    volumes:
      - redis_data:/data
    networks:
      - chatwoot_network

networks:
  chatwoot_network:
    driver: bridge

volumes:
  storage_data:
  postgres_data:
  redis_data:
```

---

**Ngày tạo**: 2026-02-10  
**Phương thức cài đặt**: Build từ Source Code  
**Image**: chatwoot:production-local
