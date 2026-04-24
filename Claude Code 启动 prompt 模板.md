# Claude Code 启动 prompt 模板

> **用途**：编码阶段开新会话或召子代理执行某个 WP 时，套此模板生成启动 prompt。格式借鉴 ChatGPT 工作包清单的每包启动 prompt（验证过对 Claude Code 最友好）。
>
> **使用方式**：复制下面的「标准模板」，把 `{{占位符}}` 替换为 WP 实际内容（时点/交付/DoD/禁做 等），喂给 Claude Code 即可。
>
> **版本**：v1.0 · 2026-04-24

---

## 标准模板

```text
你现在负责工作包 {{WP-编号}} ·《{{WP 名称}}》。

项目背景：
- 中国期货 Mac/iPad 原生专业工作台 / 终端
- 当前阶段：{{Stage A 或 Stage B}}
- 本包目标：{{WP 一句话目标}}

项目主文档（按需读）：
- /home/beelink/macos_tmp/macos_futures_trading_v1/D1-顶层设计.md
- /home/beelink/macos_tmp/macos_futures_trading_v1/D2-阶段A执行.md
- /home/beelink/macos_tmp/macos_futures_trading_v1/D3-风险与危机预案.md
- /home/beelink/macos_tmp/macos_futures_trading_v1/产品设计书.md
- /home/beelink/macos_tmp/macos_futures_trading_v1/Stage A 工作包清单.md（本 WP 所在）
- /home/beelink/macos_tmp/macos_futures_trading_v1/StageA-补遗与深化.md（如本 WP 涉及补遗 gap）
- /home/beelink/macos_tmp/macos_futures_trading_v1/Legacy迁移融合方案.md（如本 WP 涉及 Legacy 代码迁移）
- /home/beelink/macos_tmp/macos_futures_trading_v1/chatgpt_工作包清单/{{对应 ChatGPT 包路径 · 若有}}

执行要求：
1. 先阅读仓库内相关模块与本项目的关键文档。
2. 先给出实施计划，再开始改代码。
3. 严格遵守本工作包的"范围 In"、"范围 Out"、"禁做项"、"验收标准"。
4. 产出代码的同时，必须补：
   - 必要的单元测试（核心业务逻辑覆盖率 ≥ 70%）
   - 必要的文档（如 `docs/<模块>/README.md` 或 ADR 关键决策）
   - 关键设计决策说明
5. 完成后输出：
   - 改了哪些文件
   - 如何验证（跑什么命令 / 看什么指标）
   - 还有哪些风险和后续建议

本工作包范围内必须交付：
{{交付物列表 - 来自 WP-XX 交付字段}}

范围外（本包不做）：
{{范围 Out - 明确声明不在本包工作范围的内容，避免 scope creep}}

验收标准（Definition of Done）：
{{DoD 列表 - 可验证的硬标准}}

禁做项（必须避免）：
{{禁做项 - 来自 WP 或 ChatGPT 对应包}}

前置依赖（先确认完成）：
{{依赖 WP 列表}}

统一技术约束（全项目通用，勿违反）：
- 技术栈：Swift 6（严格并发）/ SwiftUI + AppKit / Metal 自研 / SQLite / CloudKit + 阿里云自建 / Go 后端 / PostgreSQL / Apple IAP
- 产品原则冲突优先级：稳定可信 > 速度 > 现金流 > 发版节奏
- 性能红线（Metal 图表相关 WP 必守）：10w K 线 60fps / 冷启动 <1s / 交互 <100ms / Tick <1ms / 内存 <500MB
- 敏感数据加密分级：凭证 → Keychain / 交易日志 → SQLCipher / 其他 → 明文
- 境内合规：用户敏感数据不出境（CloudKit 仅存 UI 偏好和自选列表等非敏感数据）
- 话术红线：不宣传"100% 兼容文华"；不做下单建议；不做个性化投资建议
- Stage A 不做：CTP 实盘下单 / Python 集成 / iPhone 版 / Windows 版 / 社区自媒体

开工前先确认：
- 是否读懂本包目标？
- 是否了解前置 WP 已完成？
- 是否了解项目统一技术约束？
- 实施计划是否回避了所有禁做项？
```

---

## 示例填充（WP-40 Metal 图表引擎）

