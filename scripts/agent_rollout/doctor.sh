#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/render_remote_config.sh"
"${SCRIPT_DIR}/openai_smoke.sh"
"${SCRIPT_DIR}/litellm_smoke.sh"
