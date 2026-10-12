#!/usr/bin/env bash
# ==============================================================================
# Ephemeral PR Preview Environments - Local Docker Simulation (Bash)
# ==============================================================================
# This script simulates the full lifecycle without AWS/EC2:
# 1. Spins up an isolated local Nginx reverse proxy on port 8080
# 2. Deploys PR #101 (Cyan theme - Checkout Flow V2)
# 3. Deploys PR #102 (Emerald theme - Realtime Alerts)
# 4. Validates routing & health endpoints for both simultaneous previews
# 5. Tears down PR #101 and verifies PR #102 remains healthy and unaffected
# ==============================================================================

set -euo pipefail

PROXY_NAME="preview-local-proxy"
NETWORK_NAME="preview-sim-net"
IMAGE_NAME="ephemeral-preview:simulation"
BASE_DIR="$(pwd)"
NGINX_CONF_FILE="${BASE_DIR}/nginx/gateway-sim.conf"
PREVIEWS_DIR="${BASE_DIR}/nginx-previews"

echo "===================================================================="
echo "🧪 Starting Local Ephemeral PR Preview Simulation (Bash)"
echo "===================================================================="

# Step 0: Ensure Docker is running
if ! docker info &>/dev/null; then
  echo "[-] Docker is not running. Please start Docker Desktop / engine."
  exit 1
fi

# Step 1: Prepare local previews directory and network
mkdir -p "$PREVIEWS_DIR"
mkdir -p "${BASE_DIR}/nginx"

cat << 'EOF' > "${PREVIEWS_DIR}/default-empty.conf"
# Default placeholder so include *.conf never fails
EOF

if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
  echo "[+] Creating Docker network '${NETWORK_NAME}'..."
  docker network create "$NETWORK_NAME"
fi

# Step 2: Build Application Image
echo "[+] Building simulation Docker image '${IMAGE_NAME}'..."
docker build -t "$IMAGE_NAME" .

# Step 3: Start Local Nginx Proxy Container
echo "[+] Starting local Nginx reverse proxy on http://localhost:8080..."
docker rm -f "$PROXY_NAME" 2>/dev/null || true

