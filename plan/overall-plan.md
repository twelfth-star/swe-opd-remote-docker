# Overall Plan

更新时间：2026-03-21

## 1. 总体策略

整个项目按“先打通基础设施，再接 rollout，再接训练”的顺序推进。

推荐按以下阶段推进：

1. Bootstrap：打通远程 SGLang 模型服务与 mini-swe-agent-plus rollout
2. Slime Integration：把 rollout 能力以自定义 `rollout-function-path` 的方式接入 `slime`
3. Reward And Evaluation：补齐 reward、trajectory schema、数据落盘与评测
4. Teacher And OPD：引入 teacher 与 OPD
5. Training：开始真正的训练、监控与迭代

## 2. 阶段拆分

### Bootstrap：Rollout Bootstrap

目标：

- 不做训练
- 不管 teacher
- 不管 OPD
- 只验证 A/B 双机 rollout 体系

产物：

- 模型服务侧可用的 SGLang endpoint
- rollout 侧可用的 mini-swe-agent-plus rollout
- 单实例与小 batch 运行记录

### Slime Integration

目标：

- 通过 `slime` 的 `--rollout-function-path` 接入自定义 rollout
- 让 `slime` 可以请求外部 rollout 服务，收回轨迹并组织成 `Sample`

产物：

- 自定义 rollout 函数
- A/B 间的 rollout RPC 协议
- trajectory -> `Sample` 的转换逻辑

### Reward And Evaluation

目标：

- 明确 rollout 输出的 reward 来源
- 确定 patch / submission / metadata schema
- 跑通评测与回放

产物：

- reward 方案
- rollout 产物格式
- 最小评测流程

### Teacher And OPD

目标：

- 引入 teacher
- 决定使用 `megatron` teacher 还是 `sglang` teacher
- 把 teacher logprob 接进训练链路

产物：

- teacher 侧部署方案
- token 对齐方案
- OPD 配置与验证计划

### Training

目标：

- 让完整训练链路稳定运行
- 跟踪 rollout、训练吞吐、成功率、失败率

产物：

- 训练脚本
- 监控面板
- 调参与回归测试流程

## 3. 为什么先做 Bootstrap

先做 Bootstrap 的原因：

1. 当前最大不确定性不是训练，而是双机交互能否稳定跑通
2. 如果远程 SGLang 无法被 rollout 侧的 LiteLLM 稳定消费，后续训练都无从谈起
3. 如果 rollout 侧的 Docker 流程本身不稳定，那么接入 `slime` 只会放大问题
4. 先把系统边界清楚分开，更容易定位错误与压测瓶颈

## 4. 当前建议的系统形态

在 Bootstrap 阶段中：

- 模型服务侧只负责模型服务
- agent rollout 侧只负责 agent rollout
- `slime` 暂时不进入主链路

即：

1. 模型服务侧：SGLang server
2. rollout 侧：mini-swe-agent-plus + Docker + SWE-bench
3. rollout 侧 -> 模型服务侧：LiteLLM / OpenAI-compatible API 调用

## 5. 阶段切换条件

只有当 Bootstrap 完成后，才进入 Slime Integration。

Bootstrap -> Slime Integration 的切换条件：

1. 模型服务侧的 SGLang 服务稳定
2. rollout 侧的单实例 rollout 稳定
3. rollout 侧的小 batch rollout 稳定
4. 常见失败模式已经有明确排查路径

## 6. 主要风险

### 基础设施风险

- 模型服务侧到 rollout 侧的网络访问不稳定
- 模型服务侧的 SGLang 显存占用与并发能力不足
- rollout 侧的 Docker 启动和镜像拉取过慢

### 接口风险

- LiteLLM 与 SGLang 的参数兼容性问题
- mini-swe-agent-plus 对远程模型配置不完整
- 某些模型参数需要在 `model_kwargs` 中显式透传

### 运行风险

- 单个 SWE-bench episode 很长，超时风险高
- rollout 侧并发 Docker 容器过多时容易产生资源抖动
- 模型服务侧单服务承载多 episode 并发时可能出现吞吐瓶颈
