#!/usr/bin/env bash
# BirdRadar deployment script — self-hosted compute target (your own machine
# as a temporary server). Runs ON that machine, not on your Mac — clone this
# repo there first, then run this script from the clone.
#
# Written for Ubuntu Server (no OS assumptions beyond that — this does NOT
# run on the Mac side of things the way deploy.sh/deploy-gcp.sh do).
#
# Same Supabase data layer as the other two compute targets — needs
# backend/.env.supabase copied over from a machine that already ran
# deploy.sh, deploy-gcp.sh, or `source provision-supabase.sh` (needs the
# Supabase CLI + login, which this script does not attempt to set up).
#
# Exposure: a home network has no public IP/open ports by default. This uses
# a Cloudflare Tunnel "quick tunnel" — free, no Cloudflare account, no owned
# domain required — which gets you a real https://*.trycloudflare.com URL.
# The one real tradeoff: that URL changes every time the tunnel restarts
# (reboot, crash, manual restart) — there is no way around this without
# owning a domain on Cloudflare DNS (a persistent named tunnel requires one;
# confirmed, not assumed). This script writes the current URL to
# /var/log/birdmap-tunnel-url.log every time it changes — check that file
# after any restart and re-run update-api-url.sh on your Mac if it moved.
#
# Usage: ./deploy-selfhost.sh [path/to/backend/.env.supabase]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${1:-$REPO_ROOT/backend/.env.supabase}"
CONTAINER_NAME="birdmap-api"
TUNNEL_LOG="/var/log/birdmap-tunnel-url.log"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }

if [ ! -f "$ENV_FILE" ]; then
  warn "No env file at $ENV_FILE."
  warn "Copy backend/.env.supabase from a machine that already ran deploy.sh,"
  warn "deploy-gcp.sh, or provision-supabase.sh (needs Supabase CLI + login),"
  warn "then re-run: ./deploy-selfhost.sh /path/to/.env.supabase"
  exit 1
fi

# ── 1. Docker ──────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  warn "Added $USER to the docker group — log out and back in (or run 'newgrp docker')"
  warn "if the next command fails with a permission error, then re-run this script."
fi

# ── 2. cloudflared ─────────────────────────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
  info "Installing cloudflared..."
  ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
  curl -L --output /tmp/cloudflared \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"
  chmod +x /tmp/cloudflared
  sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
fi

# ── 3. Build and run the backend container ─────────────────────────────────────
info "Building backend image (this reuses backend/Dockerfile — same image Render/Cloud Run run)..."
docker build -t "$CONTAINER_NAME" "$REPO_ROOT/backend"

info "Starting backend container (restarts automatically on crash or reboot)..."
docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --env-file "$ENV_FILE" \
  -p 8000:8000 \
  "$CONTAINER_NAME"

info "Waiting for the backend to become healthy..."
for i in $(seq 1 30); do
  curl -sf http://localhost:8000/health > /dev/null 2>&1 && break
  sleep 2
done
curl -sf http://localhost:8000/health > /dev/null 2>&1 || warn "Backend isn't responding on :8000 yet — check 'docker logs $CONTAINER_NAME'."

# ── 4. Persistent systemd service for the tunnel ───────────────────────────────
info "Installing systemd service for the Cloudflare Tunnel..."
sudo tee /etc/systemd/system/birdmap-tunnel.service > /dev/null <<EOF
[Unit]
Description=BirdRadar Cloudflare Tunnel (quick tunnel — URL changes on restart)
After=network-online.target docker.service
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --url http://localhost:8000
Restart=on-failure
RestartSec=5
StandardOutput=append:$TUNNEL_LOG
StandardError=append:$TUNNEL_LOG

[Install]
WantedBy=multi-user.target
EOF

sudo touch "$TUNNEL_LOG" && sudo chmod 644 "$TUNNEL_LOG"
sudo systemctl daemon-reload
sudo systemctl enable --now birdmap-tunnel.service

info "Waiting for the tunnel to come up and print its URL..."
TUNNEL_URL=""
for i in $(seq 1 30); do
  TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | tail -1 || true)
  [ -n "$TUNNEL_URL" ] && break
  sleep 2
done

if [ -z "$TUNNEL_URL" ]; then
  warn "Couldn't find the tunnel URL yet — check: sudo tail -f $TUNNEL_LOG"
  warn "Once you see it, run update-api-url.sh with it from your Mac."
  exit 1
fi

echo ""
info "Backend is live at: $TUNNEL_URL"
echo "  Container:      docker logs -f $CONTAINER_NAME"
echo "  Tunnel service:  sudo systemctl status birdmap-tunnel"
echo "  Tunnel log:      $TUNNEL_LOG"
echo ""
warn "This URL changes on every tunnel restart (reboot, crash, manual restart)."
warn "After any restart, check $TUNNEL_LOG for the new one, then from your Mac:"
echo "    ./update-api-url.sh $TUNNEL_URL"
echo ""
info "From your Mac, right now:"
echo "    ./update-api-url.sh $TUNNEL_URL"