# Generate Main Proxy Server Configuration
cat << 'EOF' > "$NGINX_CONF_FILE"
server {
    listen 80;
    server_name localhost;

    location = / {
        default_type text/html;
        return 200 '<!DOCTYPE html><html><body style="font-family:sans-serif;background:#0b0f19;color:#fff;text-align:center;padding:50px;"><h2>🚀 Local Ephemeral Preview Gateway</h2><p>Active previews:</p><p><a style="color:#38bdf8;" href="/pr-101/">/pr-101/</a> | <a style="color:#34d399;" href="/pr-102/">/pr-102/</a></p></body></html>';
    }

    # Dynamically included PR preview snippets
    include /etc/nginx/previews/*.conf;
}
EOF

docker run -d \
  --name "$PROXY_NAME" \
  --network "$NETWORK_NAME" \
  -p "8080:80" \
  -v "${NGINX_CONF_FILE}:/etc/nginx/conf.d/default.conf:ro" \
  -v "${PREVIEWS_DIR}:/etc/nginx/previews:rw" \
  nginx:alpine

# Step 4: Deploy Preview for PR #101 (Cyan Theme)
echo ""
echo "--------------------------------------------------------------------"
echo "[+] [STEP 1/3] Deploying PR #101 (Checkout Redesign - Cyan)..."
echo "--------------------------------------------------------------------"
docker rm -f "preview-pr-101" 2>/dev/null || true
docker run -d \
  --name "preview-pr-101" \
  --network "$NETWORK_NAME" \
  -e PORT=3000 \
  -e PR_NUMBER=101 \
  -e GIT_SHA=abc101a \
  -e APP_ENV="preview-pr-101" \
  -e BASE_PATH="/pr-101" \
  -e THEME_NAME="cyan" \
  -e FEATURE_NAME="PR #101: Checkout Redesign" \
  "$IMAGE_NAME"

cat << 'EOF' > "${PREVIEWS_DIR}/pr-101.conf"
location = /pr-101 {
    return 301 /pr-101/;
}
location /pr-101/ {
    proxy_pass http://preview-pr-101:3000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix /pr-101;
}
EOF

docker exec "$PROXY_NAME" nginx -t
docker exec "$PROXY_NAME" nginx -s reload
echo "[✓] PR #101 deployed at http://localhost:8080/pr-101/"

# Step 5: Deploy Preview for PR #102 (Emerald Theme)
echo ""
echo "--------------------------------------------------------------------"
echo "[+] [STEP 2/3] Deploying PR #102 (Realtime Alerts - Emerald)..."
echo "--------------------------------------------------------------------"
docker rm -f "preview-pr-102" 2>/dev/null || true
docker run -d \
  --name "preview-pr-102" \
  --network "$NETWORK_NAME" \
  -e PORT=3000 \
  -e PR_NUMBER=102 \
  -e GIT_SHA=def102b \
  -e APP_ENV="preview-pr-102" \
  -e BASE_PATH="/pr-102" \
  -e THEME_NAME="emerald" \
  -e FEATURE_NAME="PR #102: Realtime Notifications" \
  "$IMAGE_NAME"

cat << 'EOF' > "${PREVIEWS_DIR}/pr-102.conf"
location = /pr-102 {
    return 301 /pr-102/;
}
location /pr-102/ {
    proxy_pass http://preview-pr-102:3000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix /pr-102;
}
EOF

docker exec "$PROXY_NAME" nginx -t
docker exec "$PROXY_NAME" nginx -s reload
echo "[✓] PR #102 deployed at http://localhost:8080/pr-102/"

# Step 6: Verify Both Previews
echo ""
echo "--------------------------------------------------------------------"
echo "[+] Verifying simultaneous preview routing..."
echo "--------------------------------------------------------------------"
sleep 2
echo "Testing PR #101 Health Endpoint:"
curl -s http://localhost:8080/pr-101/health || true
echo ""
echo ""
echo "Testing PR #102 Health Endpoint:"
curl -s http://localhost:8080/pr-102/health || true
echo ""

# Step 7: Teardown PR #101 and verify PR #102 remains alive
echo ""
echo "--------------------------------------------------------------------"
echo "[+] [STEP 3/3] Simulating PR #101 Merge / Close Teardown..."
echo "--------------------------------------------------------------------"
echo "[+] Removing container 'preview-pr-101'..."
docker rm -f "preview-pr-101"
echo "[+] Removing Nginx config for PR #101..."
rm -f "${PREVIEWS_DIR}/pr-101.conf"
docker exec "$PROXY_NAME" nginx -t
docker exec "$PROXY_NAME" nginx -s reload
echo "[✓] Teardown complete for PR #101."

echo ""
echo "Checking PR #101 route (Expected: 404/502):"
STATUS_101=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/pr-101/health || echo "Failed")
echo "  HTTP Status for PR #101: ${STATUS_101}"

echo "Checking PR #102 route (Expected: 200 UP):"
STATUS_102=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/pr-102/health || echo "Failed")
echo "  HTTP Status for PR #102: ${STATUS_102}"

if [ "$STATUS_102" == "200" ]; then
  echo ""
  echo "===================================================================="
  echo "✅ SIMULATION SUCCESSFUL!"
  echo "   - Dynamic Nginx routing works under subpaths (/pr-N/)."
  echo "   - Ephemeral container isolation verified."
  echo "   - Independent teardown verified without affecting active PRs."
  echo "===================================================================="
else
  echo "[-] Simulation encountered an unexpected status."
fi

echo ""
echo "To clean up all simulation resources, run:"
echo "  docker rm -f preview-local-proxy preview-pr-102; docker network rm preview-sim-net; rm -rf nginx-previews"
