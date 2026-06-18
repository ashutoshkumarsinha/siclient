#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sipp-digest-auth.sh
source "${SCRIPT_DIR}/sipp-digest-auth.sh"

TARGET="${1:-127.0.0.1:15060}"

exec sipp -sf "${SCRIPT_DIR}/mo_volte_precondition.xml" \
  "${SIPP_DIGEST_FLAGS[@]}" \
  "${TARGET}" -m 1
