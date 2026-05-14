# macOS 多窗口归一架构重构方案

## 目标

将当前 SwiftUI 多窗口 / ShellViewModel 架构，重构为更稳定的 macOS 原生架构：

> MainWindow 使用 AppKit 作为 workspace shell；轻量监盘面板嵌入 NSSplitViewController；重型业务模块保留独立 NSWindow；HUD 使用 NSPanel；hover tooltip 使用 NSPopover；所有窗口共享同一个 AppState。

---

## 总体结论

采用混合架构：

```text
主窗口：单 NSWindow + NSSplitViewController + 多个 NSHostingController
重型模块：独立 NSWindow
浮顶工具：NSPanel
Hover / Quick Info：NSPopover
全局状态：共享 AppState
```

不要继续使用纯 SwiftUI 的 `VStack / HSplitView / WindowGroup` 嵌套来承载主工作台。

---

## 核心架构

```text
App
├── AppCoordinator
│   ├── appState
│   └── windowManager
│
├── WindowManager
│   ├── MainWindow
│   │   ├── 顶部 PrimaryTabBar + WorkspaceTabBar（NSHostingController）
│   │   ├── 中部 NSSplitViewController (horizontal · 3 列)
│   │   │   ├── NSHostingController(Sidebar)
│   │   │   ├── 中央 PaneContainer · 嵌套 NSSplitViewController
│   │   │   │   └── 1-N 个 NSHostingController(ChartScene)  ← 看盘 tab 下 Pane 切分
│   │   │   └── NSHostingController(WatchlistView / SectorView / PositionView)
│   │   └── 底部 NSHostingController(BottomBar + StatusBar)
│   │
│   ├── HeavyWindowRegistry
│   │   ├── OptionWindow
│   │   ├── SpreadWindow
│   │   ├── CalendarSpreadWindow
│   │   ├── SpreadAlertWindow
│   │   ├── ReviewWindow
│   │   ├── JournalWindow
│   │   ├── TrainingWindow
│   │   ├── FormulaEditorWindow
│   │   ├── AnomalyMonitorWindow
│   │   ├── InstrumentDashboardWindow
│   │   ├── SessionCompareWindow
│   │   ├── CorrelationWindow
│   │   └── MoneyflowWindow
│   │
│   ├── PanelRegistry
│   │   ├── InspectorPanel
│   │   ├── PatternHUDPanel
│   │   └── MultiTimeframeHUDPanel
│   │
│   └── PopoverService
│       └── HoverPopover
│
├── AppState
│   ├── primaryTab
│   ├── activeWorkspaceID
│   ├── selectedSymbol
│   ├── watchlist
│   ├── groupBindings
│   ├── chartTheme
│   └── userPreferences
│
└── SwiftUI Views
    └── 现有 SwiftUI views 原则上不重写，只包进 NSHostingController
```

---

## 设计原则

### 1. AppKit 负责窗口和布局边界

AppKit 负责：

- `NSWindow`
- `NSSplitViewController`
- `NSPanel`
- `NSPopover`
- 窗口生命周期
- 面板尺寸约束
- 窗口关闭 / 激活 / 浮顶 / 不抢焦点行为

SwiftUI 不再负责主窗口级别的 split layout 和窗口管理。

---

### 2. SwiftUI 只负责内容视图

现有 SwiftUI 代码尽量不重写。

每个已有模块通过 `NSHostingController` 嵌入 AppKit 容器：

```swift
let hostingController = NSHostingController(
    rootView: SomeSwiftUIView()
        .environmentObject(appState)
)
```

---

### 3. AppState 替代 ShellViewModel

用一个共享的 `AppState` 替代当前 ShellViewModel。

