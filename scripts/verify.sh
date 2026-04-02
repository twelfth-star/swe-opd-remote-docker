#!/usr/bin/env bash
#
# End-to-end verification for swe-opd-remote-docker.
# Tests each layer of the pipeline and reports pass/fail.
#
# Usage:
#   bash scripts/verify.sh              # run all checks
#   bash scripts/verify.sh --step N     # run only step N (1-6)
#   bash scripts/verify.sh --from N     # run steps N onwards
#
# Steps:
#   1  Config files exist
#   2  SSH connectivity to Server B
#   3  SGLang health (local, Server A)
#   4  Model reverse tunnel (A → B)
#   5  Rollout service health (Server B, via tunnel)
#   6  Single-instance rollout (end-to-end)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/shared/common.sh"

# ── Helpers ──────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { printf "  ${GREEN}PASS${NC}  %s\n" "$*"; }
fail()  { printf "  ${RED}FAIL${NC}  %s\n" "$*"; }
skip()  { printf "  ${YELLOW}SKIP${NC}  %s\n" "$*"; }
step_header() { printf "\n${BOLD}Step %s: %s${NC}\n" "$1" "$2"; }

STEP_ONLY=""
STEP_FROM=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --step) STEP_ONLY="$2"; shift 2 ;;
        --from) STEP_FROM="$2"; shift 2 ;;
        *) shift ;;
    esac
done

should_run() {
    local n="$1"
    if [[ -n "${STEP_ONLY}" ]]; then
        [[ "${n}" == "${STEP_ONLY}" ]]
    else
        [[ "${n}" -ge "${STEP_FROM}" ]]
    fi
}

FAILURES=0

# ── Step 1: Config files ────────────────────────────────────────────

if should_run 1; then
    step_header 1 "Configuration files"
    for role in model_serving agent_rollout rollout_service remote_rollout_client; do
        f="${PROJECT_ROOT}/config/bootstrap/${role}.local.env"
        if [[ -f "${f}" ]]; then
            pass "${role}.local.env"
        else
            fail "${role}.local.env missing"
            FAILURES=$((FAILURES + 1))
        fi
    done
fi

# ── Step 2: SSH to Server B ─────────────────────────────────────────

if should_run 2; then
    step_header 2 "SSH connectivity to Server B"
    load_bootstrap_env remote_rollout_client 2>/dev/null

    SSH_USER="${REMOTE_ROLLOUT_SSH_USER:-}"
    SSH_HOST="${REMOTE_ROLLOUT_SSH_HOST:-}"
    SSH_KEY="${REMOTE_ROLLOUT_SSH_KEY:-}"

    if [[ -z "${SSH_USER}" || -z "${SSH_HOST}" || -z "${SSH_KEY}" ]]; then
        fail "SSH vars not configured in remote_rollout_client.local.env"
        FAILURES=$((FAILURES + 1))
    else
        if ssh -i "${SSH_KEY}" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
             "${SSH_USER}@${SSH_HOST}" "echo ok" >/dev/null 2>&1; then
            pass "SSH ${SSH_USER}@${SSH_HOST}"
        else
            fail "Cannot SSH to ${SSH_USER}@${SSH_HOST}"
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi

# ── Step 3: SGLang health ───────────────────────────────────────────

if should_run 3; then
    step_header 3 "SGLang health (local)"
    load_bootstrap_env model_serving 2>/dev/null

    HOST="${SGLANG_HOST:-127.0.0.1}"
    PORT="${SGLANG_PORT:-30000}"
    URL="http://${HOST}:${PORT}"

    # Try /v1/models
    if "$(bootstrap_python_bin)" -m swe_opd.distributed_rollout probe-sglang \
         --api-base "${URL}" >/dev/null 2>&1; then
        pass "SGLang at ${URL} is healthy"

        # Smoke test
        MODEL="${SGLANG_MODEL_NAME:-${SGLANG_MODEL_PATH:-unknown}}"
        if "$(bootstrap_python_bin)" -m swe_opd.distributed_rollout openai-smoke \
             --api-base "${URL}" \
             --api-key "${SGLANG_API_KEY:-EMPTY}" \
             --model-name "${MODEL}" \
             --prompt "Reply with exactly: ok" \
             --max-tokens 10 >/dev/null 2>&1; then
            pass "SGLang smoke test (chat completion)"
        else
            fail "SGLang smoke test failed"
            FAILURES=$((FAILURES + 1))
        fi
    else
        fail "SGLang not reachable at ${URL} — is it running?"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Step 4: Model reverse tunnel ────────────────────────────────────

