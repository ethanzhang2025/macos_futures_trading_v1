# Legacy 代码迁移融合方案

> **本文档是自包含的迁移执行指南**。未来实际执行 Legacy 代码迁移时，直接读本文档即可 —— 不需要重新探查 Legacy 目录或重新分析。
>
> **Legacy 项目**：`/home/beelink/macos_tmp/macos_futures_trading/`
> **目标项目**：`/home/beelink/macos_tmp/view_cc_usaged/`（以及未来新建的 Swift 项目）
> **最后更新**：2026-04-24（第一版）
> **生成依据**：2 个 Explore agent 深度分析 Legacy 代码和设计

---

## 1. 文档使用方法

### 何时读本文档
- **代码迁移启动时**：按 §4 执行计划推进
- **具体模块细节**：查 §3 代码 map，找到源文件路径
- **决策质疑时**：查 §7 决策记录

### 何时 update 本文档
- 每个迁移里程碑完成后（Week 2 / 4 / 6 / 8）
- 发现 §3 的 map 有遗漏或错误
- 决策被推翻（记录新决策 + 原因）

---

## 2. Legacy 项目概览

### 基本信息

| 属性 | 详情 |
|------|------|
| 路径 | `/home/beelink/macos_tmp/macos_futures_trading/` |
| 语言 | **Swift 6**（严格并发，完全吻合新项目） |
| 平台 | macOS 13.0+（Ventura） |
| 代码量 | **7997 行 Swift**（Sources 3839 + App 4158） |
| 测试 | 11 个测试文件（Swift Testing 框架，~60% 覆盖） |
| 依赖 | **零外部依赖**（全自研） |
| Git 历史 | 有（`.git` 目录存在）|
| 编译验证 | **用户已在 macOS 上跑通** |

### 目录结构

```
macos_futures_trading/
├── Package.swift                    # Swift Package 根配置
├── README.md
├── Sources/                         # 核心库（5 个 target）
│   ├── Shared/                      # ★★★★★ 数据模型
│   ├── FormulaEngine/               # ★★★★★ 麦语言解析器（85%）
│   ├── MarketData/                  # ★★★ 行情 + K 线合成
│   ├── ContractManager/             # ★★★ 合约管理
│   └── TradingEngine/               # ★★★★ 条件单
├── App/                             # macOS SwiftUI App
│   ├── Views/                       # 15 个 SwiftUI 视图
│   ├── Models/                      # 画线工具等
│   └── Services/                    # Mock 交易等
├── Tests/                           # 单元测试
├── Docs/                            # 6 份设计文档（已吸收精华）
└── Resources/                       # 合约规格 JSON
```

### 代码质量评分

| 维度 | 评分 | 说明 |
|------|:---:|------|
| 架构 | ★★★★☆ | 模块划分清晰，Package 结构规范 |
| 可读性 | ★★★★☆ | 中文注释充分，变量命名规范 |
| 注释 | ★★★☆☆ | 核心模块好，UI 层不足 |
| 测试 | ★★★★☆ | 60% 覆盖，FormulaEngine 完整 |
| 可维护性 | ★★★☆☆ | `KLineChartView.swift` 985 行单文件是最大问题 |

---

## 3. 代码复用详细 map

### 3.1 🟢 直接拷贝清单（最高优先级）

| Legacy 源路径 | 目标路径（新项目）| 行数 | 复用价值 | 备注 |
|-------------|---------------|-----|--------|------|
| `Sources/Shared/*.swift` | `Sources/Shared/` | 285 | ⭐⭐⭐⭐⭐ | 所有数据模型（KLine/Order/Trade/Position/Contract/Tick/Account）· 全 Sendable · 零修改 |
| `Sources/FormulaEngine/**` | `Sources/FormulaEngine/` | 2300 | ⭐⭐⭐⭐⭐ | **最大资产**：Lexer + Parser + Interpreter + 60 内置函数 |
| `Sources/TradingEngine/ConditionalOrder/*` | `Sources/TradingEngine/` | 350 | ⭐⭐⭐⭐ | 止损/止盈/追踪/OCO/括号单框架 |
| `Sources/MarketData/KLineBuilder.swift` | `Sources/MarketData/` | ~100 | ⭐⭐⭐⭐⭐ | Tick → K 线合成 + 交易所时间对齐（难点算法）|
| `App/Models/DrawingTool.swift` | `Sources/DrawingEngine/` 或 App 层 | 246 | ⭐⭐⭐⭐ | 9 种画线工具数据模型 |
| `Tests/*`（至少 FormulaEngine 的）| `Tests/` | — | ⭐⭐⭐⭐ | 保证拷贝后功能正确性 |