建议结构：

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var primaryTab: PrimaryTab
    @Published var activeWorkspaceID: UUID?
    @Published var selectedSymbol: String?
    @Published var watchlist: [String]
    @Published var groupBindings: GroupBindings
    @Published var chartTheme: ChartTheme
    @Published var userPreferences: UserPreferences
}
```

推荐由 `AppCoordinator` 持有唯一实例，而不是在各处硬编码 `AppState.shared`。

```swift
final class AppCoordinator {
    let appState: AppState
    let windowManager: WindowManager

    init() {
        self.appState = AppState()
        self.windowManager = WindowManager(appState: appState)
    }
}
```

---

## 主窗口结构

主窗口只保留一个：

```text
MainWindow: NSWindow
├── [顶] PrimaryTabBar + WorkspaceTabBar (NSHostingController)
├── [中] NSSplitViewController (horizontal · 3 列)
│   ├── Sidebar (NSHostingController)
│   ├── PaneContainer (嵌套 NSSplitViewController · 装 1-N 个 ChartScene Pane)
│   └── MonitorSplitItems (Watchlist / Sector / Position · NSHostingController)
└── [底] BottomBar + StatusBar (NSHostingController)
```

主窗口内嵌模块包括：

- PrimaryTabBar + WorkspaceTabBar（顶部）
- Sidebar
- PaneContainer（中央 · 装 1-N 个 chart Pane · 看盘 tab 下激活）
- Watchlist / Sector / Position（monitor 区）
- BottomBar + StatusBar

注意：

- 上方结构图中的 `MonitorSplitItems` 和 `PaneContainer` 是**概念性占位**，不是新组件
- V1 **不创建** `EmbeddedMonitorPanel.swift` / `MonitorSplitItems.swift`
- 直接把现有 `WatchlistView` / `SectorView` / `PositionView` 通过 `NSHostingController` 注册为 split item
- `PaneContainer` 是嵌套 NSSplitViewController · 看盘 tab 下装 1-N 个 `NSHostingController(ChartScene)` · 实现 1/2/4/6/9 grid 切分（沿用 Shell PaneLayout 概念 · 但 PaneKind 限定 .chart）
- Heatmap **不嵌入**主窗 · 保持现有独立 NSWindow（详见下文 Heatmap 处理规则）

---

## PrimaryTabBar 处理规则

PrimaryTabBar 是主窗口顶部的 5 个一级模块入口：看盘 / 套利 / 期权 / 复盘 / 训练。

V1 改造前（Shell 模式 · 已淘汰）：

```text
点击 PrimaryTab → shellVM.primaryTab = tab → activateFirstWorkspaceOfPrimaryTab
                → PaneContainer 内嵌切换 → PaneBody case .option/.spread/.review/.training
                → 撑大父容器 → PrimaryTabBar/WorkspaceTabBar 消失（v17.207 bug 根源）
```

V1 改造后（混合架构）：

```text
PrimaryTabBar 物理位置 → 保留在 MainWindow 顶部 · NSHostingController 包装
PrimaryTabBar 点击行为 → 5 个 tab 变 5 个入口按钮

  - 看盘  → 主窗 default 状态 · PaneContainer 激活 chart Pane 切分 · WorkspaceTabBar 显示
  - 套利  → WindowManager.open(.spread)
  - 期权  → WindowManager.open(.option)
  - 复盘  → WindowManager.open(.review)
  - 训练  → WindowManager.open(.training)
