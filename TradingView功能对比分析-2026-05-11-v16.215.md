# 中国期货工作台 vs TradingView · 详细功能对比

> **基准**：TradingView Premium（功能最全档）vs 我们 v16.215（2026-05-11）
> **目的**：识别功能差距，制定对齐路线，明确独家护城河
> **使用**：v16.216+ 系列对齐参照表

---

## 0 · 执行摘要

| 维度 | 结论 |
|------|------|
| 我们持平的 | 8 类（多窗口 / Metal 60fps / Bar Replay / Paper Trading / 条件单 / 公式编辑器 / 工作区 / 截图分享） |
| 我们差距的 | 主要在"核心图表能力" + "画线工具" + "Strategy Tester" + "警报扩展" + "行情数据"5 类 |
| 我们独家的 | 9 项（中国期货专精 / 麦语言 / 训练评分 5 维 / 套利窗口三件套 / 复盘 8 图 + 22 章月报 / Mac 原生 Metal / 离线优先 / 异常监控 / 心理洞察） |
| 战略不补 | 全球多市场 / 社交社区 / iPhone Win 端 / 江恩艾略特工具 |
| 关键缺失 | Strategy Tester（重大）· 画线警报 · Heikin/Renko · Volume Profile · 斐波套件 · 浅色主题 |

---

## 1 · 核心图表能力对比

| 功能 | TradingView | 我们 v16.215 | 差距 | 优先级 |
|------|-------------|-------------|------|-------|
| 时间周期 | 50+（1s/5s/10s/15s/30s/1m/5m/.../1M/3M/6M/1Y）| 9（1m/5m/15m/30m/1H/4H/D/W/M）| 缺秒级 + 季月年 | 🟡 秒级低 / 季月年中 |
| 图表类型 | 14+（蜡烛/柱状/Heikin Ashi/Renko/Kagi/Point&Figure/Line/Area/Baseline/Hollow/Bars 等）| 蜡烛图（单一） | 缺 13+ 类型 | 🔴 Heikin/Renko 必补 |
| 多窗口布局 | 1/2/4/6/8 屏 grid | 6 种布局（MultiChart） | 基本对齐 | ⭐ 持平 |
| Multi-symbol 叠加 | spread / ratio / 多 symbol 叠加 | 套利窗口（独家形式） | 不同形式 | ⭐ 我们独家 |
| 主题切换 | 50+ 主题 | 1 种（暗） | 缺浅色 / 自定义 | 🟡 浅色必加 |
| 截图导出 | ✅ | ✅（ReviewWindow ⌘S） | 持平 | — |
| 60fps 渲染 | Web | Metal 原生 10w 根 60fps | ⭐ 我们快 | ⭐ 独家 |

## 2 · 画线工具对比

| 类别 | TradingView（80+） | 我们 | 差距 | 优先级 |
|------|----------|-------|------|------|
| 基础线 | 水平/垂直/趋势/通道/射线/平行通道 | 趋势线/水平线/矩形/斐波（基础） | 缺垂直/通道/射线 | 🔴 通道射线必补 |
| 斐波那契 | 10+ 种（回撤/扩展/扇形/弧/时间/通道/速阻/三角）| 1 种（基础回撤） | 缺 9 种 | 🔴 趋势 trader 必备 |
| 江恩 / 艾略特 | ✅（5+ 工具） | ❌ | 缺全部 | 🟢 国内 trader 用得少 |
| 形状 / 标记 | 文字/箭头/形状/价格标签 | 基础 | 缺文字标记 / 箭头 / 标签 | 🟡 复盘必备 |
| 模板保存 | 模板库 / 跨设备 sync | ❌ | 全缺 | 🟡 重要 |

## 3 · 技术指标 / 公式语言对比

| 维度 | TradingView | 我们 | 差距 | 优先级 |
|------|-------------|------|------|-------|
| 内置指标 | 400+ | 56 个（44 真 + 10 占位） | 缺 350+ | 🟡 长尾低 / 头部要补 |
| 社区指标 | 100K+（Pine 发布） | ❌ | 生态缺 | 🟢 Stage A 不做 |
| 公式语言 | Pine Script v5/v6 | 麦语言（中文）| ⭐ 文华兼容 | ⭐ 独家 |
| 公式编辑器 | Pine Editor + 调试器 | FormulaEditor + Lint 9 入口 + Minimap | 我们 lint 更强 | ⭐ 持平+ |
| Strategy 回测 | Strategy Tester | ❌ | 重大缺失 | 🔴 Stage A 必补 |
| 发布生态 | Public Library | ❌ | — | 🟢 M6+ |