**拷贝原则**：
- 原样拷贝，不做修改
- 保留所有 Sendable 标记
- 保留所有测试
- 拷贝后第一件事：新项目跑通 Legacy 测试 → 确认无编译错

### 3.2 🟡 参考改动清单（拷后需调整）

| Legacy 源路径 | 用途 | 为什么要改 | 预计改动量 |
|-------------|-----|---------|---------|
| `Sources/MarketData/SinaMarketData.swift` | 行情接入架构模板 | 新项目主用 CTP + 自建中继，Sina 只是示例 | 改为抽象 `MarketDataProvider` protocol，保留实现 |
| `Sources/MarketData/SinaQuote.swift` | 数据结构参考 | 同上 | 提取公共字段 |
| `Sources/ContractManager/*` | 合约管理模板 | 需适配真实 CTP 合约数据格式 | 30% 重写（数据加载部分）|
| `App/Views/KLineChartView.swift`（985 行）| 图表绘制逻辑参考 | **Canvas 渲染需要用 Metal 重写** + 单文件太大必须拆分 | 基本重写，但**保留 Canvas 绘制算法作为 Metal shader 参考** |
| `App/Services/MockTradingService.swift` | Mock 测试参考 | 需与真实 CTP 接口统一 protocol | 提取 `TradingService` protocol，Mock 和 CTP 都实现 |

### 3.3 ❌ 完全新写清单（Legacy 没做 / 做得太差）

| 模块 | 为什么必须新写 | 预计工作量 |
|------|-----------|---------|
| **Metal 图表引擎** | Legacy 用 Canvas（CPU），我们要 60fps Metal（GPU）· 核心差异化 | 6-8 周 |
| **CTP Bridge** | Legacy README 承诺但代码未实现 | 3-4 周 |
| **K 线回放** | Legacy 没有 | 1-2 周 |
| **交易日志**（手动补原因/情绪）| Legacy 只有 Trade 模型无日志系统 | 1-2 周 |
| **工作区模板** | Legacy 无多窗口布局保存 | 1 周 |
| **CloudKit 多端同步** | Legacy 仅 macOS 单端 | 2-3 周（Stage A 晚期）|
| **Apple IAP** | Legacy 无支付 | 1-2 周 |
| **用户系统**（注册/登录/订阅状态）| Legacy 无认证 | 2 周 |
| **Apple 生态整合**（Widgets / Shortcuts / Focus）| Legacy 无 | 分散在 Stage A/B 各 1 周 |

### 3.4 🔶 补齐清单（Legacy 有框架，补 20% 即可）

| 模块 | Legacy 完成度 | 需要补什么 | 工作量 |
|------|-----------|--------|-----|
| **FormulaEngine 指标库** | 65%（MA/EMA/SMA/WMA/DMA + CROSS/IF/HHV/LLV/REF/MAX/MIN/VAR/SLOPE/STDEV/SAR + 60 内置函数）| **MACD / KDJ / BOLL / RSI / CCI / WR / DMI / MFI / OBV / VOLUME / VR / CR / PSY / BIAS / DMA 二次形态/TRIX/CMO/ATR/HV/Ichimoku** 等约 20 个常用指标 | **2-3 周**（AI 批量生成 + 对标验证） |
| **条件预警中心** | 60%（TradingEngine 有条件单框架，可复用评估器）| UI 层（预警面板 / 触发历史）+ macOS 通知集成 | 2-3 周 |
| **模拟训练** | 50%（Mock 服务存在）| 接 SimNow 真实仿真 + 历史场景回放 + 评分 | 2-3 周 |
| **条件订单高级类型** | 基础 5 种 | 冰山单 / TWAP / VWAP / 阶梯单（Stage B 中后期）| 3-4 周 |

---

## 4. 迁移执行计划（建议 6-8 周）

### Week 1-2 · 核心包迁移
- [ ] **Day 1-2**：新项目初始化 Swift Package 结构
- [ ] **Day 3-5**：拷贝 Legacy `Sources/Shared/` 到新项目
- [ ] **Day 6-8**：拷贝 `Sources/FormulaEngine/` + 跑通测试
- [ ] **Day 9-10**：拷贝 `Sources/TradingEngine/ConditionalOrder/` + `KLineBuilder.swift`
- [ ] **Day 11-14**：补 FormulaEngine 缺失的 20 个指标（AI 批量生成 + 手动校验）
- [ ] **里程碑 M1**：新项目跑通所有 Legacy 测试 + 新增指标测试通过