```

要求：

- PrimaryTabBar 仍保留在主窗 · 不删除
- 5 tab 不再切 PaneBody · 改为调用 WindowManager
- 看盘 tab 是主窗 **default 工作模式**：
  - 中央 PaneContainer 装 1-N 个 chart Pane（沿用 v17.0 PaneLayout · 1/2/4/6/9 grid）
  - WorkspaceTabBar 显示当前 workspace 列表 · 用户可切换 workspace 切 chart 状态
  - 每个 workspace 内 chart Pane 各自独立合约 / 周期 / 指标 / group 联动
- 其他 4 tab 通过 WindowManager.open 弹出对应重型独立 NSWindow
- WindowManager 内部判定：该重型窗口已开则激活前台 · 未开则创建
- 切到其他 4 tab 时主窗仍在前台 · WorkspaceTabBar 隐藏（workspace 仅看盘 tab 下激活）

视觉位置：

```text
MainWindow
├── [顶] PrimaryTabBar       看盘 ▌ 套利 ▌ 期权 ▌ 复盘 ▌ 训练
├── [次顶] WorkspaceTabBar    仅看盘 tab 下显示
├── NSSplitViewController (中部 horizontal · 3 列)
│   ├── Sidebar
│   ├── PaneContainer (嵌套 NSSplitViewController · 1-N 个 chart Pane)
│   └── MonitorSplitItems (Watchlist / Sector / Position)
└── [底] BottomBar + StatusBar
```

---

## 重型独立窗口

以下模块保留或迁移为独立 `NSWindow`：

```text
option
spread
calendarSpread
spreadAlert
review
journal
training
formulaEditor
anomalyMonitor
instrumentDashboard
sessionCompare
correlation
moneyflow
heatmap          ← V1 保持独立 NSWindow · 不嵌入主窗
```

这些模块属于完整业务流程，不应嵌入主工作台。

---

## Heatmap 处理规则

V1 **不新增** Heatmap light mode。

现有 `HeatmapWindow`（minWidth 1200 · 全市场 60+ 品种 · 4 sortMode · 完整业务流程）符合"独立窗 5 条件"判定，保持独立重型 NSWindow。

V1 **不创建**：

- `HeatmapLightMode`
- `EmbeddedHeatmap`
- `CompactHeatmapPanel`

后续如有需要再单独设计精简版 heatmap。

---

## 轻量监盘区域说明（V1 实施细则）

文档中的 `EmbeddedMonitorPanel` / `MonitorSplitItems` 不是需要新建的 SwiftUI 组件。

它们只是主窗口 `NSSplitViewController` 中的**概念性区域**，用来承载现有轻量监盘 view。

V1 **不创建** `EmbeddedMonitorPanel.swift` / `MonitorSplitItems.swift`。

V1 **只做**以下事情：

- 把现有 Watchlist / Sector / Position 等轻量模块通过 `NSHostingController` 嵌入主窗口 split item
- 不新增 TabView / Picker 容器
- 不重写现有 SwiftUI view
- 不改变现有业务逻辑

---

## NSPanel 规则

以下模块使用 `NSPanel`：

```text
Inspector
Pattern HUD
Multi-Timeframe Resonance HUD
```

要求：

- 浮于主窗口之上
- 不抢主窗口焦点
- 可关闭
- 可复用
- 状态由 AppState 驱动
- 不使用 SwiftUI `.sheet` 替代

---

## NSPopover 规则

以下场景使用 `NSPopover`：

```text
hover tooltip
quick info
按钮锚定提示
轻量解释卡
```

目的：

- 替代 `.help()`
- 0 延迟展示
- 锚定具体 view
- 避免 SwiftUI overlay 被裁切
- 避免 tooltip 被主窗口层级遮挡

---

## 主窗 vs 独立窗判定规则

不要只用 `.frame(minWidth:)` 做最终判断。

`minWidth` 只能作为初筛：

```text
minWidth < 1000  倾向嵌入主窗
minWidth >= 1000 倾向独立窗口
```

但最终判断以业务生命周期为准。

---

## 嵌入主窗的条件

满足以下条件时，嵌入 MainWindow：

```text
1. 依附当前 activeWorkspace
2. 不需要独立拖到副屏
3. 不需要长期独立存在
4. 不需要独立保存窗口状态
5. 主要用于辅助 chart / workspace
```

典型模块：

```text
watchlist
sector
position
bottom status
workspace tab
chart (看盘 tab 下 PaneContainer 装 1-N 个)
轻量监盘面板
```

---

## 独立 NSWindow 的条件

满足以下条件时，保留独立窗口：

```text
1. 有完整业务流程
2. 可能被拖到副屏
3. 需要独立关闭 / 恢复 / 保存位置
4. 需要和主 chart 并排长时间使用
5. 内容复杂度高，不只是辅助面板
```

典型模块：

```text
option
spread
calendarSpread
spreadAlert
review
journal
training
formulaEditor
anomalyMonitor
instrumentDashboard
sessionCompare
correlation
moneyflow
```

---

## 推荐迁移顺序

### Step 1：建立 AppKit MainWindow

创建：

```text
MainWindowController
MainSplitViewController
WindowManager
AppCoordinator
```

先让主窗口从 AppKit 启动。

---

### Step 2：嵌入核心 SwiftUI 面板

将以下模块包进 `NSHostingController`：

```text
PrimaryTabBar + WorkspaceTabBar
Sidebar
ChartScene  (PaneContainer 内 1-N 个实例 · 沿用 PaneLayout 1/2/4/6/9 grid)
Watchlist / Sector / Position  (MonitorSplitItems 概念占位)
BottomBar + StatusBar
```

不要重写现有 SwiftUI view。

---

### Step 3：抽离 AppState

从 ShellViewModel 中抽离：

```text
primaryTab
activeWorkspaceID
selectedSymbol
watchlist
groupBindings
chartTheme
userPreferences
```

并注入所有 `NSHostingController.rootView`。

---

### Step 4：实现 NSPanel

实现：

```text
InspectorPanel
PatternHUDPanel
MultiTimeframeHUDPanel
```

由 WindowManager 统一打开、关闭、复用。

---

### Step 5：实现 NSPopover

实现：

```text
HoverPopoverService
```

用于替代当前 `.help()` 和不稳定的 SwiftUI overlay tooltip。

---

### Step 6：处理重型窗口

13 个重型 WindowGroup 不需要第一阶段全部迁移。

优先策略：

```text
先保留现有 WindowGroup
后续逐步迁入 WindowManager
```

主窗口稳定优先级最高。

---

## 关键实现要求

### WindowManager

职责：

```text
1. 创建 MainWindow
2. 管理 HeavyWindow
3. 管理 NSPanel
4. 管理 NSPopover
5. 注入同一个 AppState
6. 维护窗口 registry
7. 处理窗口关闭后的引用清理
```

---

### MainWindow

要求：

```text
1. 只有一个实例
2. 使用 NSSplitViewController 管理面板
3. 设置 minSize
4. 支持 autosave frame
5. 不允许 SwiftUI 子 view 反向撑爆 NSWindow
```

---

### Split View

要求：

```text
1. Sidebar 有最小宽度和最大宽度 (min 200 / max 360 · 当前 240)
2. PaneContainer 是中央主区域 (装 1-N 个 chart Pane · 沿用 PaneLayout)
3. MonitorSplitItems (Watchlist/Sector/Position) 可折叠 (NSSplitViewItem.canCollapse = true)
4. BottomBar / StatusBar 高度固定或半固定 (BottomBar 120 / StatusBar 26)
5. 所有尺寸约束在 AppKit 层控制
```

---

### SwiftUI View

要求：

```text
1. 不再直接管理窗口
2. 不直接创建 WindowGroup
3. 不持有窗口引用
4. 通过 AppState 通信
5. 需要打开窗口时调用 WindowManager
```

---

## 禁止事项

不要继续扩大以下模式：

```text
SwiftUI VStack / HSplitView 深层嵌套
SwiftUI WindowGroup 承载主工作台子模块
SwiftUI overlay 实现复杂 tooltip
SwiftUI .sheet 承载长期存在的工具窗口
各窗口持有自己的 ShellViewModel
窗口之间直接互相引用
```

---

## 验收标准

完成后应满足：

```text
1. 子面板不会撑爆主窗口
2. hover tooltip 可 0 延迟稳定显示
3. Inspector / HUD 可浮顶且不抢焦点
4. Sidebar / Chart / Watchlist / BottomBar 尺寸稳定
5. 所有主窗口内面板共享同一个 AppState
6. 重型窗口可独立打开、关闭、恢复
7. 现有 SwiftUI views 大部分无需重写
8. ShellViewModel 被 AppState / WindowManager 拆分替代
```

---

## 最终架构一句话

MainWindow 是 AppKit workspace shell；轻量监盘面板嵌入 NSSplitViewController；看盘 tab 下中央 PaneContainer 装 1-N 个 chart Pane（沿用 v17.0 PaneLayout）；重型业务模块独立 NSWindow；HUD 用 NSPanel；hover 用 NSPopover；所有窗口共享同一个 AppState。

---

# V1 实施决策（2026-05-14 拍板）

以下决策在 v17.208 spike 验证可行后 + 用户与 AI review 文档时拍板。

## A1 · ChartScene 嵌入主窗 vs 独立 chart 窗 · 选 B

**决策**：主窗中央 PaneContainer 装 1-N 个 chart Pane（看盘 tab 下激活）+ 保留独立 chart WindowGroup（⌘N 新建副 chart 窗）

**理由**：
- 真实 trader 工作流 · 主屏 PaneContainer 多 chart 切分 + 副屏 ⌘N 副 chart 多周期比图
- v17.59 Tab Detach + v17.66 持久化投入保留（chart 独立窗本来就是 detach 出去的窗）
- 兼顾「多窗口归一」（主窗一站式监盘）与「副屏多 chart」

---

## A2 · DetachedPaneWindow + Tab Detach · 选 C

**决策**：仅 Watchlist / Sector / Position 这 3 个 monitor 面板可 detach 为独立 NSPanel · chart Pane 不可 detach（要副 chart 走 ⌘N 独立 chart 窗）· Sidebar / BottomBar / StatusBar 不可 detach（主窗骨架）

**理由**：
- trader 真实需求是「自选 / 板块 / 持仓拖副屏盯，让出主屏给 chart」
- 限定 3 个 monitor 简化复杂度
- detach 后变 NSPanel（与 Inspector / HUD 同模式 · 复用）
- chart Pane detach 通过 ⌘N 独立 chart 窗解决（更原生）

**代码影响**：
- 现 `DetachedPaneWindow.swift` 132 行简化重写
- 现 ShellViewModel.markPaneDetached 改名 `markMonitorDetached(monitorID:)`
- 现 detachedPaneIDStrings 改 `detachedMonitorPanelIDs`

---

## A3 · Workspace 概念 · 选 C

**决策**：workspace 完整保留 · 仅在看盘 tab 下激活 · 套利 / 期权 / 复盘 / 训练独立窗内不引入 workspace · 看盘下保留多 workspace + chart Pane 1/2/4/6/9 切分

**理由**：
- workspace 核心价值是 trader 切场景（"鲁班套利"/"期权策略"/"复盘"workspace 切换 chart 状态组合）
- v17.62 JSON 导入导出 / v17.67 5 内置预设 / v17.81 用户预设系统全部保留
- 看盘 tab 下 PaneContainer 支持 1-N 个 chart Pane · 沿用 v17.0 PaneLayout（PaneKind 限定 .chart 单一）
- WorkspaceTabBar 顶部仍显示 workspace 列表 · trader 视觉熟悉

**代码影响**：
- Workspace struct 保留全字段（panes / paneLayout / etc.）
- PaneContainer 概念保留 · 但嵌套 NSSplitViewController 实现 · 不用 SwiftUI HSplitView
- 仅删除 PaneKind 中的非 chart case（看盘 tab 下 PaneContainer 仅装 chart Pane · 其他 PaneKind 重型走独立窗）
- v17.20 PaneContextMenu "更换 Pane 类型" 8 候选简化为只 chart · 实际删除该菜单

---

## A4 · ShellViewModel 拆分映射表（A3 C 调整版）

**3 阶段分步迁** · 不一刀切 · ShellViewModel 717 行最终拆光删除文件。

### Step 3a · 抽 AppState（@MainActor ObservableObject · 跨窗口共享业务状态）

```text
进 AppState (新增 selectedSymbol 替代 NotificationCenter):
- primaryTab: PrimaryTab
- workspaces: [Workspace]              (Pane 切分保留 · A3 C)
- activeWorkspaceID: UUID?
- maximizedPaneID: UUID?                (Pane 切分保留 · A3 C)
- groupBindings: [GroupColor: SymbolBinding]
- userPresets: [UserWorkspacePreset]
- recentPaletteCommands: [String]
- chartTheme: ChartTheme
- selectedSymbol: String?               (新增 · 替代 watchlistInstrumentSelected Notification)
```

工时：0.3d

### Step 3b · WindowManager 接管窗口生命周期

```text
进 WindowManager:
- mainWindowController: MainWindowController
- heavyWindowRegistry: [HeavyWindowKind: NSWindow]
- panelRegistry: [PanelKind: NSPanel]
- popoverService: HoverPopoverService
- detachedMonitorPanelIDs: [String]     (A2 C · 仅 monitor 面板)
- hasRestoredDetachedPanels: Bool
- isApplicationTerminating: Bool

