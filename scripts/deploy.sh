#!/usr/bin/env bash
# ==============================================================================
# Ephemeral PR Preview Environments - Deployment Script
# ==============================================================================
# Usage:
#   ./scripts/deploy.sh <PR_NUMBER> [GIT_SHA] [IMAGE_NAME] [THEME_NAME] [FEATURE_NAME]
#
# Examples:
#   ./scripts/deploy.sh 42
#   ./scripts/deploy.sh 42 7a8b9c0 preview-app:pr-42 emerald "Dark Mode UI"
# ==============================================================================

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "[-] Error: Missing required argument PR_NUMBER"
  echo "    Usage: $0 <PR_NUMBER> [GIT_SHA] [IMAGE_NAME] [THEME_NAME] [FEATURE_NAME]"
  exit 1
fi

PR_NUMBER="$1"

# Validate numeric PR_NUMBER
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "[-] Error: PR_NUMBER must be an integer, got '${PR_NUMBER}'"
  exit 1
fi

GIT_SHA="${2:-$(git rev-parse --short HEAD 2>/dev/null || echo 'manual-deploy')}"
GIT_SHA="${GIT_SHA:0:7}"
IMAGE_NAME="${3:-preview-app:pr-${PR_NUMBER}}"
THEME_NAME="${4:-}"
FEATURE_NAME="${5:-}"

if [ -z "$THEME_NAME" ]; then
  if [ $((PR_NUMBER % 2)) -eq 0 ]; then
    THEME_NAME="emerald"
  else
    THEME_NAME="cyan"
  fi
fi

if [ -z "$FEATURE_NAME" ]; then
  FEATURE_NAME="PR #${PR_NUMBER} Interactive Preview (${THEME_NAME^} Accent)"
fi

# Deterministic port allocation: 30000 + PR_NUMBER
PORT=$((30000 + PR_NUMBER))

