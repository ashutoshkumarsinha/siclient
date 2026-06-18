#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "== SICLient acceptance suite =="

echo "[1/3] Swift unit + integration tests"
swift test

echo "[2/3] CLI bootstrap smoke test"
swift run siclient --profile profiles/lab-volte-01.json --dry-run | tee /tmp/siclient-acceptance-bootstrap.log
grep -q 'bootstrap complete' /tmp/siclient-acceptance-bootstrap.log

echo "[3/3] SIPp loopback scenarios (optional)"
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
