# Rollout Bootstrap 实践记录

更新时间：2026-03-21

## 1. 结论

阶段目标已经达成：

- 服务器 A 上成功启动 SGLang，并对外提供 OpenAI-compatible 接口
- 服务器 B 上成功通过 mini-swe-agent-plus 在 Docker 中跑通单实例 SWE-bench rollout
- 服务器 B 上成功跑通小规模 batch rollout（`--slice 0:3 --workers 2`）

当前结论只覆盖 rollout 链路，不包含：

- 训练
- teacher
- OPD
- reward / verifier 接入
- Slime 训练集成

## 2. 实际可用架构

实际跑通的链路不是“服务器 B 直接访问服务器 A 的公网服务”，而是：

1. 服务器 A 在计算节点上启动 SGLang
2. 服务器 A 主动 SSH 到服务器 B，建立 reverse tunnel
3. 服务器 B 通过本地 `127.0.0.1:<forwarded_port>` 调用服务器 A 上的 SGLang
4. mini-swe-agent-plus 在服务器 B 的 Docker 容器中完成 SWE-bench rollout

这是当前环境下最稳的方案，因为：

- Delta 登录需要密码和 Duo，不适合让服务器 B 反向自动登录服务器 A
- 服务器 A 到服务器 B 的主动 SSH 更容易做长期连接

## 3. 关键配置

### 服务器 A

推荐直接用 Hugging Face repo id 作为 `SGLANG_MODEL_PATH`，例如：

```env
SGLANG_MODEL_PATH=Kwai-Klear/Klear-AgentForge-8B
SGLANG_HOST=0.0.0.0
SGLANG_PORT=30000
SGLANG_TP=1
SGLANG_MEM_FRACTION_STATIC=0.80
SGLANG_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
```

### 服务器 B

`agent_rollout.local.env` 里最关键的几项：

```env
MINI_SWE_AGENT_PLUS_ROOT=<服务器B上的绝对路径>
REMOTE_API_BASE=http://127.0.0.1:31000
REMOTE_API_KEY=EMPTY
REMOTE_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
REMOTE_PROVIDER=openai
REMOTE_TEMPERATURE=0.0
REMOTE_DROP_PARAMS=true
MSWEA_COST_TRACKING=ignore_errors
MINI_BASE_CONFIG=<服务器B上的 mini-swe-agent-plus>/src/minisweagent/config/extra/swebench.yaml
```

注意：

- 服务器 B 的目录结构可以和服务器 A 完全不同
- 这里只要求填服务器 B 自己的绝对路径

## 4. 实际操作顺序

### Step 1：在服务器 A 上启动 SGLang

```bash
bash scripts/model_serving/start_sglang.sh
```

### Step 2：验证服务器 A 的接口

推荐优先用 `curl` 验证：

```bash
curl -s http://<A_IP>:30000/v1/models
curl -s http://<A_IP>:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

### Step 3：在服务器 A 上建立 reverse tunnel 到服务器 B

从真正运行 SGLang 的计算节点执行：

```bash
ssh -i /u/zhe3/.ssh/taurus_ssh_key \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N \
  -R 127.0.0.1:31000:127.0.0.1:30000 \
  zhongmouhe@taurus.cs.ucsb.edu
```

### Step 4：在服务器 B 上验证 tunnel

```bash
curl -s http://127.0.0.1:31000/v1/models
curl -s http://127.0.0.1:31000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

### Step 5：在服务器 B 上做 rollout 侧 smoke test

```bash
bash scripts/agent_rollout/doctor.sh
```

### Step 6：跑单实例

```bash
bash scripts/agent_rollout/run_swebench_single.sh sympy__sympy-15599
```

### Step 7：跑小 batch

```bash
bash scripts/agent_rollout/run_swebench_batch.sh --slice 0:3 --workers 2
```

## 5. 本次踩坑记录

### 5.1 `scripts/lib` 被 `.gitignore` 误伤

顶层 `.gitignore` 有通用规则 `lib/`，导致 `scripts/lib/common.sh` 没有被正确同步。

修复方式：

- 将公共脚本目录改名为 `scripts/common/common.sh`

### 5.2 命令行覆盖的环境变量被 `.env` 再次覆盖

之前的 `load_bootstrap_env` 在 `source` env 文件后，会把命令行传入的变量覆盖掉。例如：

```bash
SGLANG_HOST=141.142.254.201 bash scripts/model_serving/check_openai_chat.sh
```

会被 `.env` 中的 `SGLANG_HOST=0.0.0.0` 覆盖。

修复方式：

- env 加载逻辑改为“命令行显式设置优先”

### 5.3 `health_generate` 空响应导致误报

SGLang 的 `/health_generate` 在当前环境下可能返回空 body，但服务本身是正常的。

修复方式：

- `check_http.sh` 不再要求 `health_generate` 必须返回 JSON
- 对 `health_generate` 只要求 HTTP 可达

### 5.4 `check_openai_chat.sh` 不如直接 `curl` 稳

在当前集群环境中，Python SDK/HTTP 客户端链路一度出现不稳定行为，而 `curl` 能稳定验证真实服务状态。

经验结论：

- 首次排障时优先使用 `curl`
- 脚本 smoke 主要用于回归验证，不要替代基础网络诊断

### 5.5 `swebench_add_edit_tool.yaml` 不适合当前单实例入口

该模板依赖 `{{working_dir}}`，但 `swebench_single.py` 当前上下文里没有提供这个变量，导致：

- `jinja2.exceptions.UndefinedError: 'working_dir' is undefined`

修复方式：

- 改用 `swebench.yaml` 作为 `MINI_BASE_CONFIG`

### 5.6 LiteLLM 不认识自定义模型名的成本映射

当模型名为 `Kwai-Klear/Klear-AgentForge-8B` 时，LiteLLM 的 cost calculator 不认识这个模型，导致 rollout 在成本统计阶段报错。

修复方式：

- 在服务器 B 环境中设置：

```env
MSWEA_COST_TRACKING=ignore_errors
```

### 5.7 batch 入口和单实例入口对 environment 配置的假设不同

`swebench_pool_way.py` 会直接调用：

```python
DockerEnvironment(**config["environment"])
```

而 `DockerEnvironmentConfig` 不接受 `environment_class` 字段，于是 batch 报错。

修复方式：

- 在生成 rollout config 时，如果 `environment_class == "docker"`，则移除该字段

## 6. 当前验收标准

可以认定阶段完成的标准：

1. 服务器 A 上 `curl /v1/models` 和 `curl /v1/chat/completions` 正常
2. reverse tunnel 建立成功，服务器 B 可访问 `127.0.0.1:31000`
3. `doctor.sh` 跑通
4. 单实例 rollout 跑通并生成 trajectory
5. 小 batch rollout 跑通并生成 `preds.json` 与多个 trajectory

## 7. 下一步建议

当前 rollout 链路已经具备继续集成到 Slime 的前置条件。下一阶段建议按以下顺序推进：

1. 明确要保留哪些 trajectory 字段
2. 设计从 mini-swe-agent-plus trajectory 到 Slime `Sample` 的转换
3. 再讨论如何把这条 rollout 链接入训练、teacher 和 OPD
