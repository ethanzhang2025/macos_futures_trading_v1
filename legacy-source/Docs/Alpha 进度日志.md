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

### Day 2（2026-04-19）：非交易时段 bug 修复 — ✅ 已完成

**问题**：
- `PositionTable.swift:39` 现价 fallback 失效 —— `lastPrice` 是 `Decimal(0)` 不是 nil，`??` 不触发，现价列显示 0
- 平仓按钮 / `OrderPanel.flattenAll` 非交易时段传 `price = 0`；`MockTradingService.placeOrder` 无 guard，成交后 `closePosition` 按 `0 − openAvgPrice` 算出大负 pnl 入 `closePnL`，演示时一点平仓账户瞬间爆亏

**修改**：
- `AppViewModel.swift` 新增 `priceFallback(for:)` helper：实时价 → 最后 K 线 close（仅当前合约）→ 昨结算 → 昨收
- `OrderPanel.swift` / `PositionTable.swift` 改用 helper
- `MockTradingService.swift:27` `placeOrder` 加 `guard price > 0` 作为最后防线

`+15 / −8`。Linux 无 SwiftUI 不能 build App 目录，Mac 端待验证。

### Day 2 续（2026-04-19）：K 线右键「此价位买开/卖开」— ✅ 已完成

- `KLineChartView` 加 `hoverPrice @State`，`onContinuousHover` 时更新
- 抽 `computeHoverPrice(y:chartH:)` helper（与 `drawCrosshair` 同算法，Y 坐标 → 价格）
- `ChartContextMenu` 加 `hoverPrice: Decimal?` 参数，顶部条件渲染两个菜单项，点击固定 1 手下单

**约束**：F1-F4 等快捷键延后到所有功能完成后统一梳理（见 memory `project_shortcut_postponed.md`）。Week 1 收尾只做到右键菜单为止。

### Day 2 续（2026-04-19）：自选合约增删 + UserDefaults 持久化 — ✅ 已完成

**Week 2 子项提前启动**。原计划 Week 2，Day 2 把 Week 1 收尾完就顺手开了。

- `Models/WatchItem.swift` 新建：`Codable/Identifiable/Hashable` struct 包裹 `SinaFuturesSymbol` tuple，`allContracts` 是全部合约池（36 个）
- `AppViewModel.watchList` 从 `let` 改 `@Published var [WatchItem]`，`didSet` 自动保存；`init` 启动时从 UserDefaults `"watchList"` key 加载
- 加 `addToWatch(_:) / removeFromWatch(_:)`：移除正被选中的合约时切到首项
- `ContractSidebar` 标题行加「+」按钮（`plus.circle`）打开 sheet；每行右键菜单「从自选移除」
- 新建 `Views/AddContractSheet.swift`：展示未在自选里的合约，支持搜索 + 点击「添加」

**延后**：拖拽排序（SwiftUI `ScrollView + LazyVStack` 不支持原生拖拽，手写 `DropDelegate` 与 Alpha 价值不匹配）、OI 副图（新浪 K 线 API 不返回 bar 级持仓量，数据源不支持，移出 Week 2 范围）。

### Day 2 续（2026-04-19）：合约列表「连续/主力」显示切换 — ✅ 已完成

- 新建 `Services/MainContractService.swift`：36 品种硬编码主力月份映射（2026-04-19 估算值）
- `AppViewModel` 加 `@Published showMainContract: Bool` + `displaySymbol(for:) -> String` helper
- `ContractSidebar` 搜索框下加 `[连续 / 主力]` segmented Picker
- `ContractRow` 代码列用 `vm.displaySymbol`，主力模式下显示 RB2510 等具体月份

**限定**：仅视觉切换 —— `selectedSymbol` 和 API 请求**始终走连续代码**。未做"切到主力后 K 线加载主力月份真实数据"，因为新浪 K 线 API 对月份合约代码的支持未验证，避免空数据风险。真实主力数据延后到 CTP/文华数据源阶段。

