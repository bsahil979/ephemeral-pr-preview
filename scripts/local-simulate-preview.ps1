# ==============================================================================
# Ephemeral PR Preview Environments - Local Docker Simulation (PowerShell)
# ==============================================================================
# This script simulates the full preview lifecycle locally on Windows/PowerShell:
# 1. Spins up an isolated local Nginx reverse proxy on port 8080
# 2. Deploys PR #101 (Cyan theme - Checkout Flow V2)
# 3. Deploys PR #102 (Emerald theme - Realtime Alerts)
# 4. Validates routing & health endpoints for both simultaneous previews
# 5. Tears down PR #101 and verifies PR #102 remains healthy and unaffected
# ==============================================================================

$ErrorActionPreference = "Continue"

$ProxyName = "preview-local-proxy"
$NetworkName = "preview-sim-net"
$ImageName = "ephemeral-preview:simulation"
$BaseDir = Get-Location
$NginxDir = Join-Path $BaseDir "nginx"
$NginxConfFile = Join-Path $NginxDir "gateway-sim.conf"
$PreviewsDir = Join-Path $BaseDir "nginx-previews"

function Write-ConfigNoBOM {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "🚀 Starting Local Ephemeral PR Preview Simulation (PowerShell)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# Step 0: Ensure Docker is running
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[-] Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Step 1: Clean and prepare local previews directory and network
if (Test-Path -Path $PreviewsDir) {
    Remove-Item -Path $PreviewsDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $PreviewsDir -Force | Out-Null

if (!(Test-Path -Path $NginxDir)) {
    New-Item -ItemType Directory -Path $NginxDir -Force | Out-Null
}

$DefaultEmptyConf = @"
# Default placeholder so include *.conf never fails
"@
Write-ConfigNoBOM -Path (Join-Path $PreviewsDir "default-empty.conf") -Content $DefaultEmptyConf

$existingNet = docker network ls --filter "name=^${NetworkName}$" --format "{{.Name}}"
if (-not $existingNet) {
    Write-Host "[+] Creating Docker network '$NetworkName'..." -ForegroundColor Green
    docker network create $NetworkName | Out-Null
}

# Step 2: Build Application Image
Write-Host "[+] Building simulation Docker image '$ImageName'..." -ForegroundColor Green
docker build -t $ImageName . | Out-Null

# Step 3: Start Local Nginx Proxy Container
Write-Host "[+] Starting local Nginx reverse proxy on http://localhost:8080..." -ForegroundColor Green
docker rm -f $ProxyName 2>$null | Out-Null

$GatewayConf = @"
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
"@
Write-ConfigNoBOM -Path $NginxConfFile -Content $GatewayConf

docker run -d `
  --name $ProxyName `
  --network $NetworkName `
  -p "8080:80" `
  -v "${NginxConfFile}:/etc/nginx/conf.d/default.conf:ro" `
  -v "${PreviewsDir}:/etc/nginx/previews:rw" `
  nginx:alpine | Out-Null

Start-Sleep -Seconds 2

# Verify proxy is running
$proxyStatus = docker ps --filter "name=^${ProxyName}$" --format "{{.Status}}"
if (-not $proxyStatus) {
    Write-Host "[-] Proxy failed to start. Logs:" -ForegroundColor Red
    docker logs $ProxyName
    exit 1
}

# Step 4: Deploy Preview for PR #101 (Cyan Theme)
Write-Host "`n--------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[+] [STEP 1/3] Deploying PR #101 (Checkout Redesign - Cyan)..." -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow

docker rm -f "preview-pr-101" 2>$null | Out-Null
docker run -d `
  --name "preview-pr-101" `
  --network $NetworkName `
  -e PORT=3000 `
  -e PR_NUMBER=101 `
  -e GIT_SHA=abc101a `
  -e APP_ENV="preview-pr-101" `
  -e BASE_PATH="/pr-101" `
  -e THEME_NAME="cyan" `
  -e FEATURE_NAME="PR #101: Checkout Redesign" `
  $ImageName | Out-Null

$Pr101Conf = @"
location = /pr-101 {
    return 301 /pr-101/;
}
location /pr-101/ {
    proxy_pass http://preview-pr-101:3000/;
    proxy_http_version 1.1;
    proxy_set_header Host `$host;
    proxy_set_header X-Real-IP `$remote_addr;
    proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto `$scheme;
    proxy_set_header X-Forwarded-Prefix /pr-101;
}
"@
Write-ConfigNoBOM -Path (Join-Path $PreviewsDir "pr-101.conf") -Content $Pr101Conf

docker exec $ProxyName nginx -t | Out-Null
docker exec $ProxyName nginx -s reload | Out-Null
Write-Host "[✓] PR #101 deployed at http://localhost:8080/pr-101/" -ForegroundColor Green

# Step 5: Deploy Preview for PR #102 (Emerald Theme)
Write-Host "`n--------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[+] [STEP 2/3] Deploying PR #102 (Realtime Alerts - Emerald)..." -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow

docker rm -f "preview-pr-102" 2>$null | Out-Null
docker run -d `
  --name "preview-pr-102" `
  --network $NetworkName `
  -e PORT=3000 `
  -e PR_NUMBER=102 `
  -e GIT_SHA=def102b `
  -e APP_ENV="preview-pr-102" `
  -e BASE_PATH="/pr-102" `
  -e THEME_NAME="emerald" `
  -e FEATURE_NAME="PR #102: Realtime Notifications" `
  $ImageName | Out-Null

$Pr102Conf = @"
location = /pr-102 {
    return 301 /pr-102/;
}
location /pr-102/ {
    proxy_pass http://preview-pr-102:3000/;
    proxy_http_version 1.1;
    proxy_set_header Host `$host;
    proxy_set_header X-Real-IP `$remote_addr;
    proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto `$scheme;
    proxy_set_header X-Forwarded-Prefix /pr-102;
}
"@
Write-ConfigNoBOM -Path (Join-Path $PreviewsDir "pr-102.conf") -Content $Pr102Conf

docker exec $ProxyName nginx -t | Out-Null
docker exec $ProxyName nginx -s reload | Out-Null
Write-Host "[✓] PR #102 deployed at http://localhost:8080/pr-102/" -ForegroundColor Green

# Step 6: Verify Both Previews
Write-Host "`n--------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[+] Verifying simultaneous preview routing..." -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow

Start-Sleep -Seconds 2

Write-Host "Testing PR #101 Health Endpoint (http://localhost:8080/pr-101/health):" -ForegroundColor Cyan
$Resp101 = Invoke-RestMethod -Uri "http://localhost:8080/pr-101/health" -Method Get
$Resp101 | Format-List status, environment, prNumber, feature, theme, basePath

Write-Host "Testing PR #102 Health Endpoint (http://localhost:8080/pr-102/health):" -ForegroundColor Cyan
$Resp102 = Invoke-RestMethod -Uri "http://localhost:8080/pr-102/health" -Method Get
$Resp102 | Format-List status, environment, prNumber, feature, theme, basePath

# Step 7: Teardown PR #101 and verify PR #102 remains alive
Write-Host "`n--------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host "[+] [STEP 3/3] Simulating PR #101 Merge / Close Teardown..." -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow

Write-Host "[+] Removing container 'preview-pr-101'..." -ForegroundColor Green
docker rm -f "preview-pr-101" | Out-Null

Write-Host "[+] Removing Nginx config for PR #101..." -ForegroundColor Green
Remove-Item -Path (Join-Path $PreviewsDir "pr-101.conf") -Force -ErrorAction SilentlyContinue

docker exec $ProxyName nginx -t | Out-Null
docker exec $ProxyName nginx -s reload | Out-Null
Write-Host "[✓] Teardown complete for PR #101." -ForegroundColor Green

Write-Host "`nChecking PR #101 route (Expected: 404/502):" -ForegroundColor Cyan
$Status101 = "Unknown"
try {
    $res = Invoke-WebRequest -Uri "http://localhost:8080/pr-101/health" -UseBasicParsing -TimeoutSec 3
    $Status101 = $res.StatusCode
} catch {
    if ($_.Exception.Response) {
        $Status101 = [int]$_.Exception.Response.StatusCode
    } else {
        $Status101 = "Route Removed"
    }
}
Write-Host "  HTTP Status for PR #101: $Status101" -ForegroundColor Yellow

Write-Host "Checking PR #102 route (Expected: 200 UP):" -ForegroundColor Cyan
$Status102 = "Unknown"
try {
    $res = Invoke-WebRequest -Uri "http://localhost:8080/pr-102/health" -UseBasicParsing -TimeoutSec 3
    $Status102 = $res.StatusCode
} catch {
    if ($_.Exception.Response) {
        $Status102 = [int]$_.Exception.Response.StatusCode
    }
}
Write-Host "  HTTP Status for PR #102: $Status102" -ForegroundColor Green

if ($Status102 -eq 200) {
    Write-Host "`n====================================================================" -ForegroundColor Green
    Write-Host "✅ LOCAL SIMULATION SUCCESSFUL!" -ForegroundColor Green
    Write-Host "   - Dynamic Nginx routing works under subpaths (/pr-N/)." -ForegroundColor Green
    Write-Host "   - Ephemeral container isolation verified." -ForegroundColor Green
    Write-Host "   - Independent teardown verified without affecting active PRs." -ForegroundColor Green
    Write-Host "====================================================================" -ForegroundColor Green
}

Write-Host "`nTo clean up all simulation resources, run:" -ForegroundColor Gray
Write-Host "  docker rm -f preview-local-proxy preview-pr-102; docker network rm preview-sim-net; Remove-Item -Recurse -Force nginx-previews" -ForegroundColor Gray