方法：
- openMainWindow / activateMainWindow
- openHeavyWindow(.option/.spread/.review/.training/...)
- openPanel(.inspector/.patternHUD/.multiTimeframeHUD)
- detachMonitorPanel(monitorID:)        (A2 C · 改名)
- markMonitorDetached(monitorID:)       (A2 C · 改名)
- closeWindow / closePanel / 等清理方法
```

工时：0.3d

### Step 3c · Pane 操作方法迁 AppState（A3 C 保留 Pane 概念）

```text
进 AppState 工具方法 (操作 workspaces.panes):
- toggleMaximize / exitMaximize         (Pane 保留 · A3 C)
- setPaneSymbol(paneID:symbol:)
- setPanePeriod(paneID:periodRaw:)
- setPaneGroupColor(paneID:color:)
- resetPaneConfig(paneID:)
- effectiveSymbol(for: PaneConfig)
- effectiveCrosshair(for: PaneConfig)
- newWorkspace / newWorkspace(from:) / duplicateWorkspace / closeWorkspace
- renameWorkspace / activateWorkspace / moveWorkspace
- exportWorkspace / importWorkspace
- saveActiveWorkspaceAsUserPreset / deleteUserPreset / renameUserPreset / moveUserPreset
- setPaneLayout / setPaneCrosshair