## 4 · 复盘 / 回放对比

| 功能 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| Bar Replay | ✅ 任意日期起播 | ✅ ReplayCore | 持平 |
| 回放调速 | 0.5x-10x | ✅ | 持平 |
| 回放中画线 / 加指标 | ✅ | ❓ 待验 | 🟡 |
| 回放中模拟下单 | ✅ Paper Trading | ✅ SimulatedTradingEngine | 持平 |
| 复盘 chart | 基础 | **8 张图 + 5 分类** | ⭐ 独家 |
| 月报 markdown | ❌ | **22+ 章节 + TOC + footer** | ⭐ 独家 |
| 训练评分 | ❌（仅 Strategy 回测）| **5 维 + 改进 plan + 月报** | ⭐ 独家 |
| 训练历史分析 | ❌ | TrainingHistoryPanel 38 项 | ⭐ 独家 |
| 心理风险洞察 | ❌ | ✅ v16.38 | ⭐ 独家 |

## 5 · 警报系统对比

| 功能 | TradingView | 我们 | 差距 | 优先级 |
|------|-------------|------|------|-------|
| 价格警报 | ✅ | ✅ | 持平 | — |
| 指标警报 | ✅ | ✅ | 持平 | — |
| 画线警报（突破趋势线） | ✅ | ❌ | 缺 | 🔴 高频用 |
| 公式警报 | ✅ Pine alerts | ❌ | 缺 | 🟡 |
| 渠道 | Email/SMS/Webhook/App push | 文件 / 邮件 / 本地 | 缺 SMS/Webhook | 🟡 Webhook 重要 |
| 异常监控 | ❌ | ✅ AnomalyMonitorWindow | ⭐ 独家 |
| 价差告警 | ❌ | ✅ SpreadAlertWindow | ⭐ 独家 |

## 6 · 行情数据对比

| 维度 | TradingView | 我们 | 差距 | 优先级 |
|------|-------------|------|------|-------|
| 实时行情 | 70+ exchange | 新浪轮询（延迟） | 缺低延迟 | 🔴 待 CTP 解禁（已搁置）|
| 历史数据 | 数十年 | 短期 | 缺长期 | 🔴 数据源 |
| Tick 数据 | ✅ | ✅ TickEngine | 持平 | — |
| Level 2 | ✅ | ❌ | — | 🟢 CTP 后 |
| Bid/Ask | ✅ | ❓ | — | 🟡 |
| Volume Profile | ✅ | ❌ | — | 🔴 关键工具 |

## 7 · 多市场覆盖对比

| 市场 | TradingView | 我们 | 战略 |
|------|-------------|------|------|
| 中国期货 CFFEX/SHFE/DCE/ZCE/INE | 基础（数据延迟） | **专精** | ⭐ 独家 |
| 全球股票 | ✅ 70+ exchange | ❌ | 🟢 战略不补 |
| 加密 | ✅ 500+ | ❌ | 🟢 |
| Forex | ✅ | ❌ | 🟢 |
| 商品 / 债券 / ETF | ✅ | ❌ | 🟢 |

## 8 · 自选 / 监控对比

| 功能 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| 多 watchlist | 无限 | ✅ Watchlists | 持平 |
| 颜色分组 / 旗标 | ✅ | ❓ | 🟡 |
| 自定义列 | 25+ 字段 | ❓ | 🟡 |
| 跨 device sync | ✅ | 🟡 CloudKit 预埋 | 🟡 M7 启用 |
| 板块 / 热力图 | Heatmap | ✅ HeatmapWindow + SectorWindow | ⭐ 中国期货专精 |
| 资金流向 | 部分 | ✅ MoneyFlowWindow | ⭐ |
| 相关性 | ✅ | ✅ CorrelationWindow | 持平 |

## 9 · 模拟交易 / 训练对比

| 功能 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| Paper Trading | ✅ 10+ broker | ✅ SimulatedTradingEngine | 持平 |
| 条件单（Bracket/OCO/Trailing）| ✅ | ✅ TradingCore/ConditionalOrder | 持平 |
| Strategy 回测 | ✅ Strategy Tester | ❌ | 🔴 关键缺 |
| 训练评分 | ❌ | ⭐ TrainingScore 5 维 | ⭐ 独家 |
| 训练规则 lint | ❌ | ⭐ DisciplineEvaluator 6 规则 | ⭐ 独家 |
| 改进 plan + 弱项专项 | ❌ | ⭐ v16.213 | ⭐ 独家 |
| 训练评分历史 | ❌ | ⭐ 38 增强 + streak | ⭐ 独家 |

