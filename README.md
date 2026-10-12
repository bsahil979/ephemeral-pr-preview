# Ephemeral PR Preview Environments

[![CI Test & Validate](https://github.com/your-username/labca_devops/actions/workflows/preview-environments.yml/badge.svg)](https://github.com/your-username/labca_devops/actions)
![Node.js Version](https://img.shields.io/badge/Node.js-22%20LTS-brightgreen)
![Docker](https://img.shields.io/badge/Docker-Multi--Stage-blue)
![Nginx](https://img.shields.io/badge/Nginx-Dynamic%20Reverse%20Proxy-green)
![Host](https://img.shields.io/badge/Host-Ubuntu%2024.04%20EC2-orange)

> **College DevOps Mini-Project**: Automated Git-Push-to-Live-Preview Deployment and Teardown Using GitHub Actions, Docker, and Dynamic Nginx Reverse Proxy Routing.

---

## 📌 Executive Summary

Modern software development requires rapid verification of frontend and API changes before merging pull requests to `main`. Traditional staging environments create testing bottlenecks and configuration drift. 

This project implements **Ephemeral PR Preview Environments** on a single Ubuntu 24.04 EC2 host without requiring Kubernetes, paid domain names, or wildcard DNS:
- **Automatic Spin-Up**: Every opened or updated Pull Request automatically builds, tests, and deploys an isolated Docker container (`preview-pr-N`).
- **Dynamic Path-Based Routing**: Host Nginx automatically provisions `/pr-N/` routing snippets pointing to `127.0.0.1:30000+N`.
- **Zero Route Collisions**: Atomic Nginx configuration files with `nginx -t` pre-validation prevent invalid routes from affecting other running previews.
- **Automated Resource Reclaim**: Merging or closing a PR triggers an immediate teardown workflow that removes the container, purges the Nginx route, and reclaims memory.

---

## 🏛️ System Architecture

```mermaid
flowchart TD
    subgraph Developer [Developer Workflow]
        Dev[Developer Workstation] -->|git push| GH[GitHub Repository]
        GH -->|pull_request opened/sync| GHA[GitHub Actions Runner]
    end

    subgraph CI [Continuous Integration]
        GHA -->|npm test| Test[Automated Unit & HTTP Tests]
        Test -->|docker build| Build[Multi-Stage Dockerfile Validation]
    end

    subgraph Security [Security Trust Boundary]
        Build -->|Check Same-Repo| Trust{Is Trusted Branch?}
        Trust -->|Fork PR| ForkSkip[Run Tests Only - No Deploy Secrets]
        Trust -->|Same Repo| SSH[Authenticate via SSH Key]
    end

    subgraph Host [Ubuntu 24.04 EC2 Docker Host]
        SSH -->|scripts/deploy.sh| DeployHost[Host Orchestrator]
        DeployHost -->|Run Container| C1["preview-pr-1 (Port 30001)"]
        DeployHost -->|Run Container| C2["preview-pr-2 (Port 30002)"]
        DeployHost -->|Generate Snippet| Conf["/etc/nginx/previews/pr-N.conf"]
        Conf -->|nginx -t & reload| Nginx["Nginx Reverse Proxy (:80)"]
    end

    subgraph Reviewers [Code Reviewers & Stakeholders]
        Browser[Web Browser / QA] -->|http://SERVER_IP/pr-1/| Nginx
        Browser -->|http://SERVER_IP/pr-2/| Nginx
        Nginx -->|proxy_pass| C1
        Nginx -->|proxy_pass| C2
    end
```

---

## 🛠️ Technology Stack

| Layer | Technology | Rationale |
| :--- | :--- | :--- |
| **Runtime** | Node.js 22 LTS | High-performance async I/O, native `fetch`, native `node:test` runner. |
| **Backend** | Express 4.x | Lightweight HTTP routing, robust subpath prefix middleware support. |
| **Containerization** | Docker (Alpine) | Multi-stage build producing minimal production footprint (<150MB). |
| **Reverse Proxy** | Nginx | High-performance reverse proxy with dynamic wildcard configuration includes. |
| **CI/CD** | GitHub Actions | Native pull request event triggers, automated PR commenting, secrets management. |
| **Cloud Host** | Ubuntu 24.04 LTS (EC2) | Predictable, stable cloud Linux kernel with systemd and least-privilege users. |

---

## 🚀 Quickstart: Local Demonstration (No AWS Required)

You can run the complete preview lifecycle locally in seconds using Docker:

### On Windows (PowerShell)
```powershell
.\scripts\local-simulate-preview.ps1
```

### On Linux / macOS / Git Bash
```bash
chmod +x scripts/*.sh
./scripts/local-simulate-preview.sh
```

### What the Simulation Does:
1. Spawns an isolated Nginx reverse proxy listening on `http://localhost:8080`.
2. Deploys **PR #101** with the **Cyan Theme** and routes `http://localhost:8080/pr-101/`.
3. Deploys **PR #102** with the **Emerald Theme** and routes `http://localhost:8080/pr-102/`.
4. Executes live curl queries to verify both health endpoints (`/pr-101/health` and `/pr-102/health`).
5. Simulates closing PR #101: removes container, deletes config, reloads Nginx, and proves PR #102 remains unaffected.

---

## 📦 Local Development & Tests

```bash
# Install dependencies
npm install

# Run automated tests
npm test

# Run tests with verbose reporter
npm run test:verbose

# Start application locally (defaults to port 3000)
npm start
```

---

## ☁️ EC2 Host Setup & Production Deployment

### 1. Provision Ubuntu 24.04 EC2 Instance
- **Instance Type**: `t3.small` or `t3.micro`
- **OS**: Ubuntu Server 24.04 LTS (64-bit x86)
- **Security Group Inbound Rules**:
  - `Port 22 (SSH)`: Your IP or GitHub Actions IP range
  - `Port 80 (HTTP)`: `0.0.0.0/0` (For reviewers to access preview URLs)

### 2. Run Host Bootstrap
SSH into your EC2 instance and run the bootstrap script:
```bash
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>
sudo chmod +x scripts/*.sh
sudo ./scripts/bootstrap-ubuntu.sh
```

### 3. Configure GitHub Repository Secrets
Navigate to **GitHub Repository** -> **Settings** -> **Secrets and variables** -> **Actions** -> **New repository secret**:

| Secret Name | Value | Purpose |
| :--- | :--- | :--- |
| `EC2_HOST` | `54.xxx.xxx.xxx` | Public IPv4 address or Elastic IP of the EC2 instance. |
| `EC2_USER` | `ubuntu` | Non-root deployment user. |
| `SSH_PRIVATE_KEY` | `-----BEGIN RSA PRIVATE KEY-----...` | Private key matching EC2's `~/.ssh/authorized_keys`. |
| `EC2_PORT` | `22` *(Optional)* | SSH port (defaults to 22 if omitted). |

---

## 🔒 Security Architecture & Trust Boundary

1. **No Dangerous Docker Socket Exposure**: The Docker daemon TCP socket (`2375`) is never exposed over the network. All container actions run through an authenticated SSH tunnel.
2. **Least Privilege on Host**: The deploy user belongs to the `docker` group and has passwordless sudo restricted exclusively to `/usr/sbin/nginx -t` and `/usr/sbin/nginx -s reload`.
3. **Trust Boundary Isolation**: GitHub Actions uses standard `pull_request` triggers (never insecure `pull_request_target`). Forked pull requests cannot access repository secrets; they run tests and Docker validations inside the runner, skipping the deployment stage.
4. **Deterministic Localhost Binding**: Preview containers bind strictly to `127.0.0.1:${PORT}`, meaning internal ports are never reachable from the public internet without passing through Nginx.

---

## 📂 Project Structure

```
.
├── .github/
│   └── workflows/
│       └── preview-environments.yml  # GitHub Actions CI/CD Pipeline
├── nginx/
│   ├── default-server.conf           # Base host Nginx server block
│   └── nginx-compose.conf            # Docker-compose local proxy config
├── scripts/
│   ├── bootstrap-ubuntu.sh           # EC2 Host provisioning script
│   ├── deploy.sh                     # Idempotent preview deployment script
│   ├── teardown.sh                   # Idempotent preview teardown script
│   ├── local-simulate-preview.sh     # Bash local Docker/Nginx simulator
│   └── local-simulate-preview.ps1    # PowerShell local Docker/Nginx simulator
├── src/
│   ├── public/
│   │   ├── app.js                    # Interactive health check client script
│   │   ├── index.html                # Responsive preview landing UI template
│   │   └── style.css                 # Theme-aware responsive stylesheet
│   └── server.js                     # Express application & /health endpoint
├── tests/
│   └── server.test.js                # Integration tests for server & endpoints
├── Dockerfile                        # Multi-stage production container build
├── docker-compose.yml                # Multi-container local preview setup
├── package.json                      # Node.js dependencies & scripts
├── DEMO.md                           # Step-by-step presentation walkthrough
└── TROUBLESHOOTING.md                # Debugging guide & College Viva Q&A
```
