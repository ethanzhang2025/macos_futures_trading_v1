# Alpha 阶段进度日志

> 用途：记录第一阶段"1-30 天 Alpha 样机"的评估、执行与决策，作为后续会话的背景锚点。
> 新开会话读本文档即可对齐进度；不覆盖 `Docs/开发流程与最佳实践.md`（长期 36 周 Stage 0-9 路线图）、`README.md`（对外愿景）。

---

## 一、目标

**阶段**：第 1-30 天（起始 2026-04-18）
**交付物**：可展示 Alpha 样机
**验收语**：别人第一次看到样机时，能明显感知"这就是一个真正为 Mac 做的专业期货终端"

**必须完成**：项目边界 + 高频页面（K线/分时、自选、主力切换、持仓量、多窗口） + 交易工作流假链路（下单面板、一键平仓/反手、风险提示）
**应该完成**：演示材料（PPT/视频/截图）

---

## 二、起始评估（2026-04-18）

| # | 要求 | 完成度 | 证据 | 偏差 |
|---|---|---|---|---|
| 1 | 项目边界冻结 | 60% | `Docs/` 有方案与路线图；`Package.swift:8` `.macOS(.v13)` | 缺 v1 Scope 冻结单页（不做清单 + 免责） |
| 2a | K线/分时原生 | **120%** | `Views/KLineChartView.swift`、`TimelineChartView.swift`：SwiftUI+Canvas、5 周期、4 图表类型、9 种绘图、MA/BOLL/MACD/KDJ/RSI 全参数可配 | — |
| 2b | 自选合约 | 40% | `Views/ContractSidebar.swift` 只读+搜索；`AppViewModel.swift` `watchList` 硬编码 | 缺增删/排序 UI、无自选持久化 |
| 2c | 主力合约切换 | 0% | — | 完全未做 |
| 2d | 持仓量展示 | 30% | `OrderBookPanel.swift:101` 信息栏 | 无独立 OI 副图 |
| 2e | 多窗口/多屏 | 0% | `FuturesTraderApp.swift:25` 单 NSWindow | 完全未做 |
| 3a | 快速下单面板 | **5% → Week 1 已补至 95%** | 见下节 | — |
| 3b | 一键平仓/反手 | 0% → 95% | Week 1 已补 | — |
| 3c | 风险提示 | 10% → 90% | Week 1 已补 | — |
| 4 | 演示材料 | 0% | — | 完全缺失 |

**起始整体完成度 ~35%**，图表过剩、交易/多窗口/演示空白。核心偏差：项目像"专业图表工具"而非"交易终端样机"。

---

## 三、执行快照

### Week 1（2026-04-18）：交易工作流假链路 — ✅ 已完成

**新增文件**：
- `App/Sources/FuturesTraderApp/Services/MockTradingService.swift` — 假撮合引擎
- `App/Sources/FuturesTraderApp/Views/OrderPanel.swift` — 快速下单面板
- `App/Sources/FuturesTraderApp/Views/PositionTable.swift` — 持仓表
- `App/Sources/FuturesTraderApp/Views/AccountBar.swift` — 底部账户栏

**修改文件**：
- `App/Sources/FuturesTraderApp/AppViewModel.swift` — 注入 `trading: MockTradingService`，`Combine.sink` 桥接 `objectWillChange`，`fetchQuotes` 每轮调用 `trading.refreshPnL(quotes:)`，新增 `selectedQuote(for symbol:)`
- `App/Sources/FuturesTraderApp/ContentView.swift` — 布局改为 `VSplitView`：上半图表区（右栏嵌套 VSplitView: OrderBook + OrderPanel）、下半 PositionTable、底部 AccountBar

**关键设计参数**（Alpha 阶段演示用，数值偏简化）：
| 参数 | 值 | 说明 |
|---|---|---|
| 初始权益 | 1,000,000 | `Account.preBalance` |
| 保证金率 | 10% | 所有品种统一 |
| 合约乘数 | 10 | 所有品种统一（RB 真实值 10 吨/手，IF 真实 300，Alpha 不区分）|
| 手续费 | 5 元/手 | 固定 |
| 成交回报延时 | 300ms | `Task.sleep(for: .milliseconds(300))` |
| 风险度危险阈值 | ≥80% | `AccountBar` 红色闪烁 |

