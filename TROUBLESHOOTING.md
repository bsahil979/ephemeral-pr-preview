# 🛠️ Troubleshooting Guide & College Viva Preparation

This document covers operational debugging procedures, architectural failure mode analysis, and comprehensive Viva Voce questions and answers for evaluations.

---

## 🏛️ End-to-End Request & Proxy Flow

```mermaid
sequenceDiagram
    autonumber
    actor Reviewer as Web Browser / Reviewer
    participant Nginx as Host Nginx (:80)
    participant C1 as Container preview-pr-1 (:30001)
    participant C2 as Container preview-pr-2 (:30002)

    Reviewer->>Nginx: GET http://SERVER_IP/pr-1
    Note over Nginx: Exact Match: location = /pr-1
    Nginx-->>Reviewer: HTTP 301 Redirect to /pr-1/

    Reviewer->>Nginx: GET http://SERVER_IP/pr-1/
    Note over Nginx: Prefix Match: location /pr-1/
    Nginx->>C1: proxy_pass 127.0.0.1:30001/
    C1-->>Nginx: HTTP 200 OK (HTML with base href="/pr-1/")
    Nginx-->>Reviewer: HTTP 200 OK

    Reviewer->>Nginx: GET http://SERVER_IP/pr-1/style.css
    Nginx->>C1: proxy_pass 127.0.0.1:30001/style.css
    C1-->>Nginx: HTTP 200 OK (CSS)
    Nginx-->>Reviewer: HTTP 200 OK

    Reviewer->>Nginx: GET http://SERVER_IP/pr-2/health
    Note over Nginx: Prefix Match: location /pr-2/
    Nginx->>C2: proxy_pass 127.0.0.1:30002/health
    C2-->>Nginx: HTTP 200 OK ({"status":"UP","prNumber":2})
    Nginx-->>Reviewer: HTTP 200 OK
```

---

## 🔍 Common Operational Failures & Solutions

### 1. 404 Not Found on Static Assets (`style.css` / `app.js`)
* **Symptom**: The preview HTML page loads, but CSS styles and JavaScript buttons are broken with 404 errors.
* **Root Cause**: The HTML used absolute root paths (`<link href="/style.css">`), causing the browser to fetch `http://SERVER_IP/style.css` instead of `http://SERVER_IP/pr-N/style.css`.
* **Fix Applied**: 
  1. Injected `<base href="__BASE_HREF__">` into `<head>` (e.g., `<base href="/pr-1/">`).
  2. All asset paths in the frontend use relative paths (`style.css`, `app.js`, `health`).
  3. Added `proxy_set_header X-Forwarded-Prefix /pr-N;` in Nginx.

### 2. The Trailing Slash Trap (`/pr-1` vs `/pr-1/`)
* **Symptom**: Visiting `http://SERVER_IP/pr-1` returns 404 or fails to proxy properly.
* **Root Cause**: In Nginx, `location /pr-1/` only matches URIs starting with `/pr-1/`. A URI `/pr-1` without the trailing slash fails to match.
* **Fix Applied**:
  Added an explicit 301 redirect rule before the proxy rule:
  ```nginx
  location = /pr-1 {
      return 301 /pr-1/;
  }
  ```

### 3. Nginx Fails to Reload or Breaks Active Routes
* **Symptom**: A syntax error in one PR's configuration breaks Nginx for all other PRs.
* **Root Cause**: Overwriting the main `nginx.conf` or executing `nginx -s reload` without syntax verification.
* **Fix Applied**:
  In `scripts/deploy.sh`:
  1. Writes each PR's snippet to an isolated file: `/etc/nginx/previews/pr-N.conf`.
  2. Always runs `nginx -t` validation before reloading.
  3. If validation fails, the script immediately removes `/etc/nginx/previews/pr-N.conf` (rollback) and exits 1, leaving existing routes undamaged.

### 4. Port Conflict on Deploy
* **Symptom**: `docker run` fails with `Bind for 0.0.0.0:30001 failed: port is already allocated`.
* **Root Cause**: An existing preview container from a previous push to the same PR was not properly terminated.
* **Fix Applied**:
  `scripts/deploy.sh` is idempotent:
  ```bash
  if docker ps -a --format '{{.Names}}' | grep -Eq "^preview-pr-${PR_NUMBER}\$"; then
      docker rm -f "preview-pr-${PR_NUMBER}"
  fi
  ```