### Week 3-4 · 基础 UI 搭建
- [ ] **Day 15-17**：Metal 图表引擎 PoC（目标：10 万 K 线 60fps）
- [ ] **Day 18-24**：重构 KLineChartView（参考 Legacy，用 Metal + 拆成 5 个子视图）
  - `KLineMetalRenderer.swift`（Metal 渲染层）
  - `KLineInteractionView.swift`（手势/十字光标）
  - `KLineIndicatorOverlay.swift`（指标叠加）
  - `KLineDrawingOverlay.swift`（画线层）
  - `KLineTimelineView.swift`（时间轴）
- [ ] **Day 25-28**：拷贝 `DrawingTool.swift` + 集成到 Metal 引擎
- [ ] **里程碑 M2**：可用的 Metal 图表 + 10 万 K 线 60fps 验证

### Week 5-6 · Stage A 新增 5 功能
- [ ] K 线回放（1-2 周）
- [ ] 条件预警中心 UI（2-3 周，可与其他并行）
- [ ] 交易日志（1-2 周）
- [ ] 模拟训练补完（2-3 周）
- [ ] 工作区模板（1 周）
- [ ] **里程碑 M3**：Stage A 功能全部跑通

### Week 7-8 · 集成 + 测试 + Alpha
- [ ] CloudKit 架构预埋
- [ ] Apple IAP 集成
- [ ] 用户系统（注册/登录/订阅状态）
- [ ] TestFlight Alpha 发布
- [ ] **里程碑 M4**：Alpha 版本可内测

**注**：以上时间基于单人 AI 辅助编码。若你 + 合伙人 + 兼职顾问 3 人分工，可压缩到 4-6 周。

---

## 5. 战略红利（Legacy 带来的时间节省）

### 5.1 单模块时间节省

| Stage A 目标 | 原时间估算 | Legacy 加持 | 节省 |
|----------|---------|----------|-----|
| 麦语言基础版 | M7-M9（12-16 周）| **M3-M4（2-3 周）** | **10-13 周** ⭐ |
| 核心数据模型 | M1-M2（4 周）| **M1（1 周）** | 3 周 |
| 条件单框架 | Stage B 早期（4-6 周）| **Stage A 末即上**（1 周）| 3-5 周 |
| 画线工具 6 种 | M3-M4（3-4 周）| **M2（1 周补 Metal 渲染）** | 2-3 周 |
| K 线合成算法 | M2（2 周）| **0（拷贝即用）** | 2 周 |
| **总计节省** | — | — | **20-26 周 ≈ 5-6 个月** |

### 5.2 🔥 最重要的战略红利

**麦语言完整兼容从 Stage B 末期提前到 Stage B 早期**（甚至 Stage A 末期）：
- 原计划：Stage B 末期（M22-M24）才达到 95%+ 覆盖
- Legacy 加持后：Stage B 早期（M13-M15）即可达到
- **提前 6-9 个月**

**业务含义**：
- P3 文华迁移者（5-10 万人）的转化潮可能提前 6-9 个月触发
- 乐观场景（ARR ¥2500 万）的达成概率显著提高
- Pro Max ¥999/年定价的"麦语言完整兼容"卖点 Stage B 初就能立
- 和券商谈 B2B2C 合作时，麦语言覆盖率是核心话术，提前达标 = 早拿合作

---

## 6. 已知坑与预防

| # | 坑 | 严重度 | 预防措施 |
|---|----|:----:|-------|
| 1 | `KLineChartView.swift` 985 行单文件 | 🟡 中 | 拷贝后第一件事拆成 5 个子视图（见 §4 Week 3-4）|
| 2 | App 层与核心库耦合（EnvironmentObject 直接调用）| 🟡 中 | 引入 protocol 抽象 + 依赖注入容器 |
| 3 | **CTP bridge 0% 实现** | 🔴 高 | Week 1 就启动 protocol 设计 + PoC，别拖 |
| 4 | Mock 与真实交易接口不统一 | 🟡 中 | 统一 `TradingService` protocol，两个实现 |
| 5 | Tick 数据断线重连缺失 | 🟡 中 | 参考 D3 的断线 SOP 实现 |
| 6 | 小数精度混用风险（Decimal vs Double）| 🟠 中高 | 拷贝时 audit 所有价格/金额字段，**禁止用 Double 做价格**|
| 7 | Sendable 限制（Swift 6 严格并发）| 🟢 低 | Legacy 已做到位，跟着走即可 |
| 8 | 时间对齐（KLineBuilder）与交易所规则耦合 | 🟡 中 | CTP 接入时适配每个交易所开盘规则 |
| 9 | `SinaMarketData` 网络断线重连逻辑弱 | 🟢 低 | 新项目重写行情接入时解决 |
| 10 | Legacy 测试覆盖 UI 层弱 | 🟢 低 | 新项目加端到端 UI 测试 |

---

## 7. 决策记录

