#!/usr/bin/env bash
# Shared iOS API_BASE_URL patcher — used by deploy.sh, deploy-gcp.sh, and
# deploy-selfhost.sh so all three compute targets patch the same place the
# same way. Whichever one runs last is what the app points at; can be
# run standalone too: ./update-api-url.sh https://your-backend-url
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
NEW_URL="${1:?Usage: ./update-api-url.sh <backend-url>}"

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}==>${NC} $*"; }

info "Patching iOS project.yml with $NEW_URL..."
# Matches whatever backend URL shape was there before — Fly.io (original),
# Render, Cloud Run, or a previous trycloudflare.com self-host tunnel.
sed -i '' -E \
  "s|https://birdmap-api\.fly\.dev|$NEW_URL|g; \
   s|https://birdmap-api\.onrender\.com|$NEW_URL|g; \
   s|https://birdmap-api-[a-z0-9]+\.[a-z0-9]+\.run\.app|$NEW_URL|g; \
   s|https://[a-z-]+\.trycloudflare\.com|$NEW_URL|g" \
  "$REPO_ROOT/ios/BirdRadar/project.yml"

cd "$REPO_ROOT/ios/BirdRadar"
xcodegen generate > /dev/null
cp Package.resolved.backup BirdRadar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || true
cd "$REPO_ROOT"
echo "    Xcode project regenerated."
