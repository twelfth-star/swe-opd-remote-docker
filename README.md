# swe-opd-remote-docker

Distributed SWE-bench rollout infrastructure that separates **model serving** (Server A) from **agent execution** (Server B). Server A runs SGLang for GPU-based inference; Server B runs [mini-swe-agent-plus](https://github.com/Kwai-Klear/mini-swe-agent-plus) in Docker containers to execute SWE-bench tasks against the remote model.

Communication between the two servers is handled entirely through SSH tunnels — no special network configuration required.

## Architecture

```
Server A (GPU node)                          Server B (taurus — Docker host)
┌────────────────────────────┐               ┌────────────────────────────┐
│  SGLang (:30000)           │──ssh -R──────▶│  :32000 (reverse tunnel)   │
│                            │               │         ▼                  │
│                            │               │  mini-swe-agent-plus       │
│                            │               │    + Docker containers     │
│                            │               │                            │
│  Remote client             │◀──ssh -L──────│  Rollout Service (:18080)  │
│    (:18080 local forward)  │               │                            │
└────────────────────────────┘               └────────────────────────────┘
```

**Reverse tunnel** (`ssh -R`): Exposes Server A's SGLang to Server B so the agent can call the model.

**Local forward** (`ssh -L`): Exposes Server B's rollout service to Server A so the client can submit jobs and fetch results.

## Quick Start

### 1. Run the setup wizard

```bash
bash scripts/setup.sh
```

This interactively creates all four configuration files:

| File | Where it's used | What it configures |
|------|-----------------|-------------------|
| `config/bootstrap/model_serving.local.env` | Server A | SGLang launch params, reverse tunnel SSH creds |
| `config/bootstrap/agent_rollout.local.env` | Server B | mini-swe-agent-plus paths, remote model endpoint |
| `config/bootstrap/rollout_service.local.env` | Server B | HTTP service bind address, concurrency |
| `config/bootstrap/remote_rollout_client.local.env` | Server A | SSH tunnel to rollout service, client params |

> All `*.local.env` files are gitignored. Each teammate runs `setup.sh` with their own credentials.

To check if config files already exist:

```bash
bash scripts/setup.sh --check
```

### 2. Start the pipeline

**On Server A** — start SGLang and the reverse tunnel:

```bash
# Start SGLang (foreground)
bash scripts/model_serving/start_sglang.sh

# Or background
bash scripts/model_serving/start_sglang_nohup.sh

# Test it locally
bash scripts/model_serving/test_sglang.sh

# Open reverse tunnel so Server B can reach the model
bash scripts/model_serving/start_remote_tunnel.sh
```

**On Server B** — start the rollout service:

```bash
# Start the HTTP rollout service (foreground)
bash scripts/agent_runtime/start_service.sh

# Or background
bash scripts/agent_runtime/start_service_nohup.sh
```

**On Server A** — submit a rollout job:

```bash
# Single instance
bash scripts/remote_client/run_rollout.sh single django__django-11099

# Batch (first 5 instances, 2 parallel workers)
bash scripts/remote_client/run_rollout.sh batch --slice 0:5 --workers 2
```

### 3. Verify everything works

```bash
bash scripts/verify.sh
```

This runs through 6 checks: config → SSH → SGLang → tunnel → service → end-to-end rollout. You can also run individual steps:

```bash
bash scripts/verify.sh --step 2   # only test SSH connectivity
bash scripts/verify.sh --from 3   # skip config/SSH, start from SGLang health
```

---

## Setup Guide for New Teammates

### Prerequisites

- **Server A**: A GPU node where you can run SGLang. You need:
  - A Python environment with `sglang` installed
  - A Python environment with `PyYAML`, `openai`, `litellm` (for helper scripts, can be the same env)
  - SSH key that can connect to Server B

- **Server B** (taurus): A machine with Docker. You need:
  - Your own taurus account (ask the admin for access)
  - A Python environment with `PyYAML`, `openai`, `litellm`
  - mini-swe-agent-plus cloned and its dependencies installed
  - This repo cloned (or at least the `scripts/`, `src/`, `config/` directories copied over)

### Step-by-step

#### 1. Generate your SSH key (if you don't have one)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/taurus_key -C "yourname@serverA"
ssh-copy-id -i ~/.ssh/taurus_key.pub YOUR_USERNAME@taurus.cs.ucsb.edu
```

Test it:

```bash
ssh -i ~/.ssh/taurus_key YOUR_USERNAME@taurus.cs.ucsb.edu "echo connected"
```

#### 2. Clone this repo on both servers

**Server A:**
```bash
git clone git@github.com:twelfth-star/swe-opd-remote-docker.git
cd swe-opd-remote-docker
```

**Server B (taurus):**
```bash
git clone git@github.com:twelfth-star/swe-opd-remote-docker.git
cd swe-opd-remote-docker
```

#### 3. Run the setup wizard on Server A

```bash
bash scripts/setup.sh
```

You'll be prompted for:

| Prompt | What to enter |
|--------|--------------|
| Username on Server B | Your taurus username (e.g. `jdoe`) |
| Server B hostname | `taurus.cs.ucsb.edu` |
| SSH private key path | e.g. `~/.ssh/taurus_key` |
| Model path | HuggingFace ID or local path (e.g. `Kwai-Klear/Klear-AgentForge-8B`) |
| SGLang python binary | Path to python with sglang (e.g. `/path/to/envs/sglang/bin/python`) |
| Launch mode | `single` for 1 GPU, `router` for multi-GPU |
| Tensor parallelism | Number of GPUs per inference worker |
| mini-swe-agent-plus path on Server B | Absolute path on taurus (e.g. `/home/jdoe/mini-swe-agent-plus`) |

#### 4. Copy the Server B config files to taurus

The setup wizard generates `agent_rollout.local.env` and `rollout_service.local.env` for Server B. Copy them:

```bash
scp -i ~/.ssh/taurus_key \
  config/bootstrap/agent_rollout.local.env \
  config/bootstrap/rollout_service.local.env \
  YOUR_USERNAME@taurus.cs.ucsb.edu:~/swe-opd-remote-docker/config/bootstrap/
```

Or SSH into taurus and run `bash scripts/setup.sh` there — the wizard works on both sides.

#### 5. Verify

```bash
bash scripts/verify.sh
```

---

## Directory Structure

```
scripts/
  setup.sh                              # Interactive config wizard
  verify.sh                             # End-to-end smoke test
  shared/
    common.sh                           # Env loading, helpers (sourced by all scripts)
  model_serving/                        # Server A: SGLang
    start_sglang.sh                     # Launch SGLang (foreground)
    start_sglang_nohup.sh              # Launch SGLang (background)
    test_sglang.sh                      # Health check + smoke test
    start_remote_tunnel.sh             # ssh -R: expose SGLang to Server B
    status_remote_tunnel.sh            # Check tunnel PID & logs
    stop_remote_tunnel.sh              # Kill tunnel
  agent_runtime/                        # Server B: rollout
    render_config.sh                    # Inject model settings into agent config
    test_remote_model.sh               # Verify agent can reach remote SGLang
    run_single.sh                       # Run one SWE-bench instance
    run_batch.sh                        # Run batch of instances
    start_service.sh                    # Start HTTP rollout service (foreground)
    start_service_nohup.sh             # Start service (background)
    status_service.sh                  # Check service PID & logs
    stop_service.sh                    # Kill service
  remote_client/                        # Server A: calls Server B
    open_tunnel.sh                      # ssh -L: forward rollout service port
    run_rollout.sh                      # Submit job, wait, fetch result
    reset_connections.sh               # Kill all tunnels

config/bootstrap/
  model_serving.example.env            # Template — SGLang settings
  agent_rollout.example.env            # Template — agent runtime settings
  rollout_service.example.env          # Template — HTTP service settings
  remote_rollout_client.example.env    # Template — client/tunnel settings

config/mini_swe_agent_plus/
  swebench_add_edit_tool_compat.yaml   # Base agent scaffold config

src/swe_opd/
  distributed_rollout.py               # CLI: probe-sglang, openai-smoke, litellm-smoke, render-mini-config
  rollout_service.py                   # HTTP service + client (submit/status/wait/result)
```

## Configuration Reference

### model_serving.local.env (Server A)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SGLANG_PYTHON_BIN` | yes | `python3` | Python with sglang installed |
| `SGLANG_MODEL_PATH` | yes | — | HuggingFace model ID or local path |
| `SGLANG_LAUNCH_MODE` | no | `single` | `single` (1 process) or `router` (multi-worker) |
| `SGLANG_HOST` | no | `0.0.0.0` | Bind address |
| `SGLANG_PORT` | no | `30000` | Bind port |
| `SGLANG_TP` | no | `1` | Tensor parallelism (GPUs per worker) |
| `SGLANG_DP_SIZE` | no | `1` | Data parallelism (router mode only) |
| `SGLANG_MEM_FRACTION_STATIC` | no | `0.80` | GPU memory fraction for KV cache |
| `SGLANG_CONTEXT_LENGTH` | no | — | Override model's default context length |
| `SGLANG_EXTRA_ARGS` | no | — | Extra args (e.g. `--trust-remote-code`) |
| `SGLANG_API_KEY` | no | `EMPTY` | API key for auth |
| `SGLANG_MODEL_NAME` | no | — | Served model name (defaults to model path) |
| `SGLANG_TUNNEL_SSH_USER` | for tunnel | — | SSH user on Server B |
| `SGLANG_TUNNEL_SSH_HOST` | for tunnel | — | Server B hostname |
| `SGLANG_TUNNEL_SSH_KEY` | for tunnel | — | Path to SSH private key |
| `SGLANG_TUNNEL_REMOTE_HOST` | no | `127.0.0.1` | Bind address on Server B |
| `SGLANG_TUNNEL_REMOTE_PORT` | no | `32000` | Port on Server B |

### agent_rollout.local.env (Server B)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BOOTSTRAP_PYTHON_BIN` | no | `python3` | Python for swe-opd helpers |
| `MINI_PYTHON_BIN` | no | `python3` | Python for mini-swe-agent-plus |
| `MINI_SWE_AGENT_PLUS_ROOT` | yes | — | Absolute path to mini-swe-agent-plus repo |
| `REMOTE_API_BASE` | yes | — | SGLang URL (e.g. `http://127.0.0.1:32000`) |
| `REMOTE_API_KEY` | no | `EMPTY` | SGLang API key |
| `REMOTE_MODEL_NAME` | yes | — | Model name as registered in SGLang |
| `REMOTE_PROVIDER` | no | `openai` | LiteLLM provider |
| `REMOTE_TEMPERATURE` | no | `0.0` | Sampling temperature |
| `REMOTE_DROP_PARAMS` | no | `true` | LiteLLM drops unsupported params |
| `MINI_BASE_CONFIG` | no | auto | Base agent YAML config path |
| `SWEBENCH_SUBSET` | no | `verified` | SWE-bench dataset subset |
| `SWEBENCH_SPLIT` | no | `test` | SWE-bench dataset split |
| `SWEBENCH_WORKERS` | no | `2` | Parallel rollout workers |
| `SWEBENCH_DOCKER_START_CONCURRENCY` | no | `1` | Docker container startup concurrency |

### rollout_service.local.env (Server B)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BOOTSTRAP_PYTHON_BIN` | no | `python3` | Python for the service |
| `ROLLOUT_SERVICE_HOST` | no | `0.0.0.0` | Bind address |
| `ROLLOUT_SERVICE_PORT` | no | `18080` | Bind port |
| `ROLLOUT_SERVICE_JOB_ROOT` | no | `outputs/rollout_service_jobs` | Directory for job artifacts |
| `ROLLOUT_SERVICE_MAX_WORKERS` | no | `2` | Max concurrent rollout jobs |
| `ROLLOUT_SERVICE_API_TOKEN` | no | — | Optional bearer token for auth |

### remote_rollout_client.local.env (Server A)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `BOOTSTRAP_PYTHON_BIN` | no | `python3` | Python for client helpers |
| `REMOTE_ROLLOUT_SERVICE_BASE` | no | `http://127.0.0.1:18080` | Rollout service URL (after tunnel) |
| `REMOTE_ROLLOUT_API_TOKEN` | no | — | Bearer token (must match service) |
| `REMOTE_ROLLOUT_USE_SSH_TUNNEL` | no | `true` | Auto-create SSH tunnel |
| `REMOTE_ROLLOUT_SSH_USER` | for tunnel | — | SSH user on Server B |
| `REMOTE_ROLLOUT_SSH_HOST` | for tunnel | — | Server B hostname |
| `REMOTE_ROLLOUT_SSH_KEY` | for tunnel | — | SSH private key path |
| `REMOTE_ROLLOUT_LOCAL_PORT` | no | `18080` | Local port for tunnel |
| `REMOTE_ROLLOUT_REMOTE_HOST` | no | `127.0.0.1` | Remote bind address |
| `REMOTE_ROLLOUT_REMOTE_PORT` | no | `18080` | Remote port |
| `REMOTE_ROLLOUT_WAIT_TIMEOUT` | no | `0` | Job wait timeout (0 = infinite) |

## Rollout Service API

The rollout service on Server B exposes a simple REST API:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Health check, returns `{"ok": true}` |
| `/v1/jobs` | GET | List all jobs |
| `/v1/jobs` | POST | Submit a new job (returns immediately with `job_id`) |
| `/v1/jobs/{id}` | GET | Get job status and log tails |
| `/v1/jobs/{id}/result` | GET | Get full result (409 if not finished) |

### Submit a single rollout

```bash
curl -X POST http://127.0.0.1:18080/v1/jobs \
  -H 'Content-Type: application/json' \
  -d '{"kind": "single", "instance_id": "django__django-11099"}'
```

### Submit a batch rollout

```bash
curl -X POST http://127.0.0.1:18080/v1/jobs \
  -H 'Content-Type: application/json' \
  -d '{"kind": "batch", "slice": "0:10", "workers": 4}'
```

### Poll job status

```bash
curl http://127.0.0.1:18080/v1/jobs/{job_id}
```

Response includes `status` (`queued` / `running` / `succeeded` / `failed`), log tails, and timing info.

### Fetch result

```bash
curl http://127.0.0.1:18080/v1/jobs/{job_id}/result
```

Returns trajectory file paths, instance IDs, exit statuses, and artifact locations.

## SSH Tunnel Details

Both tunnels are managed automatically by the scripts. Here's what happens under the hood:

### Model reverse tunnel (A exposes SGLang to B)

```bash
# Initiated by: bash scripts/model_serving/start_remote_tunnel.sh
ssh -i $KEY -N -R 127.0.0.1:32000:127.0.0.1:30000 user@taurus
```

- Server A's `:30000` (SGLang) becomes accessible at Server B's `:32000`
- PID file: `outputs/model_serving/model_tunnel_32000.pid`
- Manage: `status_remote_tunnel.sh`, `stop_remote_tunnel.sh`

### Service local forward (A accesses B's rollout service)

```bash
# Initiated by: bash scripts/remote_client/open_tunnel.sh (auto-called by run_rollout.sh)
ssh -i $KEY -N -L 127.0.0.1:18080:127.0.0.1:18080 user@taurus
```

- Server B's `:18080` (rollout service) becomes accessible at Server A's `:18080`
- PID file: `outputs/remote_client/service_tunnel_18080.pid`
- Cleanup: `reset_connections.sh`

Both tunnels use keepalive (`ServerAliveInterval=30`) and auto-accept new host keys.

## Troubleshooting

**"SGLang not reachable"** — Make sure SGLang is running on Server A. Check with `bash scripts/model_serving/test_sglang.sh`.

**"Server B cannot reach SGLang via tunnel"** — The reverse tunnel may have died. Restart it: `bash scripts/model_serving/stop_remote_tunnel.sh && bash scripts/model_serving/start_remote_tunnel.sh`.

**"Rollout service not reachable"** — Make sure the service is running on Server B. SSH into taurus and check: `bash scripts/agent_runtime/status_service.sh`.

**"Port already in use"** — Kill stale tunnels: `bash scripts/remote_client/reset_connections.sh`. On Server B, check for zombie services: `lsof -i :18080`.

**LiteLLM cost tracking errors** — Set `MSWEA_COST_TRACKING=ignore_errors` in `agent_rollout.local.env` (the setup wizard does this by default).

**Docker permission denied on Server B** — Make sure your taurus user is in the `docker` group, or use `sudo` for Docker commands.
