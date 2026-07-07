#!/bin/bash
# ==============================================================================
# Lanai Portal - Quick Fix Script
# ==============================================================================
# Run this on the remote server: /home/newwaveclaw/projects/lanai-code/lanai-portal
# This will pull the latest code, build, and deploy the server
# ==============================================================================

set -e

echo "============================================"
echo "  Lanai Portal Quick Fix & Deploy"
echo "============================================"
echo ""

# Navigate to project
cd /home/newwaveclaw/projects/lanai-code/lanai-portal

echo "[1/5] Fetching latest code from GitHub..."
git fetch origin || {
  echo "ERROR: Git fetch failed. Check if this is a git repository."
  exit 1
}

# Check if feat-chatwoot-integration branch exists locally
if git branch -a | grep -q "feat-chatwoot-integration"; then
  echo "  Checking out feat-chatwoot-integration branch..."
  git checkout feat-chatwoot-integration
  git pull origin feat-chatwoot-integration || true
else
  echo "  Branch not found locally, fetching..."
  git fetch origin feat-chatwoot-integration
  git checkout feat-chatwoot-integration
fi

echo ""
echo "[2/5] Creating .env file if it doesn't exist..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "  Created .env from .env.example"
  echo "  WARNING: Please edit .env and set your actual values before deploying!"
  echo "  At minimum, set: JWT_SECRET, BUILT_IN_FORGE_API_KEY, DATABASE_URL"
fi

echo ""
echo "[3/5] Stopping old container..."
sudo docker rm -f lanai-server 2>/dev/null || echo "  No existing container to stop"

echo ""
echo "[4/5] Building Docker image with VITE_ build args..."
# Extract BUILT_IN_FORGE_API_KEY from .env if it exists
BUILT_IN_FORGE_API_KEY=$(grep "^BUILT_IN_FORGE_API_KEY=" .env 2>/dev/null | cut -d'=' -f2- || echo "CHANGE_ME")
if [ -z "$BUILT_IN_FORGE_API_KEY" ] || [ "$BUILT_IN_FORGE_API_KEY" = "CHANGE_ME" ]; then
  echo "  Using default API key (update .env for production)"
fi

sudo docker build \
  --build-arg VITE_OAUTH_PORTAL_URL=http://keycloak:8080 \
  --build-arg VITE_APP_ID=lanai-portal \
  --build-arg VITE_FRONTEND_FORGE_API_URL=http://dapr:3500 \
  --build-arg VITE_FRONTEND_FORGE_API_KEY="$BUILT_IN_FORGE_API_KEY" \
  -t lanai-server:latest .

if [ $? -ne 0 ]; then
  echo "ERROR: Docker build failed!"
  exit 1
fi

echo ""
echo "[5/5] Starting lanai-server container..."
sudo docker run -d \
  --name lanai-server \
  --network app-net \
  -p 3001:3001 \
  --env-file .env \
  --restart unless-stopped \
  lanai-server:latest

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to start container"
  echo "Check logs: sudo docker logs lanai-server"
  exit 1
fi

echo ""
echo "Waiting for container to initialize..."
sleep 10

echo ""
echo "============================================"
echo "  Verification"
echo "============================================"
echo ""

# Check container is running
if sudo docker ps | grep -q "lanai-server"; then
  echo "✓ Container is running"
else
  echo "✗ Container is NOT running"
  echo "Check logs: sudo docker logs lanai-server"
fi

echo ""
echo "Testing endpoints..."

# Test SPA
SPA_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://lanai.newfire.app/ 2>/dev/null || echo "000")
echo "  SPA (homepage): HTTP $SPA_CODE"

# Test tRPC
TRPC_BODY=$(curl -s "https://lanai.newfire.app/api/trpc/system.health?input=%7B%7D" 2>/dev/null | head -1 || echo "")
if echo "$TRPC_BODY" | grep -q "{"; then
  echo "  tRPC API: JSON response (API is working)"
else
  echo "  tRPC API: $TRPC_BODY"
fi

# Test login
LOGIN_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://lanai.newfire.app/login 2>/dev/null || echo "000")
echo "  Login page: HTTP $LOGIN_CODE"

echo ""
if [ "$SPA_CODE" = "200" ]; then
  echo "============================================"
  echo "  ✅ Deployment Successful!"
  echo "============================================"
  echo ""
  echo "Access your portal at: https://lanai.newfire.app"
  echo ""
  echo "View logs: sudo docker logs -f lanai-server"
  echo "Restart:   sudo docker restart lanai-server"
  echo "Stop:      sudo docker stop lanai-server"
else
  echo "============================================"
  echo "  ⚠️  Deployment May Have Issues"
  echo "============================================"
  echo ""
  echo "Check container logs:"
  echo "  sudo docker logs lanai-server"
  echo ""
  echo "Common issues:"
  echo "  1. .env file not configured properly"
  echo "  2. Database connection failed"
  echo "  3. Port 3001 already in use"
  echo "  4. Missing services on app-net network"
fi