删除 (A3 C 单一 PaneKind .chart 后无意义):
- changePaneKind                        (PaneKind 限定 .chart · 不再支持切类型)
```

### Step 3d · 主窗 @State 持有 UI 临时状态

```text
进 MainWindowView @State (主窗局部 UI 状态 · 不跨窗):
- fKeyToast: String?
- sidebarFocusTrigger: Int
- showCommandPalette / showInstrumentInfoSheet / showQuickOrderSheet
- showPresetPickerSheet / showSidebarLayoutSheet
- 各 F 键 toast 方法 (focusSidebar / cyclePeriodOnActivePane / etc.)
```

工时：0.2d

### 总工时 A4 · 0.8-1d

---

## A5 · MainWindow vs WindowGroup 关系 · 选 B

**决策**：保留 SwiftUI `WindowGroup("主工作台", id: "main")` · 内部 root view = `MainWindowView` SwiftUI · MainWindowView body 是 `MainSplitViewBridge: NSViewControllerRepresentable` 包 `NSSplitViewController`

**理由**：
- v17.208 spike 已验证此模式可行
- 不动 SwiftUI App 体系（Scene Phase / CommandGroup / openWindow / WindowGroup 全保留）
- 与现有 28 个 WindowGroup 风格一致

**代码模式**：

```swift
@main
struct FuturesTerminalApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup("主工作台", id: "main") {
            MainWindowView()
                .environmentObject(coordinator.appState)
                .environment(\.windowManager, coordinator.windowManager)
        }
        .defaultSize(width: 1600, height: 1000)
        .commands {
            // 所有 CommandGroup 挂主窗（A6）
            CommandGroup(replacing: .newItem) { ... }
            CommandMenu("工具") { ... }
        }

        // 重型独立窗口 WindowGroup 保留（13 个 · 不变）
        WindowGroup("期权", id: "option") { OptionWindow().injectEnv(coordinator) }
        // ... 13 个重型 window
    }
}