## 10 · 社交 / 社区对比

| 功能 | TradingView | 我们 | 战略 |
|------|-------------|------|------|
| 1000 万 + 用户 | ✅ | ❌ | 🟢 Stage A 不做 |
| Ideas / Streams | ✅ | ❌ | 🟢 |
| Chat / Squawk | ✅ | ❌ | 🟢 |
| 评级 / Followers | ✅ | ❌ | 🟢 |

## 11 · 多端 / 同步对比

| 维度 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| 平台 | Web / iOS / Android / Mac / Win | Mac + iPad 原生 | 🟡 缺 iOS phone / Win |
| 同步 | Cloud-based 实时 | CloudKit 预埋 | 🟡 M7 启用 |
| 离线模式 | 有限 | ✅ 默认本地 | ⭐ 隐私优势 |

## 12 · 期权 / 衍生品对比

| 功能 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| Options chain | ✅ | ✅ OptionWindow | 持平 |
| Strategy builder | ✅ | ✅ OptionBacktestSheet | 持平 |
| Greeks | ✅ | ❓ 待验 | 🟡 |
| 风险图 | ✅ | ❓ | 🟡 |
| 中国期权专精 | 弱 | ⭐ 强 | ⭐ 独家 |

## 13 · 套利 / Spread 对比（我们重大独家）

| 功能 | TradingView | 我们 |
|------|-------------|------|
| 跨期套利 | 基础 spread | ⭐ SpreadWindow + SpreadBacktestSheet |
| 日历套利 | ❌ | ⭐ CalendarSpreadWindow |
| 自定义点差 | ❌ | ⭐ AddCustomSpreadPairSheet |
| 价差告警 | ❌ | ⭐ SpreadAlertWindow |

## 14 · 工作流 / 工作区对比

| 功能 | TradingView | 我们 | 差距 |
|------|-------------|------|------|
| 工作区模板 | ✅ Saved Layouts | ✅ WorkspaceWindow | 持平 |
| 多 chart layout | ✅ | ✅ MultiChart 6 布局 | 持平 |
| 笔记 / 想法 | ✅ Notes | ✅ JournalWindow 112K | 持平 |
| 截图分享 | ✅ | ✅ + base64 PNG markdown | ⭐ 我们月报含图 |
| 快捷键全覆盖 | ✅ | ✅（28 个窗口）| 持平 |

---

## 15 · 关键差距清单（按优先级）

### 🔴 重大缺失（影响核心可用性 · 6 项）

| # | 功能 | 工作量 | 时间 | 备注 |
|---|------|-------|------|------|
| 1 | **Strategy Tester（公式回测）** | 5-10d | Stage A M4-M5 | 公式驱动回测报告 |
| 2 | **画线警报（趋势线/水平线突破）** | 1-2d | Stage A | AlertCore + Drawings 联动 |
| 3 | **图表类型扩展**（Heikin Ashi / Renko / Line / Area） | 1-2d 每种 | Stage A | ChartScene + Metal renderer |
| 4 | **Volume Profile（成交量分布）** | 2-3d | Stage A | 重要 trader 工具 |
| 5 | **斐波套件**（扩展 5-9 种）| 2-3d | Stage A | 趋势 trader 必备 |
| 6 | **画线工具补全**（通道 / 射线 / 平行通道）| 1-2d | Stage A | 基础线类必备 |

### 🟡 重要差距（trader 体验提升 · 7 项）

| # | 功能 | 工作量 |
|---|------|-------|
| 7 | 浅色主题 + 主题切换 | 1d |
| 8 | Webhook 警报渠道 | 1d |
| 9 | 画线模板保存 / 跨设备 sync | 1-2d |
| 10 | 自选列自定义 / 颜色分组 | 1d |
| 11 | Greeks + 期权风险图 | 2-3d |
| 12 | 文字 / 形状标注（chart 内） | 1-2d |
| 13 | Bid/Ask spread 显示 | 0.3d |
| 14 | 时间周期扩展（季/半年/年 + 秒级）| 0.5-1d |

### 🟢 战略不补（不在中国期货 trader 核心需求）

- 全球股票 / 加密 / Forex 多市场
- 社交 / Ideas / Streams 社区
- Public Library 公式发布
- iPhone phone 端 / Windows 端（M6 后 Stage B）
- 江恩工具 / 艾略特波浪（小众）

### ⭐ 我们独家优势（必须保持 + 强化 · 9 项）

