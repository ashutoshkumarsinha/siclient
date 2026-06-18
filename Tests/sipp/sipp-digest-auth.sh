#!/usr/bin/env bash
# Common SIP Digest auth flags for lab-volte-01 scenarios.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=digest-auth.env
source "${SCRIPT_DIR}/digest-auth.env"

export SIPP_DIGEST_FLAGS=(
  -inf "${SCRIPT_DIR}/lab-volte-01.csv"
  -au "${IMPI}"
  -ap "${MD5_PASSWORD}"
  -auth_uri "${AUTH_URI}"
)

export SIPP_IMS_DIGEST_FLAGS=(
  -inf "${SCRIPT_DIR}/lab-volte-01-ims.csv"
  -au "${IMPI}"
  -ap "${AKA_SECRET_HEX}"
  -auth_uri "${AUTH_URI}"
)
