# Lanai Portal - Emergency Deployment Fix

## Problem
Remote server at `/home/newwaveclaw/projects/lanai-code/lanai-portal` is missing critical files:
- Dockerfile (needed to rebuild with VITE_ env vars)
- .env file (runtime configuration)
- Fixed server/index.ts (wires up all API routes)
- Other server files

## Solution
Copy all files from the git repository and rebuild with VITE_ build arguments.

## Step-by-Step Instructions

### Step 1: SSH into your remote server
```bash
ssh newwaveclaw@your-server-ip
```

### Step 2: Navigate to the lanai-portal directory
```bash
cd /home/newwaveclaw/projects/lanai-code/lanai-portal
```

### Step 3: Get the fixed files from GitHub
```bash
# The fixes are on the feat-chatwoot-integration branch
git fetch origin
git checkout feat-chatwoot-integration
```

### Step 4: Create .env file from example
```bash
cp .env.example .env
```

### Step 5: Edit .env and set your actual values
```bash
nano .env
```

Required changes in .env:
- Set `JWT_SECRET=YOUR_ACTUAL_SECRET` (random 64-char string)
- Set `BUILT_IN_FORGE_API_KEY=YOUR_ACTUAL_KEY`
- Set `TWENTY_CRM_API_TOKEN=YOUR_ACTUAL_TOKEN`
- Set `CHATWOOT_ACCESS_TOKEN=YOUR_ACTUAL_TOKEN`
- Update database URL if different from example
- Add any other service credentials

### Step 6: Stop the current container
```bash
sudo docker rm -f lanai-server 2>/dev/null
```

### Step 7: Build Docker image WITH VITE_ build args (CRITICAL)
```bash
sudo docker build \
  --build-arg VITE_OAUTH_PORTAL_URL=http://keycloak:8080 \
  --build-arg VITE_APP_ID=lanai-portal \
  --build-arg VITE_FRONTEND_FORGE_API_URL=http://dapr:3500 \
  --build-arg VITE_FRONTEND_FORGE_API_KEY=$(grep BUILT_IN_FORGE_API_KEY .env | cut -d= -f2) \
  -t lanai-server:latest .
```

### Step 8: Start the new container
```bash
sudo docker run -d \
  --name lanai-server \
  --network app-net \
  -p 3001:3001 \
  --env-file .env \
  --restart unless-stopped \
  lanai-server:latest
```

### Step 9: Verify the server is running
```bash
# Check container status
sudo docker ps | grep lanai-server

# Check logs
sudo docker logs --tail 50 lanai-server

# Test SPA loads (should return HTML)
curl -sI https://lanai.newfire.app | head -5

# Test tRPC returns JSON (not HTML)
curl -s https://lanai.newfire.app/api/trpc/system.health?input=%7B%7D | head -20

# Test login page
curl -sI https://lanai.newfire.app/login | head -5
```

### Step 10: Monitor for errors
```bash
# Watch logs in real-time
sudo docker logs -f lanai-server
```

## Expected Results

After successful deployment:
- ✅ Homepage loads without JavaScript errors
- ✅ tRPC API returns JSON (not HTML)
- ✅ Login/register pages load correctly
- ✅ OAuth integration works
- ✅ All API routes functional

## Troubleshooting

### If build fails
```bash
# Check if Dockerfile exists
ls -la Dockerfile

# Check if package.json exists
ls -la package.json

# Check pnpm-lock.yaml
ls -la pnpm-lock.yaml
```

### If container won't start
```bash
# Check logs
sudo docker logs lanai-server

# Common issues:
# 1. .env file missing - create it from .env.example
# 2. Wrong DATABASE_URL - verify PostgreSQL is running
# 3. Port 3001 already in use - check with: sudo lsof -i :3001
```

### If frontend still shows "Invalid URL" error
This means the Docker build didn't include VITE_ build args. Run step 7 again with all --build-arg flags.

### If API returns HTML instead of JSON
This means server/index.ts wasn't properly deployed. Verify the file exists:
```bash
cat server/index.ts | head -20
```

Should show the full server with all route registrations.

## Quick Deploy Script

Copy and paste this entire block into your terminal on the remote server:

```bash
#!/bin/bash
set -e

echo "=== Lanai Portal Emergency Deploy ==="

# Navigate to project
cd /home/newwaveclaw/projects/lanai-code/lanai-portal

# Get latest fixes
git fetch origin
git checkout feat-chatwoot-integration
git pull origin feat-chatwoot-integration

# Create .env if it doesn't exist
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from example - please edit with your actual values"
fi

# Stop old container
sudo docker rm -f lanai-server 2>/dev/null || true

# Extract values from .env
VITE_FORGE_API_KEY=$(grep VITE_FRONTEND_FORGE_API_KEY .env.example | cut -d= -f2 || echo "CHANGE_ME")
BUILT_IN_FORGE_API_KEY=$(grep BUILT_IN_FORGE_API_KEY .env | cut -d= -f2 || echo "CHANGE_ME")

echo "Building Docker image with VITE_ build args..."

# Build with VITE_ build args (CRITICAL)
sudo docker build \
  --build-arg VITE_OAUTH_PORTAL_URL=http://keycloak:8080 \
  --build-arg VITE_APP_ID=lanai-portal \
  --build-arg VITE_FRONTEND_FORGE_API_URL=http://dapr:3500 \
  --build-arg VITE_FRONTEND_FORGE_API_KEY=$BUILT_IN_FORGE_API_KEY \
  -t lanai-server:latest .

echo "Starting container..."

# Start container
sudo docker run -d \
  --name lanai-server \
  --network app-net \
  -p 3001:3001 \
  --env-file .env \
  --restart unless-stopped \
  lanai-server:latest

echo "Waiting for container to start..."
sleep 5

echo "Verifying deployment..."

# Test
SPA_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://lanai.newfire.app/)
TRPC_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://lanai.newfire.app/api/trpc/system.health?input=%7B%7D)

echo "SPA HTTP status: $SPA_CODE"
echo "tRPC HTTP status: $TRPC_CODE"

if [ "$SPA_CODE" = "200" ] && [ "$TRPC_CODE" = "400" ]; then
  echo "✅ Deployment successful!"
  echo "   SPA returns 200 (HTML)"
  echo "   tRPC returns 400 (JSON error = API is working)"
  echo ""
  echo "Access at: https://lanai.newfire.app"
else
  echo "❌ Deployment may have issues"
  echo "Check logs: sudo docker logs lanai-server"
fi
```

Save this as `deploy.sh` and run:
```bash
chmod +x deploy.sh
sudo ./deploy.sh
```