### Day 2 续（2026-04-19）：多窗口 ⌘N — ✅ 已完成

- `FuturesTraderApp.AppDelegate` 从 `private var window` 改 `private var windows: [NSWindow]`
- 抽 `@objc newWindow()`：每个窗口独立 `AppViewModel`（合约/周期/指标参数各自独立），watchList 走 UserDefaults 共享
- 窗口级联排列（新窗口在上一个基础上偏移 +30/-30），不完全覆盖
- 监听 `NSWindow.willCloseNotification`，关闭时从 windows 数组清除
- 菜单栏加「文件 > 新窗口 ⌘N」—— macOS 系统惯例快捷键（与 ⌘Q 退出/⌘M 最小化同类），非产品自定义，不在"延后统一梳理"范围

**限定**：watchList 通过 UserDefaults 启动时加载 + 本窗口 didSet 保存，**窗口间不实时互相同步**（A 窗口加合约 B 窗口看不到，直到 B 重启）。Alpha 阶段可接受。

### Week 2：✅ 2/3 可做项完成

- [x] 自选合约增删 + 持久化（Day 2）
- [x] 合约列表「连续/主力」显示切换（Day 2）
- [x] ~~多窗口 ⌘N（Day 2）~~ **Day 5 回退，推 Beta 用 WindowGroup 重做**（详见 Day 5 decision）
- [x] ~~OI 副图~~ 放弃 → 数据源升级后复活（详见 Day 2 续「数据源升级」）

### Day 2 续（2026-04-19）：委托单历史表 — ✅ 已完成

Week 2 完成后的增量，补齐交易工作流视觉链路。

- 新建 `Views/OrdersTable.swift`：列 时间/合约/方向/开平/价格/委托/成交/状态，最新在顶（MockTradingService.orders 插入 at: 0）；状态颜色：已报橙、成交白、部分成交黄、已撤/废灰
- 新建 `Views/TradingTabView.swift`：下方面板改 Tab 结构，`[持仓 N | 委托 M]` 切换，数字随 `vm.trading.{positions, orders}` 实时更新
- `PositionTable` 去掉自身 header（改由 TradingTabView 统管），保留行渲染
- `ContentView` 把 `PositionTable()` 替换为 `TradingTabView()`

### Day 2 续（2026-04-19）：数据源升级（修复 2 年老化）— ✅ 已完成

**背景**：调研"真实主力切换"时用 curl 实测发现，旧新浪 API 数据卡在 `2024-07-17`——过去两年项目所有"实时"行情实际是老快照。换端点后数据升到 `2026-04-17`。

**改动**：
- `SinaMarketData.fetchQuotes` URL：`list=RB0` → `list=nf_RB0`（加 `nf_` 前缀）
- `parseQuotes` 分商品/金融两套：
  - 商品期货（RB/HC/I/J/...）沿用旧字段顺序，但 openInterest/volume 改 Int(Double(...))（新 API 返回小数格式如 `1443377.000`）
  - 金融期货（IF/IC/IM/IH/T*）完全不同字段顺序：name 在末尾，价格 0-3，last 在 7，oi 在 6；独立 preSettlement 字段缺失，近似用 close
- K 线 4 个 endpoint 全换到 `InnerFuturesNewService.getDailyKLine` / `getFewMinLine?type=5/15/60`（jsonp_v2 格式）
- `fetchKLines` 私有方法：剥离 `var t=(...);` 包装后按 `[[String: String]]` JSON decode；字段 d/o/h/l/c/v/p
- `SinaKLineBar` 加 `openInterest: Int` 字段（默认 0），从新 API 的 `p` 字段映射