```text
你现在负责工作包 WP-40 ·《Metal 图表引擎（核心差异化）》。

项目背景：
- 中国期货 Mac/iPad 原生专业工作台 / 终端
- 当前阶段：Stage A
- 本包目标：交付 10 万根 K 线 60fps、支持多窗口同屏、Metal 自研的图表基础引擎（Mac 原生核心差异化）。

项目主文档（按需读）：
- /home/beelink/macos_tmp/macos_futures_trading_v1/D2-阶段A执行.md（§2 MVP §4 技术栈）
- /home/beelink/macos_tmp/macos_futures_trading_v1/产品设计书.md（§3.1 模块① / §3.4 性能基准）
- /home/beelink/macos_tmp/macos_futures_trading_v1/Stage A 工作包清单.md（WP-40）
- /home/beelink/macos_tmp/macos_futures_trading_v1/Legacy迁移融合方案.md（KLineChartView 拆分参考）
- /home/beelink/macos_tmp/macos_futures_trading_v1/chatgpt_工作包清单/stage-a/A03-Metal 图表引擎 v1.md

执行要求：
1. 先阅读 Legacy KLineChartView（985 行）并输出拆分方案
2. 先给实施计划，再开始改代码
3. 严格遵守范围 / 验收 / 禁做
4. 交付代码 + 单元测试 + benchmark + ADR

本工作包范围内必须交付：
- ChartCore 渲染管线（Swift Package 模块）
- SwiftUI/AppKit 交互层桥接
- 多周期切换（1m/5m/15m/30m/1h/4h/日/周/月）
- 多窗口布局（最多 6 同屏）
- 性能 benchmark 工具
- 图表内状态展示（加载中/断线/无数据）

范围外（本包不做）：
- 具体指标实现（归 WP-41）
- 画线工具（归 WP-42）
- Apple Pencil（Stage B）
- 外接屏专业模式（Stage B）

验收标准：
- 10 万根 K 线滚动+缩放无掉帧（<16ms 单帧）
- 单 Tick 更新不整屏重绘
- 至少支持 6 个同屏图表容器
- 冷启动 <1s，首次交互 <100ms
- 内存占用（1000 合约 + 6 图表）<500MB
- benchmark 报告可重复执行，数字入 CI

禁做项：
- ❌ 不把指标计算放在渲染线程
- ❌ 不依赖 WebView 图表库兜底
- ❌ 不把 Metal Shader 和 UI 状态混写
- ❌ 不用非原生帧控制（必须用 CADisplayLink / MTKView delegate）

前置依赖（先确认完成）：
- WP-20 Metal PoC（M1 Week 2-3）
- WP-24 Swift Package 骨架（M1 Week 2-3）
- WP-31 Legacy KLineChartView 融合（M2-M3）

统一技术约束（全项目通用，勿违反）：
- 性能红线（严格遵守）：10w K 线 60fps / 冷启动 <1s / 交互 <100ms / Tick <1ms / 内存 <500MB
- 任何 PR 触发任一指标倒退 → 自动 block merge（WP-96 CI 门禁）
- 产品原则优先级：稳定 > 速度 > 现金 > 节奏
```

---

## 使用提示

### 什么时候用
- 开新会话推进某个 WP（建议：每个 WP 独立会话，避免上下文污染）
- 召子代理执行（`Agent` 工具，subagent_type 选 general-purpose 或 feature-dev）
- 把 prompt 截图发给合作者（Cursor / 人类）

### 什么时候不用
- 跨多个 WP 的纯研究任务（用更灵活的 prompt）
- 项目管理类任务（更新状态、改文档）
- 审阅类任务（见 gap 审阅类 prompt 另写）

### 填充顺序（减少来回修）
1. 从 `Stage A 工作包清单.md` 找 WP-XX 复制 6 要素
2. 从 `工作包映射表.md` 找 ChatGPT 对应包（若有）读取禁做/范围 Out
3. 从 `chatgpt_工作包清单/` 复制启动 prompt 参考
4. 合并套入标准模板

### 常见禁做项库（可复用）
| 场景 | 禁做项 |
|-----|------|
| 图表渲染 | 不在渲染线程算指标 / 不用 WebView 兜底 / 不混写 Shader 和 UI 状态 |
| 订阅门控 | 不在业务层散落 `if Pro` 判断 / 不做 7 天免费试用暗扣 |
| CTP 交易 | 不把 CTP 原始回调暴露给 UI 层 / 不把安全模式做成仅提示不阻断 |
| 交易日志 | 不把原始交割单直接当业务模型 / 不让日志编辑反向污染成交数据 |
| 行情管线 | 不把历史读取和实时流写成两套 UI / 不先上复杂消息总线 |
| 架构 | 不为 Stage A 未验证需求上重架构 / 不把 UI 状态和业务状态混写单 ViewModel |
| 麦语言 | 不承诺 100% 兼容文华 / 不逆向文华二进制格式 |
| iPad | 不把 Mac UI 缩放搬到 iPad / Stage A 不做完整专业模式 |
| 合规 | 不把合规当"上线后再补" / 不把境外 CloudKit 用于敏感数据 |

---

## 修订日志

| 日期 | 版本 | 修订 |
|------|------|-----|
| 2026-04-24 | v1.0 | 初稿 · 基于 ChatGPT 清单 11 节格式提炼 + 示例 WP-40 + 禁做库 |
