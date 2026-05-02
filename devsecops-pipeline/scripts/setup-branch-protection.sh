# ============================================================
# GitHub Branch Protection — How to Configure
# Run these commands using the GitHub CLI (gh)
# Or configure manually in GitHub UI (instructions below)
# ============================================================

# ── Option A: GitHub CLI (gh) ─────────────────────────────────
# Install: https://cli.github.com/

# 1. Authenticate
gh auth login

# 2. Set branch protection rules on 'main'
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["🚦 Security Gate","🧪 Unit Tests"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  --field restrictions=null \
  --field required_linear_history=true \
  --field allow_force_pushes=false \
  --field allow_deletions=false

# ── Option B: GitHub UI (manual) ─────────────────────────────
# 1. Go to: github.com/{owner}/{repo}/settings/branches
# 2. Click "Add branch protection rule"
# 3. Branch name pattern: main
# 4. Enable these settings:
#    ✅ Require a pull request before merging
#       - Required approving reviews: 1
#       - Dismiss stale pull request approvals: ✅
#    ✅ Require status checks to pass before merging
#       - Require branches to be up to date: ✅
#       - Status checks required:
#           "🚦 Security Gate"
#           "🧪 Unit Tests"
#    ✅ Require linear history
#    ✅ Do not allow bypassing the above settings
#    ✅ Restrict who can push to matching branches
# 5. Click "Create" or "Save changes"

# ── Setting up GitHub Secrets ────────────────────────────────
# Required secrets for the pipeline:

# SNYK_TOKEN:
#   1. Go to: snyk.io → Sign up (free)
#   2. Click your avatar → Account Settings
#   3. Find "Auth Token" → click "click to show"
#   4. Copy the token
#   5. GitHub repo → Settings → Secrets and variables → Actions
#   6. Click "New repository secret"
#   7. Name: SNYK_TOKEN
#   8. Value: paste your token
#   9. Click "Add secret"

# GITHUB_TOKEN:
#   Automatically provided by GitHub Actions — no setup needed.
#   It's used for: pushing to GHCR, posting PR comments, uploading SARIF

# Optional — for AWS deployment:
# AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY
# (Use OIDC instead of long-lived keys in real production)
