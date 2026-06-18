#!/usr/bin/env bash
# Full lab acceptance suite: unit/integration tests, CLI bootstrap, GUI smoke, optional SIPp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== SICLient acceptance suite =="

echo "[1/4] Swift unit + integration tests (core + GUI)"
swift test

echo "[2/4] CLI bootstrap smoke test"
swift run siclient --profile profiles/lab-volte-01.json --dry-run | tee /tmp/siclient-acceptance-bootstrap.log
grep -q 'bootstrap complete' /tmp/siclient-acceptance-bootstrap.log
grep -q 'lab-volte-01' /tmp/siclient-acceptance-bootstrap.log
if grep -q 'e19aa1c37ab954daa44fa2a52007' /tmp/siclient-acceptance-bootstrap.log; then
  echo "Sensitive key material leaked into logs"
  exit 1
fi

echo "[3/4] GUI lab app smoke"
chmod +x Tests/gui/run-gui-smoke.sh
./Tests/gui/run-gui-smoke.sh

echo "[4/4] SIPp loopback scenarios (optional)"
if command -v sipp >/dev/null 2>&1; then
  ./Tests/sipp/run-uas-volte.sh 127.0.0.1 15060 &
  UAS_PID=$!
  sleep 0.5
  ./Tests/sipp/run-mo-call.sh 127.0.0.1:15060
  kill "$UAS_PID" 2>/dev/null || true
  ./Tests/sipp/run-mt-call.sh 127.0.0.1 15061
else
  echo "SIPp not installed; skipping signaling conformance"
fi

echo "Acceptance suite complete"
