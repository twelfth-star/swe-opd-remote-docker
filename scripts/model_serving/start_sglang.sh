#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/common.sh"

load_bootstrap_env model_serving
require_env SGLANG_MODEL_PATH

SGLANG_PYTHON_BIN="${SGLANG_PYTHON_BIN:-python3}"
SGLANG_HOST="${SGLANG_HOST:-0.0.0.0}"
SGLANG_PORT="${SGLANG_PORT:-30000}"
SGLANG_TP="${SGLANG_TP:-1}"
SGLANG_MEM_FRACTION_STATIC="${SGLANG_MEM_FRACTION_STATIC:-0.80}"
LOG_DIR="${SWE_OPD_PROJECT_ROOT}/outputs/model_serving"
mkdir -p "${LOG_DIR}"

cmd=(
    "${SGLANG_PYTHON_BIN}" -m sglang.launch_server
    --model-path "${SGLANG_MODEL_PATH}"
    --host "${SGLANG_HOST}"
    --port "${SGLANG_PORT}"
    --tp "${SGLANG_TP}"
    --mem-fraction-static "${SGLANG_MEM_FRACTION_STATIC}"
)

if [[ -n "${SGLANG_CONTEXT_LENGTH:-}" ]]; then
    cmd+=(--context-length "${SGLANG_CONTEXT_LENGTH}")
fi

if [[ -n "${SGLANG_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=( ${SGLANG_EXTRA_ARGS} )
    cmd+=("${extra_args[@]}")
fi

echo "Starting SGLang model serving"
echo "Model path : ${SGLANG_MODEL_PATH}"
echo "HTTP base  : http://${SGLANG_HOST}:${SGLANG_PORT}"
echo "OpenAI base: http://${SGLANG_HOST}:${SGLANG_PORT}/v1"
printf 'Command    :'
printf ' %q' "${cmd[@]}"
printf '\n'

exec "${cmd[@]}"
