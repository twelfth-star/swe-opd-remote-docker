# Rollout Bootstrap Plan: Remote SGLang Serving + mini-swe-agent-plus Rollout

更新时间：2026-03-21

## 1. 本阶段目标

本阶段只做一件事：

把“远程 SGLang 提供模型服务、mini-swe-agent-plus 在 Docker 中完成 SWE-bench rollout”这条链路打通。

本阶段不做：

- 训练
- teacher
- OPD
- reward 设计
- Slime 接入

## 2. 目标架构

### 模型服务侧

职责：

- 启动 SGLang 服务
- 暴露 OpenAI-compatible API
- 为服务器 B 的 agent rollout 提供推理能力

### agent rollout 侧

职责：

- 运行 mini-swe-agent-plus
- 在 Docker 中执行 SWE-bench 环境交互
- 通过 LiteLLM 请求服务器 A 的模型服务

### 调用关系

1. 用户在 rollout 侧启动 mini-swe-agent-plus
2. mini-swe-agent-plus 通过 LiteLLM 请求远程 SGLang
3. 模型服务侧返回模型响应
4. rollout 侧在 Docker 容器中执行命令并推进 agent episode
5. rollout 侧输出 trajectory、patch、日志

## 3. 具体执行计划

### Step 1：启动远程 SGLang 模型服务

目标：

- 起一个最小可用、可被远程访问的 SGLang 服务

要求：

1. 使用 `--host 0.0.0.0`
2. 明确服务端口
3. 明确模型路径与模型名
4. 先完成本机自测

验收标准：

1. 本机可访问 health endpoint
2. 本机可通过 OpenAI-compatible chat API 正常返回内容

### Step 2：验证 rollout 侧到模型服务侧的网络链路

目标：

- 从 rollout 侧验证能访问远程 SGLang 服务

检查项：

1. 端口是否可达
2. health 接口是否可达
3. OpenAI-compatible chat 请求是否可达

验收标准：

1. rollout 侧可以发起最小 chat request 并得到回复

### Step 3：在 rollout 侧做 LiteLLM 冒烟测试

目标：

- 在不启动 mini-swe-agent-plus 的前提下，先确认 LiteLLM 能稳定调用 A

动作：

1. 写一个最小测试脚本
2. 显式设置：
   - `model_name`
   - `api_base`
   - `custom_llm_provider`
   - `api_key`
3. 测试普通请求与失败处理

验收标准：

1. rollout 侧最小 LiteLLM 脚本可稳定调用远程模型服务
2. 返回格式符合 mini-swe-agent-plus 预期

### Step 4：为 mini-swe-agent-plus 准备远程模型配置

目标：

- 在 rollout 侧准备一个专用配置，指向远程 SGLang 服务

建议配置项：

1. `model.model_name`
2. `model.model_kwargs.api_base`
3. `model.model_kwargs.custom_llm_provider`
4. `model.model_kwargs.api_key`
5. `model.model_kwargs.temperature`
6. `model.model_kwargs.drop_params`

约束：

1. 第一阶段只用单个 endpoint
2. 不依赖本地多 vLLM 地址文件机制

验收标准：

1. mini-swe-agent-plus 在 rollout 侧能读取该配置并完成一次模型调用

### Step 5：跑通单实例 SWE-bench rollout

目标：

- 在 rollout 侧先跑单实例，而不是 batch

动作：

1. 使用单实例入口
2. 先选一个容易复现、镜像较稳定的实例
3. 提前拉取相关 Docker image
4. 记录 trajectory 与错误日志

验收标准：

1. 单实例可跑完
2. 输出 trajectory 文件
3. 产出最终 submission / patch

### Step 6：跑通小规模并行 batch

目标：

- 在 rollout 侧验证并行 rollout，而不是只验证单实例

动作：

1. 先从很小的并行度开始
2. 控制：
   - `workers`
   - Docker 启动并发
3. 从 3 到 5 个实例开始做 batch 验证

验收标准：

1. 小 batch 可完成
2. 模型服务侧未出现明显不稳定
3. rollout 侧 Docker 并发未导致严重抖动

## 4. 输出物

本阶段结束后，应至少有以下输出物：

1. 远程 SGLang 启动命令或脚本
2. rollout 侧的远程模型配置文件
3. rollout 侧的 LiteLLM 冒烟测试脚本
4. 单实例 rollout 运行说明
5. 小 batch rollout 运行说明
6. 错误排查 checklist

## 5. 排错顺序

如果端到端流程失败，排查顺序如下：

1. 模型服务侧的 SGLang 是否本机可用
2. rollout 侧是否能连通远程模型服务
3. LiteLLM 最小脚本是否可用
4. mini-swe-agent-plus 是否能正常加载配置
5. Docker 容器是否能正常启动
6. SWE-bench 实例是否本身存在环境问题

## 6. 阶段完成标准

当以下条件全部满足时，本阶段完成：

1. 远程 SGLang 稳定运行
2. rollout 侧 LiteLLM 能稳定调用远程模型服务
3. rollout 侧单实例 SWE-bench rollout 跑通
4. rollout 侧小 batch SWE-bench rollout 跑通
5. 整个链路已有可复现的启动与验证流程

## 7. 下一阶段入口

本阶段完成后，下一阶段才考虑：

1. 是否把这条 rollout 链路接入 `slime`
2. 如何设计 rollout RPC 协议
3. 如何把 trajectory 转成 `slime` 的 `Sample`