struct MainWindowView: View {
    var body: some View {
        MainSplitViewBridge()
    }
}

struct MainSplitViewBridge: NSViewControllerRepresentable {
    @EnvironmentObject var appState: AppState
    func makeNSViewController(context: Context) -> NSSplitViewController { ... }
}
```

---

## A6 · CommandGroup 挂哪 · 选 A

**决策**：所有 CommandGroup / CommandMenu 移到主窗 `WindowGroup("主工作台", id: "main")` 上（从当前 chart WindowGroup line 342 迁出）

**理由**：
- 主窗永远在前台 · 菜单一直激活
- chart WindowGroup 改名前是次级窗口 · CommandGroup 挂上反直觉

**代码影响**：
- 移 CommandGroup 一段代码 · 0d

---

## C1 · NSHostingController Environment 注入 boilerplate 收敛

spike 验证每个 NSHostingController 需手动注入 6 个 environment · 用 helper 收敛：

```swift
extension NSHostingController {
    static func wrapped<V: View>(_ view: V, in coordinator: AppCoordinator) -> NSHostingController<some View> {
        NSHostingController(rootView:
            view
                .environmentObject(coordinator.appState)
                .environment(\.storeManager, coordinator.storeManager)
                .environment(\.analytics, coordinator.analytics)
                .environment(\.alertEvaluator, coordinator.alertEvaluator)
                .environment(\.simulatedTradingEngine, coordinator.simulatedTradingEngine)
                .environment(\.bannerService, coordinator.bannerService)
        )
    }
}

