#!/usr/bin/env bash
# ============================================================
# demo-before-after.sh
# Simulates the "before" (vulnerable) and "after" (fixed) states
# to demonstrate the DevSecOps pipeline catching real issues.
#
# Run this locally to see what the pipeline would catch.
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo ""
echo "════════════════════════════════════════════════════════"
echo "  🔴 BEFORE: Simulating vulnerable state"
echo "════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Switch to vulnerable dependencies ─────────────────
echo -e "${YELLOW}[DEMO]${NC} Copying vulnerable package.json..."
cp app/package.json app/package.json.backup
cp app/package.vulnerable.json app/package.json

echo ""
echo "Vulnerable packages introduced:"
echo "  lodash@4.17.4    → CVE-2019-10744  (Prototype Pollution) — CRITICAL"
echo "  axios@0.21.1     → CVE-2021-3749   (ReDoS)              — HIGH"
echo "  node-fetch@2.6.0 → CVE-2022-0235   (Header injection)   — HIGH"
echo ""

# ── Step 2: Run Snyk against the vulnerable dependencies ──────
echo -e "${BLUE}[SCAN]${NC} Running Snyk on vulnerable dependencies..."
echo ""

if command -v snyk &>/dev/null && [ -n "${SNYK_TOKEN:-}" ]; then
  cd app
  npm ci --silent
  snyk test --severity-threshold=high --file=package.json || true
  cd ..
else
  # Simulate the output if Snyk isn't available
  cat << 'EOF'
✗ High severity vulnerability found in lodash@4.17.4
  Description: Prototype Pollution
  Info: https://snyk.io/vuln/SNYK-JS-LODASH-567746
  Introduced through: lodash@4.17.4
  Fix: Upgrade to lodash@4.17.21

✗ Critical severity vulnerability found in lodash@4.17.4
  Description: Command Injection via template
  Info: https://snyk.io/vuln/SNYK-JS-LODASH-1040724
  Introduced through: lodash@4.17.4
  Fix: Upgrade to lodash@4.17.21

✗ High severity vulnerability found in axios@0.21.1
  Description: Regular Expression Denial of Service (ReDoS)
  Info: https://snyk.io/vuln/SNYK-JS-AXIOS-1584935
  Fix: Upgrade to axios@0.21.2

Issues: 3 vulnerabilities (1 critical, 2 high)
EOF
fi

echo ""
echo -e "${RED}❌ PIPELINE RESULT: BLOCKED${NC}"
echo "   Reason: CRITICAL vulnerability in lodash (Prototype Pollution)"
echo "   The PR comment would show:"
echo "   | 🔴 Critical | 1 | ❌ BLOCKED |"
echo ""

# ── Step 3: Also show a Dockerfile vulnerability ──────────────
echo "════════════════════════════════════════════════════════"
echo "  Running Trivy on vulnerable image (simulated output)"
echo "════════════════════════════════════════════════════════"
echo ""

cat << 'EOF'
devsecops-demo:vulnerable (alpine 3.15.0)

Total: 3 (CRITICAL: 1, HIGH: 2)

┌──────────────────┬────────────────┬──────────┬───────────────────┬──────────────────┐
│ Library          │ Vulnerability  │ Severity │ Installed Version │ Fixed Version    │
├──────────────────┼────────────────┼──────────┼───────────────────┼──────────────────┤
│ lodash           │ CVE-2019-10744 │ CRITICAL │ 4.17.4            │ 4.17.21          │
│ axios            │ CVE-2021-3749  │ HIGH     │ 0.21.1            │ 0.21.2           │
│ node-fetch       │ CVE-2022-0235  │ HIGH     │ 2.6.0             │ 2.6.7            │
└──────────────────┴────────────────┴──────────┴───────────────────┴──────────────────┘

trivy image --exit-code 1 --severity CRITICAL devsecops-demo:vulnerable
→ Exit code: 1 (FAILED)
EOF

echo ""

# ── Step 4: Show tfsec catching Terraform issues ──────────────
echo "════════════════════════════════════════════════════════"
echo "  Running tfsec on vulnerable Terraform (main.tf)"
echo "════════════════════════════════════════════════════════"
echo ""

if command -v tfsec &>/dev/null; then
  tfsec terraform/ --minimum-severity HIGH 2>&1 || true
else
  cat << 'EOF'
Result #1 CRITICAL Security group rule allows ingress from public internet
──────────────────────────────────────────────────
  ID         aws-ec2-no-public-ingress-sgr
  Impact     Your port exposed to the internet
  Rule       https://aquasecurity.github.io/tfsec/v1.28.0/checks/aws/ec2/no-public-ingress-sgr/
  terraform/main.tf:52-57
──────────────────────────────────────────────────
      49 |   ingress {
      50 |     from_port   = 22
      51 |     to_port     = 22
      52 |     protocol    = "tcp"
  [  53 |     cidr_blocks = ["0.0.0.0/0"]   ]
      54 |   }

Result #2 HIGH S3 Bucket does not have encryption enabled
──────────────────────────────────────────────────
  ID         aws-s3-enable-bucket-encryption
  terraform/main.tf:25-32

Result #3 HIGH RDS encryption is disabled
──────────────────────────────────────────────────
  ID         aws-rds-encrypt-instance-storage-data
  terraform/main.tf:74

3 potential problems detected.
EOF
fi

echo ""
echo -e "${RED}❌ tfsec RESULT: 3 HIGH/CRITICAL misconfigurations found${NC}"
echo "   PR annotations would highlight each issue in the diff."
echo ""

# ── Step 5: Fix it ────────────────────────────────────────────
echo "════════════════════════════════════════════════════════"
echo "  🟢 AFTER: Applying fixes"
echo "════════════════════════════════════════════════════════"
echo ""

echo -e "${YELLOW}[DEMO]${NC} Restoring secure package.json..."
cp app/package.json.backup app/package.json
rm app/package.json.backup

echo ""
echo "Fixed packages:"
echo "  lodash removed (wasn't needed — was only in vulnerable demo)"
echo "  axios removed (not needed in this app)"
echo "  node-fetch removed (not needed)"
echo "  helmet@7.1.0 added → sets secure HTTP headers"
echo ""
echo "Fixed Terraform:"
echo "  S3 → encryption enabled (KMS), public access blocked, versioning on"
echo "  Security group → SSH restricted to office CIDR only"
echo "  RDS → encrypted, deletion_protection=true, backup=7 days"
echo ""

# ── Step 6: Scan the fixed version ────────────────────────────
echo -e "${BLUE}[SCAN]${NC} Running Snyk on FIXED dependencies..."
echo ""

if command -v snyk &>/dev/null && [ -n "${SNYK_TOKEN:-}" ]; then
  cd app && npm ci --silent
  snyk test --severity-threshold=high --file=package.json && cd ..
else
  cat << 'EOF'
Testing /app...

✔ Tested 3 dependencies for known issues, no vulnerable paths found.

Next steps:
- Run `snyk monitor` to be notified about new vulnerabilities
EOF
fi

echo ""
echo -e "${GREEN}✅ PIPELINE RESULT: PASSED${NC}"
echo ""
echo "Summary:"
echo "  SAST (Snyk):          ✅ 0 critical, 0 high"
echo "  Container (Trivy):    ✅ 0 critical"
echo "  IaC (tfsec):          ✅ 0 high/critical"
echo "  DAST (ZAP):           ✅ No critical findings"
echo ""
echo "  🟢 Security gate passed — PR is safe to merge"
echo ""
