# Deployment

## Overview

BirdMap uses a Docker Compose stack. This guide covers deploying to a Linux VPS (e.g. DigitalOcean, Hetzner, AWS EC2).

---

## Recommended Server Specs

| Component | Minimum | Recommended |
|---|---|---|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 2 GB | 8 GB |
| Disk | 20 GB SSD | 100 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| Open ports | 80, 443 | 80, 443, 22 |

The ML training pipeline is run separately (laptop or cloud GPU) — the production server only serves the API and hosts MinIO.

---

## Server Setup

### 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Install Docker Compose plugin

```bash
sudo apt-get install -y docker-compose-plugin
docker compose version
```

### 3. Clone the repository

```bash
git clone https://github.com/your-org/birdmap.git /opt/birdmap
cd /opt/birdmap
```

### 4. Configure environment

```bash
cp backend/.env.example backend/.env
nano backend/.env
```

Set production values:

```env
DATABASE_URL=postgresql+asyncpg://birdmap:STRONG_PASSWORD@db:5432/birdmap
SECRET_KEY=64-char-random-string
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY=your-minio-user
S3_SECRET_KEY=your-minio-password
S3_BUCKET=birdmap-photos
MODEL_BUCKET=birdmap-models
```

Also update the PostgreSQL password in `docker-compose.yml` to match `DATABASE_URL`.

### 5. Start services

```bash
docker compose up -d
docker compose ps
```

### 6. Run migrations

```bash
docker compose exec db psql -U birdmap -d birdmap \
  -c "$(cat backend/migrations/init.sql)"
```

---

## HTTPS with Nginx + Certbot

BirdMap must be served over HTTPS for the iOS app to make network requests (ATS requirement).

### Install Nginx

```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

### Configure Nginx

Create `/etc/nginx/sites-available/birdmap`:

```nginx
server {
    server_name api.birdmap.app;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 20M;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/birdmap /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Obtain SSL certificate

```bash
sudo certbot --nginx -d api.birdmap.app
```

Certbot auto-renews — verify with:

```bash
sudo certbot renew --dry-run
```

---

## MinIO in Production

For production, MinIO should not be exposed publicly. The API container communicates with MinIO internally on the Docker network (`http://minio:9000`).

Presigned URLs signed by MinIO will use the internal hostname unless you configure an external endpoint:

```env
# Add to backend/.env for public presigned URLs
S3_ENDPOINT=https://files.birdmap.app
```

If you want MinIO's console accessible, reverse-proxy port 9001 to a separate subdomain behind authentication.

---

## Keeping the Stack Updated

```bash
cd /opt/birdmap
git pull
docker compose pull
docker compose up -d --build
```

---

## Backups

### Database

```bash
# Dump
docker compose exec db pg_dump -U birdmap birdmap | gzip > backup_$(date +%Y%m%d).sql.gz

# Restore
gunzip -c backup_20240601.sql.gz | docker compose exec -T db psql -U birdmap -d birdmap
```

Set up a daily cron:

```cron
0 3 * * * cd /opt/birdmap && docker compose exec -T db pg_dump -U birdmap birdmap | gzip > /backups/birdmap_$(date +\%Y\%m\%d).sql.gz
```

### MinIO data

MinIO data is in the `minio_data` Docker volume. For off-site backup, use `mc mirror`:

```bash
# Install mc (MinIO client)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

mc alias set local http://localhost:9000 minioadmin minioadmin123
mc alias set s3 https://s3.amazonaws.com YOUR_KEY YOUR_SECRET

# Mirror all buckets to S3
mc mirror local/ s3/birdmap-backup/
```

---

## Monitoring

### Uptime check

```bash
curl https://api.birdmap.app/health
# {"status":"ok"}
```

Use a service like UptimeRobot (free tier) to ping `/health` every 5 minutes and alert on failure.

### Log viewing

```bash
# All services
docker compose logs -f

# API only
docker compose logs -f api

# Filter errors
docker compose logs api 2>&1 | grep -i error
```

---

## Scaling Considerations

The current architecture is a single-machine Docker Compose setup. To scale:

| Bottleneck | Solution |
|---|---|
| API throughput | Run multiple API replicas behind Nginx `upstream` with least-connection balancing |
| Photo storage | Move MinIO to AWS S3 or Cloudflare R2 for CDN delivery |
| Database | Upgrade to managed PostgreSQL (e.g. Supabase, RDS) for replication and auto-backups |
| Model training | Move ML pipeline to a cloud GPU instance or managed MLOps platform |