**交互特性**：
- 下单方向/开平：买开/卖开/买平/卖平 4 按钮（F1-F4 仅文案占位，未绑定 NSEvent）
- 手数：步进 ±1 + 快捷 1/5/10 预设
- 价格：步进 ±1 + "最新"按钮填充最新价；市价单时禁用输入
- 持仓聚合：同 `instrumentID + direction` 合并成一行，重算均价
- 一键平仓：反向下平仓单
- 一键反手：先平再开反向同手数（两次 `placeOrder` 调用）
- 风险度 = 保证金占用 / 动态权益 × 100%（逻辑已在 `Shared/Account.swift:49`）

**验证状态**：
- ✅ Linux `swift build` 跑通 Shared/MarketData/FormulaEngine/ContractManager/TradingEngine 库层 —— 引用的 `Order`/`Position`/`Account`/`Direction`/`OffsetFlag` 等类型无错
- ⏳ macOS 端 UI 交互（布局、下单链路、风险闪烁）**待实机验证**
- ⏳ F1-F4 快捷键绑定 NSEvent 未做（文案已占位）

### Week 2：多窗口 + 合约增强 — 未开始

计划清单（详见 `~/.claude/plans/review-1-1-30-alpha-iridescent-fern.md`）：
- `FuturesTraderApp.swift` 改造 WindowController + `⌘N`
- `MainContractService.swift`：新浪 `RB0/RB00` → `RB2505` 主力映射
- `ContractSidebar.swift` 扩展：增删/拖拽排序/自选组持久化（沿用 `DrawingTool.swift:195` `UserDefaults` 模式）
- `SubChartIndicators.swift` 新增 OI 副图

### Week 3：演示材料 + Scope 冻结 — 未开始

- `Docs/v1-scope-frozen.md`（不做清单 + 免责）
- `Demo/`：10 张截图 + 60 秒视频 + 8 页 PPT

---

## 四、已冻结决策

| 决策 | 取舍 | 理由 |
|---|---|---|
| Alpha 不上 Metal 图表引擎 | 保持 SwiftUI Canvas | 新浪日线 500 根 / 5 分 ~800 根，Canvas 无压力；Metal 需 shader + CoreText 贴图，收益要到 L2 深度/tick tape 才显现。放 Beta（第二阶段）再做 |
| Alpha 不接 CTP | 用 `MockTradingService` | 省时投入演示，真实接入放交易核心阶段 |
| 交易所优先级 | 上期/大商/郑商 常用品种先，CFFEX 金融期货后 | 演示场景集中在商品期货 |
| 不为"未来换 Metal"做抽象层 | 换时直接新起 `MetalKLineView` 平替 | 当前无技术债 |

---

## 五、待决事项（等用户验证后填充）

- [ ] Week 1 UI 在 macOS 上布局是否合理（OrderPanel 按钮尺寸、PositionTable 行高、AccountBar 指标选择）
- [ ] 保证金/合约乘数是否需要按品种差异化
- [ ] F1-F4 快捷键是否要绑定 NSEvent
- [ ] Week 2 多窗口改造的启动时机

---

## 六、关键文件指针

**源码入口**：
- `App/Package.swift` — Alpha app 可执行 target（独立 SPM package）
- `App/Sources/FuturesTraderApp/FuturesTraderApp.swift` — `@main` + 单 NSWindow
- `App/Sources/FuturesTraderApp/AppViewModel.swift` — 全局状态
- `App/Sources/FuturesTraderApp/ContentView.swift` — 主布局

**库依赖**（父目录 `Package.swift`）：
- `Sources/Shared/Models/Order.swift` / `Position.swift` / `Account.swift` — 交易域类型，已被 `MockTradingService` 复用
- `Sources/MarketData/SinaAPI/` — 新浪行情源（日K/5分/15分/60分/分时/3秒轮询报价）
- `Sources/TradingEngine/` — `ConditionalOrder/BracketOrder/TrailingStop/OCOOrder` 已定义但尚未接入 UI（Week 4+ 考虑）

**会话级临时文件**（非 git 跟踪）：
- `~/.claude/plans/review-1-1-30-alpha-iridescent-fern.md` — 原始 plan 文件（内容已吸收进本日志）

---

## 七、更新规则

- 每完成一个 Week 的主要任务，在 **三、执行快照** 追加一段
- 做出长期约束（如"不做 X"）时，追加到 **四、已冻结决策**
- 用户验证反馈或 blocker 记入 **五、待决事项**
- 不在本文档记录短期 TODO —— 那些用会话级 TaskList
