# Rollout 完整使用手册

更新时间：2026-03-22

本文档记录当前已经整理好的完整使用方法，覆盖以下 4 个能力：

1. 在服务器 A 上部署 SGLang，并在服务器 A 上做简单测试
2. 在服务器 B 上调用服务器 A 的 SGLang，进行 `mini-swe-agent-plus` rollout，并在服务器 B 上做简单测试
3. 在服务器 B 上部署 rollout service，并在服务器 B 上做简单测试
4. 在服务器 A 上调用服务器 B 的 rollout service，并在服务器 A 上做简单测试

本文档只记录可工作的用法，不记录踩坑过程。

## 目录结构

当前脚本按职责分为 4 组：

- `scripts/model_serving/`：服务器 A 上的模型服务
- `scripts/agent_runtime/`：服务器 B 上直接跑 rollout 和 rollout service
- `scripts/remote_client/`：服务器 A 上调用服务器 B rollout service
- `scripts/shared/`：公共 shell 函数

当前最常用的脚本如下：

- 服务器 A：
  - `scripts/model_serving/start_sglang.sh`
  - `scripts/model_serving/start_sglang_nohup.sh`
  - `scripts/model_serving/test_sglang.sh`
  - `scripts/model_serving/start_remote_tunnel.sh`
  - `scripts/model_serving/status_remote_tunnel.sh`
  - `scripts/model_serving/stop_remote_tunnel.sh`
- 服务器 B：
  - `scripts/agent_runtime/test_remote_model.sh`
  - `scripts/agent_runtime/run_single.sh`
  - `scripts/agent_runtime/run_batch.sh`
  - `scripts/agent_runtime/start_service.sh`
  - `scripts/agent_runtime/start_service_nohup.sh`
  - `scripts/agent_runtime/status_service.sh`
  - `scripts/agent_runtime/stop_service.sh`
- 服务器 A 调服务器 B：
  - `scripts/remote_client/open_tunnel.sh`
  - `scripts/remote_client/run_rollout.sh`
  - `scripts/remote_client/reset_connections.sh`

## 总体拓扑

当前系统中各角色如下：

- 服务器 A：GPU 节点，运行 SGLang
- 服务器 B：支持 Docker，运行 `mini-swe-agent-plus`
- 服务器 A 通过 `ssh -R` 把模型端口暴露到服务器 B
- 服务器 B 通过本地端口访问服务器 A 的模型
- 服务器 B 还可以启动一个 rollout HTTP service
- 服务器 A 通过 `ssh -L` 把服务器 B 的 rollout service 拉回本地，然后提交 `single` 或 `batch` job

典型端口约定：

- 服务器 A 上 SGLang：`127.0.0.1:30000`
- 服务器 B 上看到的模型 tunnel：`127.0.0.1:32000`
- 服务器 B 上 rollout service：`127.0.0.1:18080`
- 服务器 A 上看到的 rollout service tunnel：`127.0.0.1:18080`

## 一、服务器 A：启动并测试 SGLang

### 1. 准备配置

在服务器 A 上：

```bash
cd /u/zhe3/re-swe/swe-opd
cp config/bootstrap/model_serving.example.env config/bootstrap/model_serving.local.env
```

一个常用配置示例如下：

```env
SGLANG_PYTHON_BIN=/projects/bdse/zhe3/uv_env/sglang/bin/python
SGLANG_MODEL_PATH=Kwai-Klear/Klear-AgentForge-8B

SGLANG_HOST=127.0.0.1
SGLANG_PORT=30000

SGLANG_LAUNCH_MODE=router
SGLANG_TP=1
SGLANG_DP_SIZE=2
SGLANG_MEM_FRACTION_STATIC=0.80

SGLANG_EXTRA_ARGS=--trust-remote-code

SGLANG_API_KEY=EMPTY
SGLANG_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
SGLANG_SMOKE_PROMPT=Reply with exactly: bootstrap-ok
```

字段说明：