### 为什么选**混合策略（方案 A）**

**核心优势**：
1. 保留新项目的干净架构（不继承 Legacy 的 `KLineChartView` 技术债）
2. 复用 Legacy 已完成的核心工作（省 20-26 周）
3. 新项目 Stage A/B/C 战略可独立演进（Legacy 的 36 周一气呵成节奏不适合当下）

### 为什么**不选整体迁移（方案 B · 基于 Legacy 继续开发）**

- Legacy App 层架构需大重构（KLineChartView 985 行 / 缺状态管理 / 高耦合）
- **技术债继承成本 > 重搭基础架构成本**
- 新项目 Stage A 新增 5 功能（K 线回放 / 交易日志 / 预警 / 训练 / 模板）Legacy 都没做 → 整体迁移后仍要补 60%+ 新功能
- Legacy 项目已有 Git 历史 + Docs + 旧决策，新项目需要干净起点

### 为什么**不选全部重写（方案 C）**

- 浪费 20-30 周已完成的核心工作（特别是 FormulaEngine 的 2300 行）
- 麦语言解析器重写投入巨大且无明显收益
- Shared 数据模型 + KLineBuilder 时间对齐算法都经过测试验证

### 决策风险
若 Legacy 代码质量远低于预期（如发现隐藏 bug / 架构不适配），回退方案：
- 降级为 "只复用 FormulaEngine"（仍省 12-16 周）
- 其他模块重写

---

## 8. 设计文档吸收状态

Legacy `Docs/` 下 6 份设计文档的精华已分层吸收：

| 设计点 | 吸收位置（新项目当前文档）| 状态 |
|-------|------------------------|:---:|
| 期货机制速查表（双向/T+0/夜盘/结算价/平今平昨）| `产品设计书.md §3.0` | ✅ |
| 条件单完整定义 10+ 种 | `产品设计书.md §3.2 ⑩` | ✅ |
| 性能基准 list（60fps/<1s/<5ms/<500MB）| `产品设计书.md §3.4` | ✅ |
| CTP 断线重连 SOP | `D3-风险与危机预案.md §3 事故 SOP` | ✅ |
| 期货数据量估算（500MB-1GB/天 / 375-750GB/年）| `产品设计书.md §3.0` | ✅ |
| 图表类型 P0/P1/P2 分级 | Stage B 规划（D4 · 未来产出时吸收）| ⏸️ 待 D4 |
| 期权完整路径（T 型报价 / Greeks / 波动率曲面）| Stage C 规划（未来）| ⏸️ 待 Stage C |
| 用户获取多渠道矩阵 | Plan B 参考（D3 §6）| ⏸️ 仅作 Plan B 备选 |

---

## 9. 关键数字速查（迁移决策用）

| 问 | 答 |
|----|----|
| 迁移总耗时？ | 单人 6-8 周 / 3 人协作 4-6 周 |
| 最大时间节省点？ | 麦语言（省 10-13 周）+ 数据模型（省 3 周）+ 条件单（省 3-5 周）|
| 最大新写投入？ | Metal 图表引擎 6-8 周 + CTP Bridge 3-4 周 |
| Legacy 代码可直接用比例？ | **约 40%** 直接拷贝，30% 参考改动，30% 全新写 |
| Legacy 最值钱的单个模块？ | `FormulaEngine/`（麦语言解析器，2300 行 85% 完成度）|
| Legacy 最坑的单个文件？ | `App/Views/KLineChartView.swift`（985 行需拆分）|

---

## 10. 实际迁移时的检查清单（Ready-to-Execute）

**启动前 check**：
- [ ] 新项目已初始化 Swift Package，Package.swift 声明好 targets
- [ ] 有 Xcode / Cursor 开发环境
- [ ] 本文档和 Legacy 项目都能访问

**Week 1 Day 1 第一件事**：
```bash
# 创建新 Package targets
cd <新项目路径>
# 手动编辑 Package.swift，添加 5 个 library：
# - Shared / FormulaEngine / MarketData / ContractManager / TradingEngine

# 拷贝 Shared（最简单，最先做）
cp -r /home/beelink/macos_tmp/macos_futures_trading/Sources/Shared/* \
      Sources/Shared/

# 编译验证
swift build
```

**每周末 checkpoint**：对照 §4 执行计划核对里程碑，偏差超过 20% 触发复盘。

---

**文档版本**：v1.0 · 2026-04-24
**下次更新触发**：代码迁移正式启动 Week 1 完成后
**维护人**：项目创始团队

---

**一句话总结**：**不要在新项目里从零写麦语言解析器 —— Legacy 已经替你做了 85%。其他模块按本文档 §3 的 map 拷/改/新写即可，6-8 周完成迁移。**
