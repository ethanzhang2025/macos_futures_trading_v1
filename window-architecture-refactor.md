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
│   │   └── NSSplitViewController
│   │       ├── NSHostingController(Sidebar)
│   │       ├── NSHostingController(ChartScene)
│   │       ├── NSHostingController(WatchlistView / SectorView / PositionView)
│   │       └── NSHostingController(BottomBar + StatusBar)
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
└── NSSplitViewController
    ├── Sidebar
    ├── ChartScene
    ├── MonitorSplitItems (Watchlist / Sector / Position)
    └── BottomBar + StatusBar
```

主窗口内嵌模块包括：

- Sidebar
- ChartScene
- WorkspaceTab
- Watchlist
- Sector
- Position
- BottomBar
- StatusBar
- 轻量监盘类面板

注意：

- 上方结构图中的 `MonitorSplitItems` 是**概念性占位**，不是新组件
- V1 **不创建** `EmbeddedMonitorPanel.swift` / `MonitorSplitItems.swift`
- 直接把现有 `WatchlistView` / `SectorView` / `PositionView` 通过 `NSHostingController` 注册为 split item
- Heatmap **不嵌入**主窗 · 保持现有独立 NSWindow（详见下文 Heatmap 处理规则）

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
light heatmap
bottom status
workspace tab
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
Sidebar
ChartScene
Watchlist / EmbeddedMonitorPanel
BottomBar
StatusBar
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
1. Sidebar 有最小宽度和最大宽度
2. ChartScene 是主区域
3. EmbeddedMonitorPanel 可折叠
4. BottomBar / StatusBar 高度固定或半固定
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

MainWindow 是 AppKit workspace shell；轻量监盘面板嵌入 NSSplitViewController；重型业务模块独立 NSWindow；HUD 用 NSPanel；hover 用 NSPopover；所有窗口共享同一个 AppState。
