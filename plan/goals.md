# Project Goals

更新时间：2026-03-21

## 1. 总体目标

本项目的长期目标是构建一套基于以下组件的 agentic 软件工程训练体系：

- 训练框架：`slime`
- agent scaffold：`mini-swe-agent-plus`
- 任务环境：`SWE-bench`
- 推理后端：`SGLang`

最终希望支持的能力是：

1. student 模型通过 agent scaffold 与真实 repo / 环境交互
2. rollout 数据可被 `slime` 消费
3. 后续可在此基础上接入 reward、teacher、OPD 和训练流程

## 2. 当前阶段目标

当前阶段只做基础设施与 rollout 闭环，不做训练相关工作。

本阶段目标是：

1. 在模型服务侧稳定启动 SGLang 服务
2. 在 agent rollout 侧通过 Docker 运行 mini-swe-agent-plus
3. 让 rollout 侧通过 LiteLLM 调用远程 SGLang OpenAI-compatible API
4. 跑通一条端到端的 SWE-bench rollout 流程

## 3. 当前阶段明确不做的事

当前阶段不包含：

- Slime 训练接入
- policy update
- reward model
- teacher model
- on-policy distillation
- trajectory 到训练样本的转换
- teacher / student token-level logprob 对齐

## 4. 当前阶段成功标准

当以下条件全部满足时，认为当前阶段完成：

1. 模型服务侧的 SGLang 可通过远程 `chat/completions` 调用
2. agent rollout 侧的 LiteLLM 能稳定调用远程模型服务
3. agent rollout 侧能成功跑完至少 1 个 SWE-bench 单实例 rollout
4. agent rollout 侧能成功跑完一个小规模并行 batch
5. 失败时能够区分问题来源：
   - 网络连接
   - SGLang 服务
   - LiteLLM 配置
   - Docker / SWE-bench 环境
   - mini-swe-agent-plus scaffold

## 5. 当前阶段产物

本阶段的预期产物包括：

1. 模型服务侧的 SGLang 启动方式与配置
2. agent rollout 侧的 mini-swe-agent-plus 远程模型配置
3. 一份可重复执行的单实例验证流程
4. 一份可重复执行的小 batch 验证流程
5. 一份问题排查清单

## 6. 关键约束

当前已知约束：

1. 模型服务侧有 GPU，但不支持 Docker
2. agent rollout 侧支持 Docker，但没有 GPU
3. mini-swe-agent-plus 通过 LiteLLM 调用模型
4. SWE-bench rollout 依赖 Docker 容器环境
5. 当前阶段应尽量避免把 `slime` 引入链路，先单独验证 rollout 系统本身
