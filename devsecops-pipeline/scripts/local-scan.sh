#!/usr/bin/env bash
# ============================================================
# local-scan.sh — Run all security scans locally before pushing
# This lets you catch issues before CI fails your PR
#
# Prerequisites:
#   - Docker installed
#   - npm installed
#   - snyk CLI: npm install -g snyk
#   - trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/
#   - tfsec: brew install tfsec OR go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[SCAN]${NC}  $*"; }
pass()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }

IMAGE_NAME="devsecops-demo:local"
REPORT_DIR="security-reports/local-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORT_DIR"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  🔒 DevSecOps Local Security Scanner"
echo "════════════════════════════════════════════════════════"
echo ""

FAILURES=0

# ── 1. Unit Tests ─────────────────────────────────────────────
info "Running unit tests..."
cd app && npm ci --silent && npm test 2>&1 | tee "../$REPORT_DIR/unit-tests.txt"
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  pass "Unit tests passed"
else
  fail "Unit tests failed"
  FAILURES=$((FAILURES + 1))
fi
cd ..

# ── 2. SAST: Snyk dependency scan ────────────────────────────
info "Running Snyk dependency scan (SAST)..."
if command -v snyk &>/dev/null; then
  snyk test \
    --file=app/package.json \
    --severity-threshold=high \
    --json > "$REPORT_DIR/snyk-sast.json" 2>&1 || true

  SNYK_CRITICAL=$(cat "$REPORT_DIR/snyk-sast.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
vulns=d.get('vulnerabilities',[])
print(sum(1 for v in vulns if v.get('severity') in ['critical']))
" 2>/dev/null || echo "0")

  if [ "$SNYK_CRITICAL" -gt 0 ]; then
    fail "Snyk found $SNYK_CRITICAL CRITICAL vulnerabilities"
    FAILURES=$((FAILURES + 1))
  else
    pass "Snyk: no critical vulnerabilities found"
  fi
else
  warn "Snyk not installed — skipping. Install: npm install -g snyk"
fi

# ── 3. Build Docker image ─────────────────────────────────────
info "Building Docker image..."
docker build -t "$IMAGE_NAME" . 2>&1 | tail -5
pass "Docker image built: $IMAGE_NAME"

# ── 4. Container scan: Trivy ──────────────────────────────────
info "Running Trivy container scan..."
if command -v trivy &>/dev/null; then
  trivy image \
    --severity CRITICAL,HIGH \
    --exit-code 0 \
    --format json \
    --output "$REPORT_DIR/trivy-results.json" \
    --ignore-unfixed \
    "$IMAGE_NAME"

  TRIVY_CRITICAL=$(cat "$REPORT_DIR/trivy-results.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
total=0
for r in d.get('Results',[]):
  for v in r.get('Vulnerabilities',[]) or []:
    if v.get('Severity')=='CRITICAL':
      total+=1
print(total)
" 2>/dev/null || echo "0")

  TRIVY_HIGH=$(cat "$REPORT_DIR/trivy-results.json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
total=0
for r in d.get('Results',[]):
  for v in r.get('Vulnerabilities',[]) or []:
    if v.get('Severity')=='HIGH':
      total+=1
print(total)
" 2>/dev/null || echo "0")

  echo "  Trivy findings: CRITICAL=$TRIVY_CRITICAL HIGH=$TRIVY_HIGH"

  if [ "$TRIVY_CRITICAL" -gt 0 ]; then
    fail "Trivy found $TRIVY_CRITICAL CRITICAL vulnerabilities — pipeline would be BLOCKED"
    FAILURES=$((FAILURES + 1))
  else
    pass "Trivy: no critical vulnerabilities"
  fi

  # Also show a human-readable table
  trivy image \
    --severity CRITICAL,HIGH \
    --ignore-unfixed \
    "$IMAGE_NAME" 2>/dev/null || true
else
  warn "Trivy not installed — skipping. See: https://aquasecurity.github.io/trivy"
fi

# ── 5. IaC scan: tfsec ────────────────────────────────────────
info "Running tfsec IaC scan..."
if command -v tfsec &>/dev/null; then
  tfsec terraform/ \
    --minimum-severity HIGH \
    --format lovely \
    2>&1 | tee "$REPORT_DIR/tfsec-results.txt"

  TFSEC_EXIT=${PIPESTATUS[0]}
  if [ "$TFSEC_EXIT" -ne 0 ]; then
    warn "tfsec found HIGH/CRITICAL misconfigurations (see above)"
    # Not a hard failure locally — pipeline will annotate PR
  else
    pass "tfsec: no high/critical misconfigurations"
  fi
else
  warn "tfsec not installed — skipping. Install: brew install tfsec"
fi

# ── 6. DAST: OWASP ZAP (quick baseline) ─────────────────────
info "Running OWASP ZAP baseline scan..."
if command -v docker &>/dev/null; then
  # Start the app
  docker run -d --name local-app -p 3001:3000 "$IMAGE_NAME" 2>/dev/null || true
  sleep 3

  # Run ZAP
  docker run --rm \
    --network host \
    -v "$(pwd)/$REPORT_DIR:/zap/wrk:rw" \
    ghcr.io/zaproxy/zaproxy:stable \
    zap-baseline.py \
    -t http://localhost:3001 \
    -r zap-report.html \
    -J zap-report.json \
    -I \
    2>&1 | tail -20

  docker stop local-app 2>/dev/null || true
  docker rm local-app 2>/dev/null || true

  pass "ZAP baseline scan complete — see $REPORT_DIR/zap-report.html"
else
  warn "Docker not running — skipping ZAP"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo "  Security Scan Complete"
echo "  Reports saved to: $REPORT_DIR/"
echo ""
if [ "$FAILURES" -gt 0 ]; then
  fail "  $FAILURES scan(s) FAILED — fix before pushing"
  echo "════════════════════════════════════════════════════════"
  exit 1
else
  pass "  All scans passed ✅"
  echo "════════════════════════════════════════════════════════"
fi