| 优势 | 状态 | 建议 |
|------|------|------|
| 中国期货专精 | ✅ 强 | 持续优化 |
| 文华麦语言生态 | 🟡 5 函数 / 90% 兼容 | 补 30-50 函数 |
| 训练评分 5 维 | ✅ 强（v16 大爆发） | 继续 polish |
| 套利窗口三件套 | ✅ 强 | 持续 polish |
| 复盘 8 图 + 22 章月报 | ✅ 强 | 持续 polish |
| Mac/iPad 原生 + Metal 60fps | ✅ 强 | 性能护城河 |
| 离线优先 + 本地存储 | ✅ 强 | 隐私 / 监管优势 |
| 异常监控 + 心理洞察 | ✅ 独有 | 持续 polish |
| 公式 Lint 噪音控制 | ✅ 独有 9 入口 | — |

---

## 16 · 战略观察

| # | 观察 | 影响 |
|---|------|------|
| 1 | 核心独家护城河 = "训练评分 + 套利 + 中国期货专精" | TradingView 不会做这些 |
| 2 | TradingView 不直接竞争中国期货 trader 场景 | 定位差异化清晰 |
| 3 | Strategy Tester 是最大单点缺失 | 实盘 trader 决策必需 · Stage A M4-M5 必补 |
| 4 | 画线警报 + Volume Profile + 斐波套件 + 图表类型 + 通道射线 = 8-15d | 在 v16.216+ 系列可一气呵成完成 |
| 5 | 公式生态（麦语言函数补齐）是中长期 | WP-62 30-50 函数继续推 |
| 6 | 多端（iPhone）/ Win 走 Stage B | 不影响 M6 上线 |

---

## 17 · 完整对齐路线（v16.216+ 工作清单）

### A 段：核心图表能力 + 画线工具（用户当前优先级 · ~10-15d 总量）

| 优先 | 任务 | 类别 | 工作量 |
|------|------|------|-------|
| 1 | Heikin Ashi 图表类型 | 图表 | 1d |
| 2 | Renko 图表类型 | 图表 | 1d |
| 3 | Line / Area / Baseline 图表类型 | 图表 | 1d（3 in 1）|
| 4 | 浅色主题 + 主题切换 | 图表 | 1d |
| 5 | 时间周期扩展（季 / 半年 / 年 + 秒级）| 图表 | 0.5-1d |
| 6 | 画线：通道 + 射线 + 平行通道 | 画线 | 1-2d |
| 7 | 斐波套件扩展（扩展 / 扇形 / 弧 / 时间 / 通道）| 画线 | 2-3d |
| 8 | 文字 / 箭头 / 形状标注 | 画线 | 1-2d |
| 9 | 画线模板保存 + Watchlists 同步 | 画线 | 1-2d |
| 10 | Hollow / Bars / Point & Figure / Kagi 图表（可选）| 图表 | 1d 每种 |

### B 段：警报 + Volume Profile（关键 trader 工具 · 4-6d）

| 优先 | 任务 | 工作量 |
|------|------|-------|
| 11 | 画线警报（趋势线 / 水平线突破）| 1-2d |
| 12 | Volume Profile（成交量分布柱）| 2-3d |
| 13 | Webhook 警报渠道 | 1d |

### C 段：自选 + 期权深化（体验提升 · 3-5d）

| 优先 | 任务 | 工作量 |
|------|------|-------|
| 14 | 自选列自定义 / 颜色分组 | 1d |
| 15 | Greeks + 期权风险图 | 2-3d |
| 16 | Bid/Ask spread 显示 | 0.3d |

### D 段：Strategy Tester（最重 · 5-10d · M4-M5）

| 优先 | 任务 | 工作量 |
|------|------|-------|
| 17 | 公式回测引擎（基于 FormulaEngine + ReplayDriver）| 3-5d |
| 18 | 回测报告（Profit/DD/Sharpe/WR/Expectancy）| 2-3d |
| 19 | 回测可视化（equity curve / trades / DD）| 1-2d |

### E 段：麦语言补齐（WP-62 中长期）

| 优先 | 任务 | 工作量 |
|------|------|-------|
| 20 | 麦语言 30-50 函数补齐 | 5-10d 持续 |

---

## 18 · 备注

- 本文档为 v16.215 时刻快照；对齐过程中可能新增项目
- 优先级仅供参考，可根据 trader 反馈调整
- 文华公式导入 / 自选导入（WP-63/64）属于另一条线，与本表并行
- CTP SimNow 已搁置，本表不计入
- IAP / Pro 门控不在本表范围内（M6 前不预留）
