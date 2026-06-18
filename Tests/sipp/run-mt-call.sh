#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sipp-digest-auth.sh
source "${SCRIPT_DIR}/sipp-digest-auth.sh"

UAS_BIND="${1:-127.0.0.1}"
UAS_PORT="${2:-15061}"
TARGET="${UAS_BIND}:${UAS_PORT}"

cleanup() {
  if [[ -n "${UAS_PID:-}" ]]; then
    kill "${UAS_PID}" 2>/dev/null || true
    wait "${UAS_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

sipp -sf "${SCRIPT_DIR}/mt_volte.xml" \
  "${SIPP_DIGEST_FLAGS[@]}" \
  -i "${UAS_BIND}" -p "${UAS_PORT}" &
UAS_PID=$!

for _ in $(seq 1 50); do
  if nc -z "${UAS_BIND}" "${UAS_PORT}" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

sipp -sf "${SCRIPT_DIR}/mo_volte_precondition.xml" \
  "${SIPP_DIGEST_FLAGS[@]}" \
  "${TARGET}" -m 1
