# Stage A 架构基线 · WP-24 Swift Package 8 Core 骨架

> 本文档是 WP-24 的核心交付物。描述 Stage A 阶段工程架构的起点。
>
> **版本**：v1.0 · 2026-04-24
> **对应 WP**：WP-24（Stage A 工作包清单）· ChatGPT A01
> **源起决策**：`工作包映射表.md` §Legacy 5 targets ↔ WP-24 8 Core

---

## 1. 设计原则（承自 D1 / Karpathy）

- **手术式**：Stage A 只建骨架（空 Core + 占位 + 测试通过），不一次性堆完整 App/Backend/CI
- **可验证**：`swift build` 无错无警告 · `swift test` 全绿
- **低耦合**：8 Core 业务域独立，依赖关系成 DAG（下方），无循环
- **Sendable 优先**：Swift 6 严格并发从骨架日起落地
- **Legacy 友好**：8 Core 边界与 Legacy 5 targets 对齐，迁入无障碍

## 2. 8 Core 业务域边界

| Core | 职责 | 对应 Legacy | 对应 Stage A 主 WP |
|------|------|-----------|------------------|
| **Shared** | 跨端共用值类型（KLine/Tick/Order/Trade/Position/Contract/Account）| `Sources/Shared/` | WP-30 |
| **DataCore** | 行情接入 / Tick / K 线聚合 / 数据源协议（历史+实时统一）/ 合约+交易日历 | `Sources/MarketData/` + `Sources/ContractManager/` | WP-21 / WP-30 / WP-31 |
| **IndicatorCore** | 56 指标 Swift 实现 + 麦语言底层函数（共用）| `Sources/FormulaEngine/` | WP-41 / WP-62 |
| **ChartCore** | Metal 自研图表引擎 + 交互 + 多窗口 | （Legacy 用 Canvas，ChartCore 从零新写 · Metal）| WP-40 |
| **JournalCore** | 交割单导入 + 交易日志 + 复盘 8 图 | （Legacy 无，全新写）| WP-50 / WP-53 |
| **AlertCore** | 条件预警中心（价格/画线/异常 + 通知）| 评估器可复用 `Sources/TradingEngine/ConditionalOrder/` | WP-52 |
| **ReplayCore** | K 线回放（沉浸式复盘）| （Legacy 无，全新写，依赖 DataCore 统一数据源协议）| WP-51 |
| **WorkspaceCore** | 自选管理 + 多窗口布局 + 工作区模板 + CloudKit 预埋 | （Legacy 无多窗口保存，全新写）| WP-43 / WP-44 / WP-55 |

**注**：Legacy `Sources/TradingEngine/ConditionalOrder/` 迁入后作为独立 TradingCore target（Stage A 不激活下单，仅作 AlertCore 评估器来源）。Stage B 激活时对应 WP-220+。

## 3. 依赖 DAG

```
               ┌──── WorkspaceCore
               │
Shared ────────┼──── DataCore ────┬──── IndicatorCore ─── ChartCore
               │                  │                    │
               │                  ├──── JournalCore    │
               │                  │                    │
               │                  ├──── ReplayCore     │
               │                  │                    │
               │                  └──── AlertCore ─────┘
               │
               └── (所有 Core 都依赖 Shared)
```

- **无循环依赖**
- 底层：Shared（无依赖）
- 中层：DataCore（仅依赖 Shared）
- 上层：其他 6 Core 按需引用 Shared + DataCore + IndicatorCore

## 4. WP-24 刻意缩减声明（Karpathy 手术式）

**本 WP 没做但原 ChatGPT A01 列了的**（按 Stage A 节奏推迟到对应 WP）：

| 缩减项 | 原因 | 归属 WP |
|-------|-----|--------|
| macOS App / iPad App 骨架 | Stage A 先把核心库搭起来，App 层跟 WP-40 Metal 图表一起建 | WP-40 |
| Go Backend 骨架 | Stage A 后期才需后端服务 | WP-80 |
| Xcode Cloud / GitHub Actions CI | WP-96 CI benchmark 门禁会统一建 | WP-96 |
| 完整 Feature Flag 服务 | WP-23 专项建（M2 Week 5）| WP-23 |
| 完整审计日志实现 | WP-83 统一做 | WP-83 |
| `.env.example` / `xcconfig` 模板 | 部署期（M5 生产部署）再建 | WP-82 |

**不缩减的**：Package.swift + 8 Core 目录 + 占位 + 测试骨架 + 本文档 + README。这是后续所有 WP 的起点，必须一次做对。

## 5. 禁做项（WP-24 scope boundary）

- ❌ 不把 UI 状态和业务状态混写在单个 ViewModel
- ❌ 不为 Stage A 未验证需求上重架构（不做微服务 / 多租户 / 插件系统）
- ❌ 不把业务域边界和 UI 层强耦合
- ❌ 不在 Core 里 import SwiftUI/AppKit（留给 App 层）
- ❌ 不放任何具体业务代码（WP-24 只建骨架，代码进各自业务 WP）

## 6. 下一步路径

按 Stage A 工作包清单月度时间轴：

1. **WP-30 Legacy 直接拷贝**（M1-M2）：把 Legacy 5 targets 归入 8 Core 对应位置
   - `legacy-source/Sources/Shared/*` → `Sources/Shared/`
   - `legacy-source/Sources/MarketData/*` → `Sources/DataCore/`
   - `legacy-source/Sources/ContractManager/*` → `Sources/DataCore/`
   - `legacy-source/Sources/FormulaEngine/*` → `Sources/IndicatorCore/`（或并入为子目录）
   - `legacy-source/Sources/TradingEngine/ConditionalOrder/*` → 独立 TradingCore target（Stage A 不激活到 App）
2. **WP-40 Metal 图表引擎**（M2-M4）：ChartCore 填充
3. **WP-41 56 指标**（M3）：IndicatorCore 填充
4. ...（详见 `Stage A 工作包清单.md`）

## 7. 验收状态（WP-24 DoD）

- [x] 8 Core 目录就位
- [x] Package.swift 声明 8 target + 8 testTarget · DAG 清晰
- [x] 每个 Core 有占位文件 + 版本 namespace
- [x] 每个 Core 有测试骨架（Swift Testing）
- [x] 架构文档（本文件）就位
- [x] README 更新
- [ ] `swift build` 验证（正在跑）
- [ ] `swift test` 验证（正在跑）
- [ ] code-simplifier 过审（骨架代码简单，可选）

## 8. 关联文档

| 文档 | 关联 |
|------|-----|
| `Stage A 工作包清单.md` WP-24 | 本 WP 定义 |
| `工作包映射表.md` §Legacy 5 targets ↔ WP-24 8 Core | Legacy 归入策略 |
| `Legacy迁移融合方案.md` §3.1.1 / §4 | M1-M2 具体迁移动作 |
| `Claude Code 启动 prompt 模板.md` | 后续 WP 开工 prompt |
| `chatgpt_工作包清单/stage-a/A01-仓库骨架与架构基线.md` | 本 WP 的 ChatGPT 对应包 |
