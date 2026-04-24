# Claude Code 可执行工作包

本包基于以下 4 份文档拆分：
- D1-顶层设计
- D2-阶段A执行
- D3-风险与危机预案
- 产品设计书

目标不是“再解释一遍规划”，而是把规划拆成 Claude Code 能直接接手执行的工作包：
- 每个工作包都包含：目标、范围、依赖、输入、要产出的文件、实施步骤、验收标准、禁做项
- 每个工作包都附一段“Claude Code 启动提示词”
- Stage A 以 **M6 上线收费** 为硬节点
- Stage B 以 **CTP 下单、麦语言高兼容、iPad 专业工作流、B2B2C** 为主轴

## 建议使用方式

1. 先读 `stage-a/00-StageA-总索引.md` 或 `stage-b/00-StageB-总索引.md`
2. 按依赖顺序执行工作包
3. 每完成一个工作包，必须满足对应的“验收标准”
4. 所有高风险包优先先做 PoC，再做正式实现

## 统一约束

- 默认技术栈：Swift 6 / SwiftUI + AppKit / Metal / SQLite / CloudKit / Go / PostgreSQL
- 默认原则：稳定可信 > 速度 > 现金流 > 发版节奏
- Stage A 不做 CTP 实盘下单
- Stage B 上线下单前，必须完成审计、断线安全模式、E&O 保险前置能力预埋