if should_run 4; then
    step_header 4 "Model reverse tunnel (A → B)"
    load_bootstrap_env model_serving 2>/dev/null
    load_bootstrap_env remote_rollout_client 2>/dev/null

    REMOTE_PORT="${SGLANG_TUNNEL_REMOTE_PORT:-32000}"
    PID_FILE="${PROJECT_ROOT}/outputs/model_serving/model_tunnel_${REMOTE_PORT}.pid"

    if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
        pass "Reverse tunnel PID alive"

        # Verify from Server B side
        SSH_USER="${REMOTE_ROLLOUT_SSH_USER:-}"
        SSH_HOST="${REMOTE_ROLLOUT_SSH_HOST:-}"
        SSH_KEY="${REMOTE_ROLLOUT_SSH_KEY:-}"
        if [[ -n "${SSH_USER}" && -n "${SSH_HOST}" && -n "${SSH_KEY}" ]]; then
            if ssh -i "${SSH_KEY}" -o ConnectTimeout=10 \
                 "${SSH_USER}@${SSH_HOST}" \
                 "curl -sf http://127.0.0.1:${REMOTE_PORT}/v1/models" >/dev/null 2>&1; then
                pass "Server B can reach SGLang via tunnel (:${REMOTE_PORT})"
            else
                fail "Server B cannot reach SGLang at 127.0.0.1:${REMOTE_PORT}"
                FAILURES=$((FAILURES + 1))
            fi
        fi
    else
        fail "No active reverse tunnel — run: bash scripts/model_serving/start_remote_tunnel.sh"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Step 5: Rollout service health ──────────────────────────────────

if should_run 5; then
    step_header 5 "Rollout service health"
    load_bootstrap_env remote_rollout_client 2>/dev/null

    # Ensure tunnel is open
    "${SCRIPT_DIR}/remote_client/open_tunnel.sh" >/dev/null 2>&1 || true

    SVC_BASE="${REMOTE_ROLLOUT_SERVICE_BASE:-http://127.0.0.1:18080}"

    if curl -sf "${SVC_BASE}/healthz" >/dev/null 2>&1; then
        pass "Rollout service at ${SVC_BASE}/healthz"
    else
        fail "Rollout service not reachable at ${SVC_BASE}"
        printf "       Make sure the service is running on Server B:\n"
        printf "       bash scripts/agent_runtime/start_service_nohup.sh\n"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Step 6: End-to-end single rollout ───────────────────────────────

if should_run 6; then
    step_header 6 "End-to-end single rollout (this may take several minutes)"

    TEST_INSTANCE="${SWE_VERIFY_INSTANCE:-django__django-11099}"

    printf "  Testing with instance: %s\n" "${TEST_INSTANCE}"
    printf "  Submitting job...\n"

    if bash "${SCRIPT_DIR}/remote_client/run_rollout.sh" single "${TEST_INSTANCE}" >/dev/null 2>&1; then
        pass "Single rollout completed for ${TEST_INSTANCE}"
    else
        fail "Single rollout failed for ${TEST_INSTANCE}"
        FAILURES=$((FAILURES + 1))
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────

printf "\n${BOLD}── Summary ──${NC}\n\n"
if [[ "${FAILURES}" -eq 0 ]]; then
    printf "${GREEN}All checks passed.${NC}\n"
else
    printf "${RED}%d check(s) failed.${NC}\n" "${FAILURES}"
fi
exit "${FAILURES}"
