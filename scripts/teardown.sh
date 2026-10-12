#!/usr/bin/env bash
# ==============================================================================
# Ephemeral PR Preview Environments - Teardown Script
# ==============================================================================
# Usage:
#   ./scripts/teardown.sh <PR_NUMBER>
#
# Examples:
#   ./scripts/teardown.sh 42
# ==============================================================================

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "[-] Error: Missing required argument PR_NUMBER"
  echo "    Usage: $0 <PR_NUMBER>"
  exit 1
fi

PR_NUMBER="$1"

# Validate numeric PR_NUMBER
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "[-] Error: PR_NUMBER must be an integer, got '${PR_NUMBER}'"
  exit 1
fi

# Guard protected manual preview environments (e.g., PR #1000 or preview-test)
if [ "$PR_NUMBER" -eq 1000 ] 2>/dev/null; then
  echo "[!] Protection: PR #1000 is reserved as a permanent manual test environment. Skipping teardown."
  exit 0
fi

CONTAINER_NAME="preview-pr-${PR_NUMBER}"
CONF_FILE="/etc/nginx/previews/pr-${PR_NUMBER}.conf"

echo "===================================================================="
echo "🧹 Tearing Down Ephemeral Preview for PR #${PR_NUMBER}"
echo "===================================================================="
echo "  Target Container: ${CONTAINER_NAME}"
echo "  Target Config:    ${CONF_FILE}"
echo "===================================================================="

# 1. Stop and remove Docker container
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
  echo "[+] Stopping and removing container '${CONTAINER_NAME}'..."
  docker rm -f "$CONTAINER_NAME"
  echo "[✓] Container removed."
else
  echo "[✓] Container '${CONTAINER_NAME}' is not running (already clean)."
fi

# 2. Remove dynamic Nginx configuration snippet
if [ -f "$CONF_FILE" ]; then
  echo "[+] Removing Nginx config snippet '${CONF_FILE}'..."
  sudo rm -f "$CONF_FILE"
  echo "[✓] Config snippet removed."
else
  echo "[✓] Config snippet '${CONF_FILE}' does not exist (already clean)."
fi

# 3. Validate and reload Nginx
echo "[+] Validating Nginx configuration after route removal (nginx -t)..."
if sudo nginx -t; then
  echo "[+] Configuration valid. Reloading Nginx..."
  sudo nginx -s reload || sudo systemctl reload nginx
  echo "[✓] Nginx reloaded successfully. Route /pr-${PR_NUMBER}/ is now deactivated."
else
  echo "[-] CRITICAL: Nginx validation failed after teardown!"
  exit 1
fi

# 4. Clean up dangling images to prevent disk space exhaustion
echo "[+] Cleaning up dangling Docker images..."
docker image prune -f >/dev/null 2>&1 || true

echo "===================================================================="
echo "✅ Ephemeral Teardown Complete for PR #${PR_NUMBER}!"
echo "===================================================================="