- `SGLANG_PYTHON_BIN`：装了 `sglang` 的 Python 解释器
- `SGLANG_MODEL_PATH`：Hugging Face repo id 或本地模型目录
- `SGLANG_HOST`：建议填 `127.0.0.1`
- `SGLANG_PORT`：本机监听端口，默认用 `30000`
- `SGLANG_LAUNCH_MODE`：
  - `single`：单实例
  - `router`：多 GPU 模式
- `SGLANG_TP`：
  - `single` 模式下表示 tensor parallel 大小
  - `router` 模式下表示每个 worker 的 tp 大小
- `SGLANG_DP_SIZE`：
  - `router` 模式下表示 worker 数量
- `SGLANG_MEM_FRACTION_STATIC`：显存静态占用比例
- `SGLANG_EXTRA_ARGS`：可选，例如 `--trust-remote-code`
- `SGLANG_API_KEY`、`SGLANG_MODEL_NAME`、`SGLANG_SMOKE_PROMPT`：供 smoke test 使用

推荐配置：

- 单卡：

```env
SGLANG_LAUNCH_MODE=single
SGLANG_TP=1
SGLANG_DP_SIZE=1
```

- 多卡、并发更高：

```env
SGLANG_LAUNCH_MODE=router
SGLANG_TP=1
SGLANG_DP_SIZE=2
```

### 2. 启动 SGLang

前台启动：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_sglang.sh
```

后台启动：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_sglang_nohup.sh
```

后台日志默认在：

- `outputs/model_serving/start_sglang.log`

### 3. 测试 SGLang

直接运行：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/test_sglang.sh
```

它会检查：

- `/v1/models`
- `/v1/chat/completions`

也可以手动测试：

```bash
curl -s http://127.0.0.1:30000/v1/models
curl -s http://127.0.0.1:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

成功标准：

- `/v1/models` 返回模型列表
- `chat/completions` 返回合法 JSON

## 二、服务器 A：把模型自动暴露给服务器 B

服务器 B 跑 agent 时，需要访问服务器 A 上的 SGLang。当前采用 `ssh -R` 方式完成。

### 1. 在服务器 A 上补模型 tunnel 配置

仍然编辑：

- `config/bootstrap/model_serving.local.env`

增加下面这些字段：

```env
SGLANG_TUNNEL_SSH_USER=zhongmouhe
SGLANG_TUNNEL_SSH_HOST=taurus.cs.ucsb.edu
SGLANG_TUNNEL_SSH_KEY=/u/zhe3/.ssh/taurus_ssh_key
SGLANG_TUNNEL_REMOTE_HOST=127.0.0.1
SGLANG_TUNNEL_REMOTE_PORT=32000
```

含义：

- 服务器 A 会 SSH 到服务器 B
- 在服务器 B 本地监听 `127.0.0.1:32000`
- 该端口会转发到服务器 A 本地的 `127.0.0.1:30000`

### 2. 启动模型 reverse tunnel

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_remote_tunnel.sh
```

这是 `nohup` 后台脚本，会自动：

- 建日志目录
- 后台执行 `ssh -R`
- 写 pid 文件

默认输出位置：

- pid：`outputs/model_serving/model_tunnel_32000.pid`
- log：`outputs/model_serving/model_tunnel_32000.log`

### 3. 查看 tunnel 状态

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/status_remote_tunnel.sh
```

### 4. 停止 tunnel

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/stop_remote_tunnel.sh
```

### 5. 在服务器 B 上测试模型 tunnel

在服务器 B 上执行：

```bash
curl -s http://127.0.0.1:32000/v1/models
```

如果返回模型列表，说明：

- 服务器 A 上的 SGLang 已成功暴露给服务器 B

## 三、服务器 B：直接调用 A 上模型做 rollout

这一部分对应的是：

- 不经过 rollout service
- 直接在服务器 B 上运行 `mini-swe-agent-plus`

### 1. 准备配置

在服务器 B 上：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
cp config/bootstrap/agent_rollout.example.env config/bootstrap/agent_rollout.local.env
```