# Validate host port range (1024 - 65535)
if [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  echo "[-] Error: Computed port ${PORT} is out of valid range (1024-65535)"
  exit 1
fi

CONTAINER_NAME="preview-pr-${PR_NUMBER}"
CONF_DIR="/etc/nginx/previews"
CONF_FILE="${CONF_DIR}/pr-${PR_NUMBER}.conf"

echo "===================================================================="
echo "🚀 Deploying Ephemeral Preview for PR #${PR_NUMBER}"
echo "===================================================================="
echo "  Container:    ${CONTAINER_NAME}"
echo "  Image:        ${IMAGE_NAME}"
echo "  Host Port:    127.0.0.1:${PORT}"
echo "  Path Prefix:  /pr-${PR_NUMBER}/"
echo "  Commit SHA:   ${GIT_SHA}"
echo "  Theme:        ${THEME_NAME}"
echo "  Feature:      ${FEATURE_NAME}"
echo "===================================================================="

# 1. Build Docker image with target tag
if [ -f Dockerfile ]; then
  echo "[+] Building Docker image '${IMAGE_NAME}' (commit: ${GIT_SHA})..."
  docker build -t "$IMAGE_NAME" .
elif ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "[-] Error: Dockerfile not found and image '${IMAGE_NAME}' does not exist."
  exit 1
else
  echo "[✓] Using pre-existing Docker image '${IMAGE_NAME}'."
fi

# 2. Stop & remove any existing container for this PR (Idempotency)
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  echo "[+] Removing existing container '${CONTAINER_NAME}'..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Verify port is not colliding with another process on loopback
if ss -tuln 2>/dev/null | grep -Eq "127\.0\.0\.1:${PORT}\b"; then
  echo "[-] Error: Loopback port 127.0.0.1:${PORT} is already in use by another process!"
  exit 1
fi

# 3. Start isolated Docker container
echo "[+] Starting container '${CONTAINER_NAME}' on 127.0.0.1:${PORT}..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "127.0.0.1:${PORT}:3000" \
  -e PORT=3000 \
  -e PR_NUMBER="$PR_NUMBER" \
  -e GIT_SHA="$GIT_SHA" \
  -e APP_ENV="preview-pr-${PR_NUMBER}" \
  -e BASE_PATH="/pr-${PR_NUMBER}" \
  -e THEME_NAME="$THEME_NAME" \
  -e FEATURE_NAME="$FEATURE_NAME" \
  "$IMAGE_NAME"

# 4. Wait for container health check
echo "[+] Waiting for container health check at http://127.0.0.1:${PORT}/health..."
MAX_ATTEMPTS=25
SLEEP_INTERVAL=1
ATTEMPT=0
HEALTH_OK=false

while [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if curl -sf -o /dev/null "http://127.0.0.1:${PORT}/health"; then
    HEALTH_OK=true
    echo "[✓] Preview container is healthy after ${ATTEMPT}s."
    break
  fi
  sleep "$SLEEP_INTERVAL"
done

if [ "$HEALTH_OK" != "true" ]; then
  echo "[-] Error: Container '${CONTAINER_NAME}' failed to pass health check!"
  echo "[-] Dumping container logs:"
  docker logs --tail 50 "$CONTAINER_NAME"
  echo "[-] Rolling back container..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# 5. Generate Dynamic Nginx Configuration
echo "[+] Generating dynamic Nginx configuration: ${CONF_FILE}..."
TMP_CONF="/tmp/pr-${PR_NUMBER}.conf"

cat << EOF > "$TMP_CONF"
# ==============================================================================
# Dynamically generated reverse proxy config for PR #${PR_NUMBER}
# Container: ${CONTAINER_NAME} | Localhost Port: ${PORT}
# Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================

# Redirect non-trailing slash to trailing slash
location = /pr-${PR_NUMBER} {
    return 301 /pr-${PR_NUMBER}/;
}

location /pr-${PR_NUMBER}/ {
    proxy_pass http://127.0.0.1:${PORT}/;
    proxy_http_version 1.1;

    # Standard proxy headers
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Prefix /pr-${PR_NUMBER};

    # Resiliency timeouts
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_read_timeout 60s;
}
EOF

# Ensure destination directory exists
if [ ! -d "$CONF_DIR" ]; then
  echo "[+] Directory ${CONF_DIR} not found, attempting to create..."
  sudo mkdir -p "$CONF_DIR"
fi

# Copy generated config into place
sudo cp "$TMP_CONF" "$CONF_FILE"
rm -f "$TMP_CONF"

# 6. Validate and Reload Nginx
echo "[+] Validating Nginx configuration (nginx -t)..."
if sudo nginx -t; then
  echo "[+] Nginx configuration syntax valid. Reloading Nginx..."
  sudo nginx -s reload || sudo systemctl reload nginx
  echo "[✓] Nginx reloaded successfully."
else
  echo "[-] CRITICAL: Nginx validation failed! Rolling back PR config..."
  sudo rm -f "$CONF_FILE"
  sudo nginx -s reload || sudo systemctl reload nginx
  echo "[-] Rolling back preview container..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# 7. Validate Nginx reverse proxy routing to application health check
echo "[+] Validating Nginx reverse proxy route at http://127.0.0.1/pr-${PR_NUMBER}/health..."
PROXY_MAX=10
PROXY_HEALTH=false
for i in $(seq 1 $PROXY_MAX); do
  if curl -sf -o /dev/null "http://127.0.0.1/pr-${PR_NUMBER}/health"; then
    PROXY_HEALTH=true
    echo "[✓] Nginx proxy routing verified healthy."
    break
  fi
  sleep 1
done

if [ "$PROXY_HEALTH" != "true" ]; then
  echo "[-] Error: Reverse proxy route http://127.0.0.1/pr-${PR_NUMBER}/health failed health verification!"
  echo "[-] Rolling back PR config and container..."
  sudo rm -f "$CONF_FILE"
  sudo nginx -s reload || sudo systemctl reload nginx
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  exit 1
fi

# 8. Print Deployment Summary
HOST_IP="$(curl -s --max-time 2 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo 'SERVER_IP')"

echo "===================================================================="
echo "🎉 Preview Environment Successfully Deployed!"
echo "===================================================================="
echo "  URL:          http://${HOST_IP}/pr-${PR_NUMBER}/"
echo "  Health Check: http://${HOST_IP}/pr-${PR_NUMBER}/health"
echo "  Container:    ${CONTAINER_NAME}"
echo "  Port:         127.0.0.1:${PORT}"
echo "===================================================================="
