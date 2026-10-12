# 🎬 Live Demonstration Guide: Ephemeral PR Preview Environments

This guide provides the exact demonstration script to showcase the project to an examiner, professor, or technical team.

---

## 🎯 Demonstration Objective

Demonstrate that two concurrent Pull Requests (PR #1 and PR #2) can be deployed to the same host simultaneously, routed dynamically under isolated URL paths (`/pr-1/` and `/pr-2/`), and that closing one PR destroys only its container and route without affecting the other.

---

## 📋 Demonstration Summary Table

| Environment | Branch Name | Theme | Host Port | Routing Path | Container Name |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Preview 1** | `feature/cyan-ui` | Cyan | `30001` | `http://<EC2_IP>/pr-1/` | `preview-pr-1` |
| **Preview 2** | `feature/emerald-theme` | Emerald | `30002` | `http://<EC2_IP>/pr-2/` | `preview-pr-2` |

---

## 🚀 Scenario A: Cloud Demonstration on AWS EC2

### Step 1: Initialize Git Repository and Push Main
```bash
git init
git checkout -b main
git add .
git commit -m "feat: initial commit with ephemeral preview system"
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

### Step 2: Create PR #1 (Feature Cyan)
```bash
# 1. Create and switch to new branch
git checkout -b feature/cyan-ui

# 2. Modify app feature name in package.json or server.js
# For quick demo: edit package.json description or server.js
git commit --allow-empty -m "feat(ui): implement modern cyan redesign for PR 1"
git push -u origin feature/cyan-ui
```
1. Open GitHub in your browser and click **Compare & pull request**.
2. Set title: `feat: Modern Cyan Redesign (PR #1)`.
3. Click **Create pull request**.

#### What to Show in GitHub Actions:
- Point out the `ci-test-and-validate` job running tests and Docker build.
- Point out the `deploy-preview` job executing `scripts/deploy.sh` over SSH.
- Show the automated bot comment posted on the PR with the live link: `http://<EC2_IP>/pr-1/`.

---

### Step 3: Create PR #2 (Feature Emerald)
```bash
# 1. Return to main and branch out
git checkout main
git checkout -b feature/emerald-theme

# 2. Commit a second feature
git commit --allow-empty -m "feat(alerts): add emerald theme with realtime notifications for PR 2"
git push -u origin feature/emerald-theme
```
1. Go to GitHub and open a pull request for `feature/emerald-theme`.
2. Title: `feat: Emerald Theme & Realtime Alerts (PR #2)`.
3. GitHub Actions deploys PR #2 in parallel.
4. Bot posts preview link: `http://<EC2_IP>/pr-2/`.

---

### Step 4: Live Verification of Co-Existing Environments

#### 1. Open Both URLs in Browser Tabs:
- **Tab 1**: `http://<EC2_IP>/pr-1/`
  - Displays: **PR #1**, **Theme: cyan**, Container `preview-pr-1`, Port `30001`.
  - Click **Ping /health**: Live JSON response shows `status: "UP"`, `prNumber: 1`.
- **Tab 2**: `http://<EC2_IP>/pr-2/`
  - Displays: **PR #2**, **Theme: emerald**, Container `preview-pr-2`, Port `30002`.
  - Click **Ping /health**: Live JSON response shows `status: "UP"`, `prNumber: 2`.

#### 2. Inspect Host Over SSH:
Open a terminal and run on the EC2 host:
```bash
# Verify both containers are running in isolation
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
**Expected Output:**
```
NAMES            STATUS         PORTS
preview-pr-2     Up 2 minutes   127.0.0.1:30002->3000/tcp
preview-pr-1     Up 4 minutes   127.0.0.1:30001->3000/tcp
```

Inspect Nginx dynamic configuration directory:
```bash
ls -la /etc/nginx/previews/
```
**Expected Output:**
```
default-empty.conf
pr-1.conf
pr-2.conf
```

---

### Step 5: Automated Teardown Demonstration

1. Go to GitHub PR #1 and click **Close pull request** (or **Merge pull request**).
2. Within seconds, the GitHub Actions `teardown-preview` job triggers.
3. Show the GitHub Actions log:
   - `docker rm -f preview-pr-1`
   - `rm -f /etc/nginx/previews/pr-1.conf`
   - `sudo nginx -t && sudo nginx -s reload`
4. Show the bot comment confirming teardown: `🛑 Ephemeral Preview Environment Decommissioned`.

#### Verification on Host & Browser:
- Refresh `http://<EC2_IP>/pr-1/` -> Returns **404 Not Found** (Route purged).
- Refresh `http://<EC2_IP>/pr-2/` -> **Still 100% active and healthy!**
- Run `docker ps` on EC2:
  ```
  NAMES            STATUS         PORTS
  preview-pr-2     Up 6 minutes   127.0.0.1:30002->3000/tcp
  ```
  *(Only `preview-pr-2` remains. Zero resource leak!)*

---

## 💻 Scenario B: 60-Second Offline Local Simulation

If presenting on a laptop without internet or AWS access, execute the automated simulation script:

### On Windows PowerShell:
```powershell
.\scripts\local-simulate-preview.ps1
```

### On Linux / macOS / Git Bash:
```bash
./scripts/local-simulate-preview.sh
```

### What to Walk Through During the Execution:
1. **Container Spin-Up**: Point to terminal logs showing `preview-pr-101` and `preview-pr-102` spinning up simultaneously.
2. **Dynamic Nginx Reload**: Highlight `nginx -t` validation and `nginx -s reload` without restarting the Nginx daemon.
3. **Endpoint Verification**: Point to the health output showing PR 101 returning `theme: cyan` and PR 102 returning `theme: emerald`.
4. **Teardown**: Point to step 3 where PR 101 is removed, and notice:
   - `HTTP Status for PR #101: 404 (Route Removed)`
   - `HTTP Status for PR #102: 200 (Active & Healthy)`
5. Conclude: *"This confirms that dynamic preview provisioning and teardown are completely isolated, atomic, and idempotent."*