// 调用方:
let chartHC = NSHostingController<_>.wrapped(ChartScene(), in: coordinator)
```

---

## C2 · MainWindow 数值约束

```text
minSize         : NSSize(width: 1200, height: 800)
defaultSize     : NSSize(width: 1600, height: 1000)
setFrameAutosaveName: "main-workspace.v1"
```

---

## C3 · Sidebar 宽度约束（NSSplitViewItem）

```text
minimumThickness : 200
maximumThickness : 360
preferredThickness: 240    (与当前 ShellMetrics.sidebarWidth 一致)
canCollapse      : true    (折叠到 60pt 走 ShellMetrics.sidebarCollapsedWidth)
```

---

## C4 · 重型独立 NSWindow tabbing

启用 macOS 原生窗口 tabbing：

```swift
NSWindow.allowsAutomaticWindowTabbing = true
```

trader 可把 OptionWindow / SpreadWindow 等拖到一起合 tabs · macOS 原生体验。

---

## D1 · 实施后风险 · SwiftUI .sheet 在 NSHostingController 内验证

**风险**：ChartScene 内大量 `.sheet`（ChartTypeOptionsSheet / HUDFieldsSheet / PatternsListSheet / ResonanceStatsSheet 等十几个）· spike 未测 sheet 行为。

**验证策略**：Step 2 完成后立即测一个 sheet（如 `⌘⌥1` ChartTypeOptionsSheet）· 通过再继续后续 Step。失败则评估 sheet → NSWindow openWindow 迁移方案（参考 v17.202 CSV import 模式）。

---

## D2 · isHostedInShell 语义改 isInMonitorPanel

WatchlistWindow / SectorWindow / PositionWindow 等已有 `@Environment(\.isHostedInShell)` · 改造后嵌入主窗 monitor 区 · 语义改成 `isInMonitorPanel`。

但 V1 实施时**保留 isHostedInShell 名字**（避免改 30+ 调用点）· 仅注释加 「v17.208+ 实际语义=嵌入主窗 monitor split item」。

---

## D3 · 回退策略

**双窗口入口**（V1 上线后 Mac 切机验证 1 周）：

- 菜单工具 「🆕 主工作台（V1 AppKit）」⌘1 ← 新 MainWindow
- 菜单工具 「🧪 旧 Shell（回退）」⌘0 ← 旧 ShellWindow（保留 1 周作 fallback）

Mac 切机验证 1 周后无重大问题 · 删 Shell 一系列文件（ShellWindow / ShellViewModel / PaneContainer / 等约 5400 行）。

---

## E1 · 渐进迁移 · ShellViewModel 不立刻删

Step 3a-3d 抽 AppState / WindowManager / 局部 / 删除 时 · ShellViewModel 标 `@available(*, deprecated)` 但保留代码。

现存 ShellSidebar / WorkspaceTabBar / PaneContainer / 等仍用 ShellViewModel · 逐个迁 AppState：

1. Step 4 NSPanel 实施时同步迁 ShellSidebar → AppState
2. Step 5 NSPopover 实施时同步迁 WorkspaceTabBar → AppState
3. Step 6 主窗稳定后 · ShellViewModel 全删

避免一刀切导致 Step 3 工作量爆炸。

---

## V1 验收标准（扩展为 11 条）

```text
1. 子面板不会撑爆主窗口
2. hover tooltip 可 0 延迟稳定显示（NSPopover · 替代 .help() 1.5s）
3. Inspector / HUD 可浮顶且不抢焦点
4. Sidebar / Chart / Watchlist / BottomBar 尺寸稳定
5. 所有主窗口内面板共享同一个 AppState
6. 重型窗口可独立打开、关闭、恢复
7. 现有 SwiftUI views 大部分无需重写
8. ShellViewModel 被 AppState / WindowManager 拆分替代
9. 看盘 tab 下 PaneContainer 支持 1/2/4/6/9 chart Pane 切分（A3 C）
10. PrimaryTab 5 tab 点击行为符合 A1 规则（看盘=主窗 / 其他=独立窗）
11. Monitor 面板（Watchlist/Sector/Position）可 detach 为 NSPanel 拖副屏（A2 C）
```

---

## V1 实施工时（按决策细化）

| Step | 工作 | 工时 |
|---|---|---|
| 1 | AppCoordinator + WindowManager + MainWindowController + MainSplitViewController（spike 模式扩展）| 1d |
| 2 | NSHostingController 包 Sidebar / PaneContainer / Watchlist / Sector / Position / BottomBar / StatusBar | 0.5-1d |
| 3 | AppState 拆分（A4 · 3a/3b/3c/3d 分步）| 0.8-1d |
| 4 | NSPanel: Inspector / PatternHUD / MultiTimeframeHUD | 0.5-1d |
| 5 | NSPopover HoverPopoverService 替代 .help() | 0.3-0.5d |
| 6 | 重型窗口集中迁入 WindowManager 调用（保留 WindowGroup）| 0.3d |
| + | PrimaryTabBar 行为重塑（A1）| 0.3d |
| + | PaneContainer 嵌套 NSSplitView（A3 C · chart Pane 1-N 切分）| 0.3d |
| + | Monitor 面板 detach NSPanel（A2 C）| 0.3d |
| + | 切机 + 11 条验收 + 回归测试 | 0.5-1d |

**总计 5-6d**（比原估 4-5d 增加 0.5-1d · 主要 A3 C 比 A3 B 多 0.5d Pane 切分实现 · A4 拆分映射明确后实际工时清晰）