一个常用配置示例如下：

```env
BOOTSTRAP_PYTHON_BIN=/home/zhongmouhe/miniconda3/bin/python
MINI_PYTHON_BIN=/mnt/data2/zhongmouhe/conda_envs/sweagent/bin/python
MINI_SWE_AGENT_PLUS_ROOT=/home/zhongmouhe/swe-re/mini-swe-agent-plus

REMOTE_API_BASE=http://127.0.0.1:32000
REMOTE_API_KEY=EMPTY
REMOTE_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
REMOTE_PROVIDER=openai
REMOTE_TEMPERATURE=0.0
REMOTE_DROP_PARAMS=true
REMOTE_SMOKE_PROMPT=Reply with exactly: bootstrap-ok

MSWEA_COST_TRACKING=ignore_errors

SWEBENCH_SUBSET=verified
SWEBENCH_SPLIT=test
SWEBENCH_WORKERS=2
SWEBENCH_DOCKER_START_CONCURRENCY=1
```

字段说明：

- `BOOTSTRAP_PYTHON_BIN`：运行 `swe-opd` 自己脚本的 Python
- `MINI_PYTHON_BIN`：运行 `mini-swe-agent-plus` 的 Python
- `MINI_SWE_AGENT_PLUS_ROOT`：服务器 B 上 `mini-swe-agent-plus` 仓库绝对路径
- `REMOTE_API_BASE`：服务器 B 看到的模型地址，这里应是 `http://127.0.0.1:32000`
- `REMOTE_MODEL_NAME`：必须与服务器 A 提供的模型名一致
- `MSWEA_COST_TRACKING=ignore_errors`：避免 LiteLLM 因模型名未注册而报 cost tracking 错误

### 2. 标准配置与 add_edit_tool 配置

如果只用标准 SWE-bench 配置，在 `agent_rollout.local.env` 里设置：

```env
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src/minisweagent/config/extra/swebench.yaml
```

如果要启用 `add_edit_tool`，使用 `swe-opd` 里的兼容配置：

```env
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml
```

### 3. 如果使用 add_edit_tool，确保导入 plus 源码

在服务器 B 上执行：

```bash
export PYTHONPATH=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src:$PYTHONPATH
```

原因：

- 要确保运行时导入的是 `mini-swe-agent-plus` 仓库里的 `src/minisweagent`
- 不要导入旧的 `site-packages/minisweagent`

### 4. 简单测试远程模型调用

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/test_remote_model.sh
```

这个测试会验证：

- 渲染 rollout config
- 用 OpenAI-compatible 方式调用远程模型
- 用 `mini-swe-agent-plus` 兼容方式调用远程模型

### 5. 在服务器 B 上直接跑单实例

标准配置：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/run_single.sh sympy__sympy-15599
```

如果使用 `add_edit_tool`：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
PYTHONPATH=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src:$PYTHONPATH \
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml \
bash scripts/agent_runtime/run_single.sh sympy__sympy-15599
```

### 6. 在服务器 B 上直接跑小 batch

标准配置：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/run_batch.sh --slice 0:3 --workers 2
```

如果使用 `add_edit_tool`：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
PYTHONPATH=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src:$PYTHONPATH \
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml \
bash scripts/agent_runtime/run_batch.sh --slice 0:3 --workers 2
```

## 四、服务器 B：部署 rollout service

这一部分用于让服务器 A 主动发起 rollout。

### 1. 准备 rollout service 配置

在服务器 B 上：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
cp config/bootstrap/rollout_service.example.env config/bootstrap/rollout_service.local.env
```

一个常用配置示例如下：

```env
BOOTSTRAP_PYTHON_BIN=/home/zhongmouhe/miniconda3/bin/python
ROLLOUT_SERVICE_HOST=0.0.0.0
ROLLOUT_SERVICE_PORT=18080
ROLLOUT_SERVICE_JOB_ROOT=/home/zhongmouhe/swe-re/swe-opd/outputs/rollout_service_jobs
ROLLOUT_SERVICE_API_TOKEN=
ROLLOUT_SERVICE_MAX_WORKERS=2
```

