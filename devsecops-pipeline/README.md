# 🔒 DevSecOps Pipeline

> **Security scanning integrated into CI/CD — Snyk + Trivy + tfsec + OWASP ZAP on GitHub Actions**
> A portfolio-ready DevSecOps project demonstrating automated security at every stage of delivery.

[![DevSecOps Pipeline](https://github.com/Iamoamen/devsecops-pipeline/actions/workflows/devsecops-pipeline.yml/badge.svg)](https://github.com/Iamoamen/devsecops-pipeline/actions)
[![Security](https://img.shields.io/badge/Security-DevSecOps-red?logo=shield)](https://github.com/Iamoamen/devsecops-pipeline/security)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📋 Table of Contents

- [Architecture](#architecture)
- [Pipeline Stages](#pipeline-stages)
- [Tools Used and Why](#tools-used-and-why)
- [Quick Start](#quick-start)
- [Setting Up Secrets](#setting-up-secrets)
- [How Security Gates Work](#how-security-gates-work)
- [Before / After Demo](#before--after-demo)
- [Branch Protection](#branch-protection)
- [Dependabot](#dependabot)
- [Running Locally](#running-locally)
- [Troubleshooting](#troubleshooting)
- [What I Learned](#what-i-learned)
- [Production Improvements](#production-improvements)

---

## Architecture

```
Developer pushes code / opens PR
              │
              ▼
    ┌─────────────────┐
    │  GitHub Actions │
    │  Pipeline       │
    └────────┬────────┘
             │
    ┌────────▼────────────────────────────────────────┐
    │                                                  │
    │  ①  BUILD          ②  TEST                      │
    │  Docker image      Unit tests + coverage         │
    │  → push to GHCR   → Jest                        │
    │                                                  │
    └─────────────────────────┬────────────────────────┘
                              │ (parallel)
          ┌───────────────────┼──────────────────┐
          │                   │                  │
    ┌─────▼──────┐    ┌───────▼──────┐   ┌──────▼──────┐
    │ ③ SAST     │    │ ④ CONTAINER  │   │ ⑤ IaC SCAN  │
    │            │    │    SCAN      │   │             │
    │ Snyk       │    │              │   │ tfsec       │
    │ (deps)     │    │ Trivy        │   │ (Terraform) │
    │            │    │ Snyk         │   │             │
    │ → SARIF    │    │ Scout        │   │ → SARIF     │
    │ → Sec tab  │    │ → SARIF      │   │ → PR annot. │
    └─────┬──────┘    └───────┬──────┘   └──────┬──────┘
          │                   │                  │
          └───────────────────┼──────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  ⑥ DAST           │
                    │  OWASP ZAP        │
                    │  (live HTTP scan) │
                    │  → HTML report    │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  ⑦ SECURITY       │
                    │     REPORT        │
                    │  Aggregate all    │
                    │  → PR comment     │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  ⑧ SECURITY GATE  │
                    │                   │
                    │  CRITICAL found?  │
                    │  ❌ Block merge   │
                    │  ✅ Allow merge   │
                    └───────────────────┘
```

### PR Security Comment (auto-posted)

```
🔒 DevSecOps Security Scan Report

Pipeline Status
| Stage          | Tool      | Status  |
|----------------|-----------|---------|
| SAST           | Snyk      | ✅ success |
| Container Scan | Trivy     | ✅ success |
| IaC Scan       | tfsec     | ✅ success |
| DAST           | OWASP ZAP | ✅ success |

Container Vulnerabilities (Trivy)
| Severity   | Count | Gate       |
|------------|-------|------------|
| 🔴 Critical | 0     | ✅ PASS    |
| 🟠 High     | 2     | ✅ PASS    |
| 🟡 Medium   | 5     | ℹ️ INFO   |

✅ SECURITY GATE PASSED — Safe to merge
```

---

## Pipeline Stages

### ① Build
Creates a hardened Docker image using multi-stage builds:
- Stage 1 installs dependencies
- Stage 2 is the minimal production image (Alpine, non-root user, read-only packages)
- Image is pushed to GitHub Container Registry (GHCR)

### ② Test
Runs Jest unit tests with coverage reporting. Coverage artifacts are uploaded for review.

### ③ SAST — Static Application Security Testing
**Tool: Snyk**

Snyk scans your `package.json` and the entire dependency tree for known CVEs. It checks against the Snyk vulnerability database (updated in real-time from NVD, GitHub advisories, etc.).

- Fails the pipeline on HIGH or CRITICAL severity
- Uploads results as SARIF to GitHub Security tab (visible under repo → Security → Code scanning)

### ④ Container Scan
**Tools: Trivy + Snyk Container + Docker Scout**

Three tools scan the built Docker image for OS-level and library vulnerabilities:

- **Trivy** is the primary gate — it fails the pipeline (`--exit-code 1`) on CRITICAL findings
- **Snyk** provides additional coverage with different vulnerability sources
- **Docker Scout** adds informational context (no hard failure)

### ⑤ IaC Scan — Infrastructure as Code
**Tool: tfsec**

Scans all `.tf` files for misconfigurations before any infrastructure is provisioned:
- S3 buckets without encryption
- Security groups open to `0.0.0.0/0`
- RDS without encryption at rest
- Missing deletion protection

Results appear as **inline annotations on the PR diff** — you see the finding directly next to the vulnerable line of Terraform code.

### ⑥ DAST — Dynamic Application Security Testing
**Tool: OWASP ZAP**

Unlike SAST (which reads code), DAST actually **runs the application** and sends HTTP requests to it, looking for:
- Missing security headers
- Cross-Site Scripting (XSS) vulnerabilities
- SQL injection points
- Information disclosure
- Insecure cookies

ZAP runs a "baseline scan" (passive only — no active attacks) which is safe for CI/CD.

### ⑦ Security Report
Aggregates findings from all four tools into a single PR comment. The comment is **updated** (not re-posted) on each new commit to the PR, keeping the conversation clean.

### ⑧ Security Gate
The final job evaluates all results and makes a binary decision:
- **CRITICAL container vulnerability** → `exit 1` → PR blocked
- **HIGH SAST vulnerability** → `exit 1` → PR blocked
- IaC and DAST findings → advisory warnings (don't block, but are visible)

GitHub branch protection rules reference this job — if it fails, the merge button is greyed out.

---

## Tools Used and Why

| Tool | Category | Why this tool |
|------|----------|---------------|
| **Snyk** | SAST | Best dependency scanning, free tier generous, integrates with GitHub natively |
| **Trivy** | Container | Fast, comprehensive, supports OS + library + IaC, SARIF output |
| **tfsec** | IaC | Purpose-built for Terraform, inline PR annotations, 150+ AWS rules |
| **OWASP ZAP** | DAST | Industry standard, free, Dockerized, baseline mode safe for CI |
| **Docker Scout** | Container | New tool from Docker Inc, adds supply chain context |
| **Dependabot** | SCA | Automatic PRs for dependency updates, native GitHub integration |
| **GitHub Actions** | CI/CD | Native, no extra infrastructure, free for public repos |
| **GHCR** | Registry | Free, integrated with GitHub permissions, no DockerHub rate limits |

---

## Quick Start

```bash
# 1. Fork and clone this repo
git clone https://github.com/Iamoamen/devsecops-pipeline.git
cd devsecops-pipeline

# 2. Set up secrets (see next section)

# 3. Create a branch and open a PR
git checkout -b feature/my-change
# make a change
git commit -am "feat: my change"
git push origin feature/my-change
# Open PR → pipeline runs automatically
```

---

## Setting Up Secrets

The pipeline needs one secret configured in your GitHub repo:

### SNYK_TOKEN

1. Go to [snyk.io](https://snyk.io) → Sign up (free)
2. Click your avatar (top right) → **Account Settings**
3. Find **Auth Token** → click **"click to show"** → copy it
4. In your GitHub repo: **Settings → Secrets and variables → Actions**
5. Click **"New repository secret"**
6. Name: `SNYK_TOKEN`, Value: paste your token
7. Click **"Add secret"**

### GITHUB_TOKEN
Automatically provided by GitHub Actions. No setup required.

---

## How Security Gates Work

```
Vulnerability found
        │
        ▼
Is it CRITICAL severity?
   │              │
  YES             NO
   │              │
   ▼              ▼
Pipeline        Is it HIGH severity?
fails              │           │
(exit 1)          YES          NO
                   │           │
                   ▼           ▼
              Pipeline      Pipeline
              fails       continues
              (exit 1)    (warning only)
```

The `gate` job is what GitHub branch protection watches. Configure it under:
**Settings → Branches → Branch protection rules → Require status checks → "🚦 Security Gate"**

---

## Before / After Demo

### Before — Vulnerable State

Vulnerable dependencies are included in `app/package.vulnerable.json`:

```json
{
  "dependencies": {
    "lodash": "4.17.4",    ← CVE-2019-10744: Prototype Pollution (CRITICAL)
    "axios": "0.21.1",     ← CVE-2021-3749: ReDoS (HIGH)
    "node-fetch": "2.6.0"  ← CVE-2022-0235: Header injection (HIGH)
  }
}
```

Pipeline result:
```
❌ SAST (Snyk):      FAILED — 1 CRITICAL, 2 HIGH
❌ Container (Trivy): FAILED — CRITICAL found in image
⚠️  IaC (tfsec):     WARNING — 6 misconfigurations
🚦 Security Gate:    BLOCKED — merge prevented
```

### After — Fixed State

```json
{
  "dependencies": {
    "express": "4.18.2",   ← No known critical CVEs
    "helmet": "7.1.0",     ← Adds security headers (bonus security)
    "morgan": "1.10.0"     ← Clean
  }
}
```

Pipeline result:
```
✅ SAST (Snyk):      PASSED — 0 critical, 0 high
✅ Container (Trivy): PASSED — 0 critical
✅ IaC (tfsec):      PASSED after main.tf fixed
✅ DAST (ZAP):       PASSED — headers present (helmet)
🚦 Security Gate:    PASSED — safe to merge
```

### Run the demo locally

```bash
chmod +x scripts/demo-before-after.sh
./scripts/demo-before-after.sh
```

---

## Branch Protection

After the pipeline runs at least once:

1. **Settings → Branches → Add rule**
2. Branch name: `main`
3. Enable:
   - ✅ Require pull request before merging (1 approval)
   - ✅ Require status checks: **"🚦 Security Gate"** and **"🧪 Unit Tests"**
   - ✅ Require branches to be up to date
   - ✅ Do not allow bypassing the above settings
4. Save

Now no one — not even admins — can merge a PR with CRITICAL vulnerabilities.

---

## Dependabot

Dependabot is configured in `.github/dependabot.yml` to watch:

| Ecosystem | Directory | Schedule |
|-----------|-----------|----------|
| npm | `/app` | Weekly (Monday) |
| docker | `/` | Weekly (Monday) |
| github-actions | `/` | Weekly (Monday) |
| terraform | `/terraform` | Weekly (Tuesday) |

**How it works:**
1. Every Monday, Dependabot checks your dependencies against the latest versions
2. If it finds an outdated or vulnerable package, it opens a PR with the fix
3. Your DevSecOps pipeline runs on that PR automatically
4. Snyk and Trivy verify the fix is clean
5. You review and merge

This means security patches happen automatically without you having to manually track CVE announcements.

---

## Running Locally

### Run the app

```bash
cd app
npm install
npm start
# App running at http://localhost:3000
```

### Run tests

```bash
cd app
npm test
```

### Run the full local security scan

```bash
chmod +x scripts/local-scan.sh
./scripts/local-scan.sh
```

### Run with Docker Compose

```bash
# Start the app
docker-compose up app

# Run ZAP against it
docker-compose run zap
```

### Run individual tools manually

```bash
# Snyk dependency scan
snyk test --file=app/package.json --severity-threshold=high

# Trivy container scan
docker build -t myapp:local .
trivy image --severity CRITICAL,HIGH myapp:local

# tfsec IaC scan
tfsec terraform/ --minimum-severity HIGH

# ZAP baseline (app must be running first)
docker run --rm ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py -t http://localhost:3000 -I
```

---

## Project Structure

```
devsecops-pipeline/
├── .github/
│   ├── workflows/
│   │   └── devsecops-pipeline.yml   ← Full CI/CD + security pipeline
│   └── dependabot.yml               ← Automated dependency updates
├── .zap/
│   └── rules.tsv                    ← ZAP scan rules (pass/warn/fail)
├── app/
│   ├── src/
│   │   └── index.js                 ← Express app
│   ├── tests/
│   │   └── app.test.js              ← Jest tests
│   ├── package.json                 ← Secure dependencies
│   └── package.vulnerable.json     ← Demo: vulnerable deps (before fix)
├── terraform/
│   ├── main.tf                      ← Infra with intentional misconfigs
│   ├── main.secure.tf.reference     ← Fixed version (for reference)
│   └── variables.tf
├── security-reports/                ← Scan outputs (gitignored for local)
├── scripts/
│   ├── local-scan.sh                ← Run all scans locally
│   ├── demo-before-after.sh         ← Before/after vulnerability demo
│   └── setup-branch-protection.sh  ← Configure GitHub branch rules
├── docs/
│   └── screenshots/                 ← Add your own after running
├── docker-compose.yml               ← Local dev + ZAP scanning
├── Dockerfile                       ← Multi-stage, hardened
└── README.md
```

---

## Troubleshooting

### "SNYK_TOKEN not found" in pipeline

```
Error: SNYK_TOKEN environment variable not set
```

**Fix:** Add the secret in GitHub → Settings → Secrets and variables → Actions → New repository secret → `SNYK_TOKEN`

---

### Trivy scan takes too long

```
FATAL Fatal error init error: timeout
```

**Fix:** Increase timeout in the workflow:
```yaml
timeout: '15m'   # Change from 10m to 15m
```

---

### ZAP scan fails — "Target not reachable"

```
WARN-NEW: Failed to connect to the target
```

**Fix:** The app container didn't start in time. Increase the wait loop:
```bash
for i in $(seq 1 60); do   # 60 seconds instead of 30
```

---

### tfsec fails — "no Terraform files found"

**Fix:** Make sure the `working_directory` in the tfsec action points to where your `.tf` files are:
```yaml
working_directory: terraform/
```

---

### SARIF upload fails — "Code scanning is not available"

GitHub Code Scanning (Security tab) requires either:
- A **public** repository, OR
- GitHub Advanced Security (paid, for private repos)

**Fix for private repos:** Remove the SARIF upload steps or make the repo public. The scans still run — you just won't see them in the Security tab.

---

### Docker Scout fails — "unauthorized"

**Fix:** Scout requires authentication to GHCR. Make sure the `permissions` block includes `packages: read`.

---

## What I Learned

**1. Shift-left security is about speed, not just catching bugs.**
Running Snyk before building the Docker image means developers get feedback in 2 minutes, not after a 20-minute build. Faster feedback = faster fixes.

**2. SARIF is the universal security format.**
Trivy, Snyk, tfsec — they all output SARIF. GitHub's Security tab reads SARIF natively. Once you understand SARIF, integrating any new tool is trivial.

**3. The difference between SAST and DAST.**
SAST reads your code and finds vulnerabilities by analyzing it statically. DAST actually runs your code and sends real HTTP requests. SAST is fast and runs early. DAST is slower but catches things SAST can't — like missing security headers that helmet would have added.

**4. `--exit-code 1` is the key flag for pipeline gates.**
Without it, Trivy runs and finds vulnerabilities but the job still passes. With it, the job fails on finding. Every security tool has this concept — it's what makes a scan a gate.

**5. IaC security is infrastructure security.**
A misconfigured S3 bucket in Terraform is just as dangerous as a SQL injection. tfsec catches these before `terraform apply` ever runs — before any real infrastructure exists.

**6. Dependabot + security pipeline = automated remediation.**
Dependabot opens the PR. The pipeline verifies it's safe. You approve and merge. That's essentially automated CVE remediation for known vulnerabilities.

**7. The `for` clause in alert rules (from the monitoring project) has a direct parallel here.**
The `continue-on-error: true` flag in GitHub Actions is the same concept — you want to collect all findings before deciding whether to fail, not abort on the first issue.

---

## Production Improvements

Things to add for a real production setup:

**1. OIDC instead of long-lived AWS credentials**
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions
    aws-region: eu-west-1
```

**2. Secret scanning**
```yaml
- uses: trufflesecurity/trufflehog@main
  with:
    path: ./
    base: ${{ github.event.repository.default_branch }}
```

**3. SBOM (Software Bill of Materials) generation**
```yaml
- uses: anchore/sbom-action@v0
  with:
    image: ${{ env.FULL_IMAGE }}
    format: cyclonedx-json
```

**4. License compliance scanning**
```yaml
- run: npx license-checker --onlyAllow 'MIT;Apache-2.0;BSD-2-Clause;BSD-3-Clause'
```

**5. Signed container images (Cosign)**
```yaml
- uses: sigstore/cosign-installer@main
- run: cosign sign --yes ${{ env.FULL_IMAGE }}
```

**6. Policy-as-Code with OPA/Conftest**
Define security policies in Rego and gate deployments against them.

**7. Runtime security with Falco**
Kubernetes runtime threat detection — alerts when a container tries to write to unexpected paths, open shells, etc.

---

## Author

**Moamen Mohamed Hafez**
Systems Engineer → DevOps & Cloud Engineer

- GitHub: [github.com/Iamoamen](https://github.com/Iamoamen)
- LinkedIn: [linkedin.com/in/moamen-mohamed-hafez-49a660216](https://linkedin.com/in/moamen-mohamed-hafez-49a660216)

---

## License

MIT — see [LICENSE](LICENSE) for details.
