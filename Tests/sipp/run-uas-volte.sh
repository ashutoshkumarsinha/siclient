#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sipp-digest-auth.sh
source "${SCRIPT_DIR}/sipp-digest-auth.sh"

BIND_IP="${1:-127.0.0.1}"
PORT="${2:-15060}"

exec sipp -sf "${SCRIPT_DIR}/uas_volte_call.xml" \
  "${SIPP_DIGEST_FLAGS[@]}" \
  -i "${BIND_IP}" -p "${PORT}"
