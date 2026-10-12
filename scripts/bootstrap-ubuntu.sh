#!/usr/bin/env bash
# ==============================================================================
# Ephemeral PR Preview Environments - Ubuntu 24.04 Host Bootstrap Script
# ==============================================================================
# This script provisions an Ubuntu 24.04 LTS EC2 instance as an Ephemeral Preview
# Docker Host with dynamic Nginx reverse proxy routing.
#
# Requirements satisfied:
# - Least-privilege permissions
# - Automated Docker and Nginx installation
# - Dynamic preview routing directory structure
# - Idempotent execution
# ==============================================================================

set -euo pipefail

echo "===================================================================="
echo "🚀 Starting Bootstrap: Ephemeral PR Preview Docker Host (Ubuntu 24.04)"
echo "===================================================================="

# Check root or sudo
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root or with sudo: sudo ./scripts/bootstrap-ubuntu.sh"
  exit 1
fi

DEPLOY_USER="${SUDO_USER:-ubuntu}"
echo "[+] Target deploy user: ${DEPLOY_USER}"

# 1. Update system packages
echo "[+] Updating apt repositories..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw rsync

# 2. Install Docker Engine
echo "[+] Installing Docker..."
if ! command -v docker &> /dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "[+] Docker installed successfully."
else
  echo "[✓] Docker is already installed."
fi

# Enable and start Docker service
systemctl enable docker
systemctl start docker

# Add deploy user to docker group (least privilege - avoids running docker with sudo)
if id "$DEPLOY_USER" &>/dev/null; then
  usermod -aG docker "$DEPLOY_USER"
  echo "[+] Added user '${DEPLOY_USER}' to 'docker' group."
fi

# 3. Install Nginx
echo "[+] Installing Nginx..."
if ! command -v nginx &> /dev/null; then
  apt-get install -y nginx
  echo "[+] Nginx installed successfully."
else
  echo "[✓] Nginx is already installed."
fi

systemctl enable nginx
systemctl start nginx

# 4. Set up Dynamic Preview Directory & Nginx Gateway
echo "[+] Configuring dynamic preview directories..."
mkdir -p /etc/nginx/previews
mkdir -p /var/www/html

# Create default placeholder so wildcard include never errors when 0 PRs are active
cat << 'EOF' > /etc/nginx/previews/default-empty.conf
# Placeholder to ensure Nginx wildcard include (/etc/nginx/previews/*.conf)
# always matches at least one file even when zero PR previews are deployed.
EOF

# Create Root Landing Page for Port 80
cat << 'EOF' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Preview Environments Gateway</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0b0f19; color: #f9fafb; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .box { background: #1f2937; padding: 2.5rem; border-radius: 12px; border: 1px solid #374151; max-width: 580px; text-align: center; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
    h1 { margin-top: 0; color: #38bdf8; }
    code { background: #111827; padding: 0.2rem 0.4rem; border-radius: 4px; font-family: monospace; color: #34d399; }
    p { color: #9ca3af; line-height: 1.6; }
    .badge { display: inline-block; padding: 0.3rem 0.8rem; background: rgba(56,189,248,0.15); color: #38bdf8; border-radius: 999px; font-weight: 600; font-size: 0.85rem; margin-bottom: 1rem; }
  </style>
</head>
<body>
  <div class="box">
    <div class="badge">Nginx Dynamic Reverse Proxy Gateway</div>
    <h1>🚀 Preview Environments Host</h1>
    <p>This server automatically routes pull request previews to isolated Docker containers.</p>
    <p>Access your preview environment using the path: <code>http://&lt;HOST_IP&gt;/pr-&lt;PR_NUMBER&gt;/</code></p>
    <p>Managed dynamically by GitHub Actions CI/CD workflows.</p>
  </div>
</body>
</html>
EOF

# Configure Main Nginx Site (/etc/nginx/sites-available/default)
echo "[+] Writing default Nginx gateway configuration..."
cat << 'EOF' > /etc/nginx/sites-available/default
# Ephemeral Preview Reverse Proxy Gateway
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Root landing page
    location = / {
        root /var/www/html;
        index index.html;
    }

    # Health check for the gateway itself
    location = /gateway-health {
        access_log off;
        default_type application/json;
        return 200 '{"status":"GATEWAY_UP","service":"nginx-reverse-proxy"}';
    }

    # Include all dynamically generated PR preview routes
    include /etc/nginx/previews/*.conf;
}
EOF

# Enable default site if not already enabled
if [ ! -L /etc/nginx/sites-enabled/default ]; then
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

# 5. Configure sudoers permissions for deploy user (least privilege)
# Deploy user needs to test and reload nginx without password prompts
echo "[+] Granting least-privilege Nginx reload permissions to '${DEPLOY_USER}'..."
cat << EOF > /etc/sudoers.d/nginx-preview-deploy
# Allow deploy user to test and reload Nginx without password
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t, /usr/sbin/nginx -s reload, /usr/bin/systemctl reload nginx, /usr/bin/cp * /etc/nginx/previews/*, /usr/bin/rm -f /etc/nginx/previews/*
EOF
chmod 0440 /etc/sudoers.d/nginx-preview-deploy

# Set proper directory ownership so deploy user can write preview configs
chown -R ${DEPLOY_USER}:${DEPLOY_USER} /etc/nginx/previews

# 6. Test and reload Nginx
echo "[+] Testing Nginx configuration..."
nginx -t
systemctl reload nginx

# 7. Configure Firewall (UFW)
if ufw status | grep -q "Status: active"; then
  echo "[+] Allowing SSH (22) and HTTP (80) in UFW..."
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw reload
fi

echo "===================================================================="
echo "✅ Bootstrap Complete!"
echo "===================================================================="
echo ""
echo "NEXT STEPS FOR GITHUB ACTIONS SECRETS CONFIGURATION:"
echo "--------------------------------------------------------------------"
echo "1. Retrieve your EC2 public IP:"
echo "   curl -s ifconfig.me"
echo ""
echo "2. Generate pinned SSH host key entry for SSH_KNOWN_HOSTS:"
echo "   ssh-keyscan -H \$(curl -s ifconfig.me)"
echo ""
echo "3. Add the following repository secrets in GitHub:"
echo "   (Settings -> Secrets and variables -> Actions -> New repository secret)"
echo ""
echo "   - EC2_HOST        : Your EC2 Public IPv4 (e.g. 54.x.x.x)"
echo "   - EC2_USER        : ${DEPLOY_USER}"
echo "   - SSH_PRIVATE_KEY : The private SSH key (.pem) used to connect to EC2"
echo "   - SSH_KNOWN_HOSTS : The pinned host key line from step 2"
echo ""
echo "4. Ensure EC2 Security Group allows Inbound:"
echo "   - Port 22  (SSH)  : Your GitHub Actions IP or 0.0.0.0/0"
echo "   - Port 80  (HTTP) : 0.0.0.0/0 (For browser preview access)"
echo "===================================================================="