**验证**：`swift build --target MarketData` 编译通过。Mac 端 `git pull && swift run --package-path ...` 后应看到：
- K 线最新日期是 `2026-04-17` 而非 `2024-07-17`
- 商品期货 lastPrice 与新浪网页一致
- 金融期货 IF0/IC0/IM0/IH0 能加载（交易时段字段精度可能有偏差，非交易时段 close=last 近似 OK）

**连锁**：`SinaKLineBar.openInterest` 已 populated → **OI 副图**（原放弃项）前置条件成立。

### Day 2 续（2026-04-19）：OI 副图 — ✅ 已完成

**前置**：数据源升级后 `SinaKLineBar.openInterest` 已从新 K 线 API 的 `p` 字段填充，原 Week 2 放弃的 OI 副图现可做。

- `SubChartType` 加 `.oi = "OI"` 枚举值
- `SubChartRenderer.drawOI`：金黄色折线 + 下方半透明面积，按 bars 的 OI min/max 自动缩放（10% margin）
- `KLineChartView` 副图 switch 加 `.oi` 分支
- `hoverText` 对 `.oi` 返回 `(OI, 数字, 金色)`
- 副图按钮区和右键「副图指标」菜单用 `SubChartType.allCases` 自动枚举，新 case 无需额外改

### Day 5（2026-04-22）：多窗口 ⌘N 回退 — ❌ 撤销 Week 2 的多窗口实现

**现象**：用户 Mac 端反复撞窗口关闭问题，演变过程：
1. 单窗口关闭 crash：`CA::Transaction::commit → autoreleasepool pop → NSConcretePointerArray dealloc → _Block_release → objc_release` 野指针
2. 多次修 teardown 顺序（`de6457c` / `9239b1d` / `b0d8866`）均无效
3. 定位 `KLineChartView.NSEvent.addLocalMonitorForEvents` 全局闭包强持 SwiftUI State/EnvironmentObject、`onDisappear` 在 NSHostingView 随 window 关闭时不可靠 → 删 keyMonitor / wheelMonitor 改 NSViewRepresentable（`eaf2372`），单窗口不再崩
4. 但关最后一个窗口仍崩 → `applicationShouldTerminateAfterLastWindowClosed = false` 规避 terminate flow（`78c68d2`），关第一个窗口后主线程 hang（beach ball），彻底卡死

**根因**：macOS 26 SDK + Swift 6 SwiftUI runtime 在 **NSHostingView 多实例销毁路径**上有多处清理不彻底（NSConcretePointerArray / observer block 残留），属于 AppKit + SwiftUI 混合模式的已知痛点。手搓 `NSApplication + 字典追踪 + NSHostingView` 无法彻底规避。

**决策**：**Alpha 阶段回退到单窗口**（commit 本次），多窗口推到 Beta 用 `SwiftUI App + WindowGroup` 原生多场景一起重做（原生生命周期，不踩手搓坑）。

**回退范围**：
- `AppDelegate` 瘦身回 `private var window: NSWindow?` + 单 `viewModel` + 单 `titleCancellable`
- 删 `newWindow()` / `windowWillClose` / `windowViewModels` / `windowCancellables` / `windows: [NSWindow]`
- 删菜单「文件 > 新窗口 ⌘N」 + 整个「文件」菜单
- 保留：窗口标题 Combine 订阅（单窗口下仍然有用）、`eaf2372` 的 monitor 修复（单窗口下也受益）

**非回退项**：Week 2 的自选增删、连续/主力切换、数据源升级、OI 副图、成交记录表、千分位等全部保留。

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
| Alpha 不做多窗口 | 手搓 NSApp + NSHostingView 多实例被 macOS 26 SDK + SwiftUI runtime 反复报销（pool pop over-release / teardown hang） | 投入产出不划算；Beta 迁 `SwiftUI App + WindowGroup` 原生多场景一起做，由 SwiftUI runtime 管生命周期。应用内"一窗多格"分屏视图（4 宫格看多合约）不受此决策影响，可以后续 Alpha 范围内做 |

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