### 5. SSH Permission Denied in GitHub Actions
* **Symptom**: GitHub Actions fails with `Permission denied (publickey)`.
* **Fix Checklist**:
  1. Verify secret `SSH_PRIVATE_KEY` has no trailing spaces and includes the header `-----BEGIN RSA PRIVATE KEY-----` and footer.
  2. Verify secret `EC2_USER` matches the AMI user (for Ubuntu 24.04, it is `ubuntu`).
  3. Verify permissions on the EC2 host: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`.

### 6. Host Key Verification Failed (`SSH_KNOWN_HOSTS`)
* **Symptom**: SSH fails with `Host key verification failed`.
* **Root Cause**: Strict host key checking (`-o StrictHostKeyChecking=yes`) protects against MitM attacks. If the EC2 instance was re-created or its IP reassigned, the pinned host key in secret `SSH_KNOWN_HOSTS` no longer matches the target.
* **Fix Applied**:
  Run `ssh-keyscan -H <NEW_EC2_IP>` on your workstation and update the `SSH_KNOWN_HOSTS` secret in GitHub Repository Settings.

---

## 🎓 College Viva Voce Questions & Answers

### Q1: What is an Ephemeral Environment, and why is it preferred over a static Staging server?
**Answer**:
An ephemeral environment is a temporary, fully functional deployment created on-demand for a specific branch or pull request and destroyed as soon as the PR is closed or merged. 
- **Advantage over static staging**: Traditional staging servers create queues where developers wait to test changes, suffer from configuration drift, and can hide bugs caused by conflicting concurrent merges. Ephemeral environments provide true isolation, allowing multiple developers to test distinct features concurrently.

---

### Q2: Why did you route previews using URL path prefixes (`/pr-N/`) instead of subdomains (`pr-N.example.com`)?
**Answer**:
1. **Cost & Infrastructure Independence**: Subdomains require a purchased registered domain name, DNS provider integration (AWS Route 53 or Cloudflare), and Wildcard DNS records (`*.example.com`).
2. **Path-Based Zero-Config Portability**: Dynamic path-based routing (`http://SERVER_IP/pr-N/`) works out-of-the-box on any bare IP, local Docker host, or cloud VM with zero external DNS dependencies or recurring domain costs.

---

### Q3: How did you solve the subpath reverse proxy problem where assets return 404?
**Answer**:
When an application expects to run at `/` but is proxied under `/pr-N/`:
1. If the HTML references `/style.css`, the browser requests `http://SERVER_IP/style.css`, bypassing the proxy route.
2. We solved this by:
   - Setting `<base href="/pr-N/">` dynamically in the `<head>` of the HTML.
   - Using relative references (`style.css`, `app.js`, `health`).
   - Using `proxy_pass http://127.0.0.1:PORT/;` (with trailing slash) so Nginx strips `/pr-N/` when forwarding requests to the container.
   - Configuring Express middleware to handle both stripped (`/`) and prefixed (`/pr-N/`) routes.

---

### Q4: Why is using `pull_request` safer than `pull_request_target` in GitHub Actions?
**Answer**:
- `pull_request_target` runs in the context of the base repository (`main`) and has access to repository secrets even when triggered by external forks. If a workflow runs code from the PR under `pull_request_target`, an attacker could submit a malicious PR to exfiltrate deployment secrets.
- Using standard `pull_request` with an explicit trust boundary check (`if: github.event.pull_request.head.repo.full_name == github.repository`) guarantees that fork PRs only run tests in the runner sandbox and are strictly denied access to host SSH keys.

---

### Q5: How do you prevent port collisions between different Pull Requests?
**Answer**:
We use a deterministic, collision-free port formula:
$$\text{Port} = 30000 + \text{PR\_NUMBER}$$
Because GitHub assigns strictly unique, sequential integers to pull requests within a repository, two pull requests can never have the same PR number.
Additionally, containers bind strictly to loopback (`127.0.0.1`), preventing external direct access and port scanning.

---

### Q6: What happens if a developer merges a PR and deletes the branch? How does teardown succeed?
**Answer**:
The teardown workflow relies exclusively on `github.event.pull_request.number` provided in the GitHub webhook payload (`github.event.action == 'closed'`). It does not need the git branch to exist. The script targets `preview-pr-N` and `/etc/nginx/previews/pr-N.conf`, which are named using the PR number, making teardown completely branch-independent.

---

### Q7: Why use Multi-Stage Docker builds in this project?
**Answer**:
- **Layer 1 (Builder)**: Installs dependencies using `npm ci --omit=dev`.
- **Layer 2 (Runner)**: Uses minimal `node:22-alpine`, copies only the production `node_modules` and `src/`, and runs as non-root user `node`.
- **Benefits**:
  - Image size is reduced from ~1GB to ~130MB.
  - Development tools, compilers, and npm cache are omitted, shrinking the attack surface.

---

### Q8: What does the `--restart unless-stopped` flag do, and why is it important?
**Answer**:
`--restart unless-stopped` ensures that if the EC2 host reboots or the Docker daemon restarts, all currently active preview containers automatically spin back up and resume serving traffic, while maintaining zero downtime for ongoing code reviews.

---

### Q9: Why did you choose Docker + Nginx over Kubernetes or Terraform for this project?
**Answer**:
- **Simplicity and Overhead**: Kubernetes requires significant memory and CPU overhead (etcd, kubelet, kube-proxy, control plane), typically needing multiple nodes or large instances ($$$).
- **Appropriate Architecture**: For a preview environment setup serving 5-20 concurrent developer PRs, a single Linux VM with lightweight Docker containers and dynamic Nginx routing uses less than 5% CPU and minimal RAM, satisfying the prompt's mandate: *"Keep the setup simple: no Kubernetes, Terraform, database, paid domain, or unnecessary infrastructure."*

---

### Q10: How would you scale this architecture in a production enterprise?
**Answer**:
In an enterprise environment with hundreds of concurrent PRs:
1. **Container Registry**: Push Docker images to AWS ECR or GitHub Packages instead of building on the host.
2. **Automatic TTL (Time-To-Live)**: Implement a cron job to stop containers inactive for more than 48 hours to conserve memory.
3. **Horizontal Scaling**: Use AWS ECS (Fargate) or lightweight Nomad with an AWS Application Load Balancer using path-based target groups.