字段说明：

- `ROLLOUT_SERVICE_HOST`：服务监听地址
- `ROLLOUT_SERVICE_PORT`：HTTP 端口，默认 `18080`
- `ROLLOUT_SERVICE_JOB_ROOT`：job、日志、结果文件保存目录
- `ROLLOUT_SERVICE_API_TOKEN`：可选鉴权 token
- `ROLLOUT_SERVICE_MAX_WORKERS`：服务端可并发处理的 job 数

### 2. 前台启动 rollout service

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/start_service.sh
```

### 3. 后台启动 rollout service

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/start_service_nohup.sh
```

### 4. 查看服务状态

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/status_service.sh
```

### 5. 停止服务

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/stop_service.sh
```

### 6. 在服务器 B 上测试 rollout service

```bash
curl -s http://127.0.0.1:18080/healthz
```

成功时应返回 JSON，例如：

```json
{
  "ok": true,
  "service": "rollout",
  "jobs": 0
}
```

## 五、服务器 A：调用服务器 B 的 rollout service

这一步是“服务器 A 主动发起 rollout”的入口。

### 1. 准备服务器 A 的 client 配置

在服务器 A 上：

```bash
cd /u/zhe3/re-swe/swe-opd
cp config/bootstrap/remote_rollout_client.example.env config/bootstrap/remote_rollout_client.local.env
```

一个常用配置示例如下：

```env
BOOTSTRAP_PYTHON_BIN=/u/zhe3/miniconda3/bin/python3

REMOTE_ROLLOUT_SERVICE_BASE=http://127.0.0.1:18080
REMOTE_ROLLOUT_API_TOKEN=

REMOTE_ROLLOUT_USE_SSH_TUNNEL=true

REMOTE_ROLLOUT_SSH_USER=zhongmouhe
REMOTE_ROLLOUT_SSH_HOST=taurus.cs.ucsb.edu
REMOTE_ROLLOUT_SSH_KEY=/u/zhe3/.ssh/taurus_ssh_key

REMOTE_ROLLOUT_LOCAL_PORT=18080
REMOTE_ROLLOUT_REMOTE_HOST=127.0.0.1
REMOTE_ROLLOUT_REMOTE_PORT=18080

REMOTE_MODEL_TUNNEL_REMOTE_PORT=32000
REMOTE_ROLLOUT_WAIT_TIMEOUT=0
```

字段说明：

- `REMOTE_ROLLOUT_SERVICE_BASE`：服务器 A 本地看到的 rollout service 地址
- `REMOTE_ROLLOUT_USE_SSH_TUNNEL=true`：表示脚本会自动建立本地 `ssh -L`
- `REMOTE_ROLLOUT_SSH_USER`、`REMOTE_ROLLOUT_SSH_HOST`、`REMOTE_ROLLOUT_SSH_KEY`：服务器 B SSH 信息
- `REMOTE_ROLLOUT_LOCAL_PORT`：服务器 A 本地端口
- `REMOTE_ROLLOUT_REMOTE_HOST`、`REMOTE_ROLLOUT_REMOTE_PORT`：服务器 B 上 rollout service 的地址
- `REMOTE_MODEL_TUNNEL_REMOTE_PORT=32000`：供重置脚本清理 A→B 模型 tunnel 时使用
- `REMOTE_ROLLOUT_WAIT_TIMEOUT=0`：表示无限等待 job 结束

### 2. 单独建立服务器 A 到服务器 B rollout service 的本地 tunnel

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/open_tunnel.sh
```

这一步会自动建立：

- `A:127.0.0.1:18080 -> B:127.0.0.1:18080`

### 3. 测试服务器 A 是否已经能访问 rollout service

```bash
curl -s http://127.0.0.1:18080/healthz
```

如果能返回 JSON，说明：

- 服务器 A 已能访问服务器 B 的 rollout service

### 4. 在服务器 A 上运行单实例远程 rollout

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/run_rollout.sh single sympy__sympy-15599
```

