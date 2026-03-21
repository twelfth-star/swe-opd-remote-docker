#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_bootstrap_env model_serving

SGLANG_HOST="${SGLANG_HOST:-127.0.0.1}"
SGLANG_PORT="${SGLANG_PORT:-30000}"
BASE_URL="http://${SGLANG_HOST}:${SGLANG_PORT}"

"$(bootstrap_python_bin)" -m swe_opd.distributed_rollout probe-sglang --api-base "${BASE_URL}"