这个脚本会自动：

1. 打开到服务器 B 的本地 tunnel
2. 提交一个 `single` job
3. 等待 job 完成
4. 拉取结果 JSON
5. 保存到服务器 A 本地

结果默认保存到：

- `outputs/remote_client/results/<job_id>.json`

### 5. 在服务器 A 上运行 batch 远程 rollout

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/run_rollout.sh batch --slice 0:3 --workers 2
```

### 6. 查询远程 job 进度

如果你想手动查看 job 状态，可以直接调用 rollout service：

```bash
curl -s http://127.0.0.1:18080/v1/jobs/<job_id>
```

如果要取结果：

```bash
curl -s http://127.0.0.1:18080/v1/jobs/<job_id>/result
```

说明：

- `run_rollout.sh` 默认会等待 job 完成
- 如果 job 很久没结束，可以通过上面两个接口查看进度
- 即使本地 `run_rollout.sh` 被中断，服务器 B 上的 job 仍然会继续跑

### 7. 重置连接

如果你想在服务器 A 上一把清理常见连接，重新开始，可以执行：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/reset_connections.sh
```

它会尝试清理：

- 服务器 A 到服务器 B rollout service 的本地 tunnel
- 服务器 A 到服务器 B模型 reverse tunnel 的 pid 记录

## 六、推荐的完整执行顺序

如果你要从零开始完整跑一遍，推荐顺序如下。

### 阶段 1：服务器 A 起模型

在服务器 A 上：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_sglang_nohup.sh
bash scripts/model_serving/test_sglang.sh
```

### 阶段 2：服务器 A 把模型暴露给服务器 B

在服务器 A 上：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_remote_tunnel.sh
bash scripts/model_serving/status_remote_tunnel.sh
```

### 阶段 3：服务器 B 直接测试模型调用

在服务器 B 上：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/test_remote_model.sh
```

### 阶段 4：服务器 B 启动 rollout service

在服务器 B 上：

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/start_service_nohup.sh
bash scripts/agent_runtime/status_service.sh
```

### 阶段 5：服务器 A 调服务器 B 做 rollout

在服务器 A 上：

单实例：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/run_rollout.sh single sympy__sympy-15599
```

小 batch：

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/remote_client/run_rollout.sh batch --slice 0:3 --workers 2
```

## 七、当前成功标准

当前这套流程已经覆盖并支持以下使用方式：

- 服务器 A 上启动并测试 SGLang
- 服务器 A 自动建立到服务器 B 的模型 reverse tunnel
- 服务器 B 直接访问服务器 A 上模型并做单实例 rollout
- 服务器 B 直接访问服务器 A 上模型并做小 batch rollout
- 服务器 B 部署 rollout service
- 服务器 B 本地测试 rollout service
- 服务器 A 自动建立到服务器 B 的 rollout service tunnel
- 服务器 A 调用服务器 B 的 `single` rollout
- 服务器 A 调用服务器 B 的 `batch` rollout
- 支持标准 SWE-bench 配置
- 支持 `add_edit_tool` 兼容配置

## 八、常用最短命令

### 服务器 A

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_sglang_nohup.sh
bash scripts/model_serving/test_sglang.sh
bash scripts/model_serving/start_remote_tunnel.sh
bash scripts/model_serving/status_remote_tunnel.sh
bash scripts/remote_client/run_rollout.sh single sympy__sympy-15599
bash scripts/remote_client/run_rollout.sh batch --slice 0:3 --workers 2
bash scripts/remote_client/reset_connections.sh
```

### 服务器 B

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_runtime/test_remote_model.sh
bash scripts/agent_runtime/run_single.sh sympy__sympy-15599
bash scripts/agent_runtime/run_batch.sh --slice 0:3 --workers 2
bash scripts/agent_runtime/start_service_nohup.sh
bash scripts/agent_runtime/status_service.sh
bash scripts/agent_runtime/stop_service.sh
```
