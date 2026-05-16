// MainApp · 期货终端真 App 入口
//
// 取代 MetalKLineWindowDemo 命令式 NSApplication.run 的 PoC 路径，
// 用 SwiftUI App 协议提供：
//   - WindowGroup × 2（K 线图表 / 自选合约）· Cmd+N / Cmd+L 多窗口隔离
//   - Settings Scene · Cmd+, 自动绑定偏好设置窗口
//   - 主菜单 .commands（File / View / Window 骨架）
//
// 后续 WP 接入路径：
//   - WP-43 自选 UI → 替换 WatchlistContentView 真实数据源
//   - WP-44 多周期 + 多窗口 UI → CommandMenu 加周期切换 Cmd+1~9
//   - WP-90 上线决策 → Settings 真实订阅 / 账号 / 偏好
//   - M5 集成（StoreCore）→ App.init() 一次 init 6 store + 注入到 Scene ✅ 已交付（此文件）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Shared
import StoreCore
import AlertCore
import IndicatorCore
import TradingCore

// MARK: - StoreManager 环境注入（M5 集中接入持久化）

private struct StoreManagerKey: EnvironmentKey {
    static let defaultValue: StoreManager? = nil
}

extension EnvironmentValues {
    /// M5 持久化：StoreManager 在 App.init 一次性创建 · 通过 .environment 注入到所有 Scene
    /// nil = 未启动成功（路径写入失败 / SQLite 错误等）· Window 自动 fallback 到 Mock 数据
    var storeManager: StoreManager? {
        get { self[StoreManagerKey.self] }
        set { self[StoreManagerKey.self] = newValue }
    }
}

// MARK: - AnalyticsService 环境注入（M5 持久化第 5 批 c · StoreManager 7/7 收官）

private struct AnalyticsServiceKey: EnvironmentKey {
    static let defaultValue: AnalyticsService? = nil
}

extension EnvironmentValues {
    /// 埋点服务：App.init 一次性创建 · 注入 storeManager.analytics + 稳定 deviceID + appVersion
    /// nil = storeManager 未启动 · 调用方走 fire-and-forget 模式（Task + try?）安全降级
    var analytics: AnalyticsService? {
        get { self[AnalyticsServiceKey.self] }
        set { self[AnalyticsServiceKey.self] = newValue }
    }
}

// MARK: - AlertEvaluator 环境注入（v11.0+1 · alerts 真 e2e · K 线 close 假 Tick · 真 Tick Stage B 接）

private struct AlertEvaluatorKey: EnvironmentKey {
    static let defaultValue: AlertEvaluator? = nil
}

extension EnvironmentValues {
    /// 预警评估器：App.init 一次性创建 · 注入 storeManager.alertHistory + NotificationDispatcher
    /// AlertWindow 监听 observe 流写 history · ChartScene 用 K 线 close 模拟 onTick 触发评估
    /// nil = storeManager 未启动 · UI 退化为 testTrigger 占位模式（与 v11.0+1 修复前等价）
    var alertEvaluator: AlertEvaluator? {
        get { self[AlertEvaluatorKey.self] }
        set { self[AlertEvaluatorKey.self] = newValue }
    }
}

// MARK: - SimulatedTradingEngine 环境注入（v15.4 · WP-54 SimNow 模拟训练）

private struct SimulatedTradingEngineKey: EnvironmentKey {
    static let defaultValue: SimulatedTradingEngine? = nil
}

extension EnvironmentValues {
    /// 模拟撮合引擎：App.init 一次性创建 · 初始资金 1,000,000 · 注册主力 4 合约（RB0/IF0/AU0/CU0）
    /// TradingWindow 订阅 observe + submitOrder/cancelOrder · ChartScene K 线 close 模拟 onTick 撮合
    /// 不依赖 CTP 二进制 · M5 节点 SimNow 真接入留 v15.5+
    var simulatedTradingEngine: SimulatedTradingEngine? {
        get { self[SimulatedTradingEngineKey.self] }
        set { self[SimulatedTradingEngineKey.self] = newValue }
    }
}

// MARK: - BannerService 环境注入（v15.18 · WP-120 App 内 Banner 推送）

private struct BannerServiceKey: EnvironmentKey {
    static let defaultValue: BannerService? = nil
}

extension EnvironmentValues {
    /// Banner 服务：App.init 一次性创建 · stub source · UserDefaults dismissal store
    /// 后端就绪后切 HTTPBannerSource · ChartScene 顶部 overlay 监听
    var bannerService: BannerService? {
        get { self[BannerServiceKey.self] }
        set { self[BannerServiceKey.self] = newValue }
    }
}

@main
struct FuturesTerminalApp: App {

    /// M5 集中接入：启动时一次性 init 7 store · 通过 .environment 注入到所有 Scene
    /// 失败（路径写入失败 / SQLite 错误 / 加密参数错）→ storeManager = nil · Window fallback 到 Mock
    /// 路径：~/Library/Application Support/FuturesTerminal/db/（macOS 沙盒友好 · M6 .app bundle 后路径不变）
    /// passphrase = nil（明文）· M5 上线前评估是否启用 SQLCipher（视用户设置 / 合规要求）
    private let storeManager: StoreManager?

    /// 埋点服务（M5 持久化第 5 批 c · StoreManager 7/7 收官 · WP-133a/G2）
    /// storeManager nil 时 analytics nil · 调用方走 fire-and-forget 模式安全降级
    private let analytics: AnalyticsService?

    /// 预警评估器（v11.0+1 · alerts 真 e2e · 注入 alertHistory store · ChartScene 调 onTick）
    /// storeManager nil 时 evaluator nil · UI 退化 testTrigger 占位
    private let alertEvaluator: AlertEvaluator?

    /// 模拟撮合引擎（v15.4 · WP-54 SimNow 模拟训练第 2 批）
    /// 默认初始资金 1,000,000 · 启动注册 4 主力合约（RB0/IF0/AU0/CU0）
    private let simulatedTradingEngine: SimulatedTradingEngine?

    /// App 生命周期 session 跟踪器（v15.18 · WP-133a session_start/end 3 分钟规则）
    /// analytics nil 时 nil · 持有强引用与 App 生命周期绑定（无 deinit · 跨次启动靠 UserDefaults lastSessionEndMs）
    private let lifecycleObserver: AppLifecycleObserver?

    /// 埋点上报 driver（v15.18 · WP-133b 客户端层闭环）
    /// stub mode · 后端 WP-80 就绪后切 HTTPBatchUploadClient · 客户端 wire 不动
    /// 周期 30s poll · 双阈值（5min OR 100 条）触发 · App init 后 fire-and-forget start
    private let batchUploadDriver: BatchUploadDriver?

    /// App 内 Banner 服务（v15.18 · WP-120 推送）
    /// stub source（默认空 · 不骚扰）· UserDefaults dismissal · ChartScene 顶部 overlay
    private let bannerService: BannerService?

    /// Banner 周期刷新 driver（v15.18 · 5min poll · 后端可热推送 / 撤回）
    private let bannerRefreshDriver: BannerRefreshDriver?

    /// v17.59 · ShellViewModel 提到 App 级（@StateObject）· 让 detached Pane 多屏共享同一 instance
    /// 跨窗口 group 联动 / Workspace 列表 / 持仓 / 等 state 全部共享
    /// v17.225 · Step 3a · 改为 init 内创建 · 同 ref 传给 AppCoordinator(shellVM:) 让 AppState facade 包它
    @StateObject private var shellVM: ShellViewModel

    /// v17.209 · V1 重构 Step 1 · AppKitShell 顶层协调器（持 AppState + WindowManager）
    /// D3 双窗口入口阶段两套并存 · 旧 Shell ⌘⌃0 · V1 主窗 ⌘⌃1 · 1 周稳定后删旧 Shell
    /// v17.225 · Step 3a · AppState facade 包同一个 shellVM · 新 V1 组件读 AppState · 老调用继续 shellVM
    @StateObject private var coordinator: AppCoordinator

    init() {
        // v17.225 · Step 3a · ShellViewModel 与 AppCoordinator 共享同一 ref
        // AppState facade 9 字段全部转发到此 shellVM · 二者读写同一数据源
        let shell = ShellViewModel()
        _shellVM = StateObject(wrappedValue: shell)
        _coordinator = StateObject(wrappedValue: AppCoordinator(shellVM: shell))

        // swift run 是 non-bundle 可执行 · macOS 默认不把它当前台 App ·
        // 菜单栏不切换 · ⌘N / ⌘L / ⌘, 全部落到 Terminal 上。
        // 显式声明 .regular 让主菜单栏 + 全局快捷键 + Dock 图标正常工作。
        // M6 打包 .app bundle 后此调用变成 no-op（Bundle Info.plist 已声明）。
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let manager = Self.bootStoreManager()
        self.storeManager = manager
        self.analytics = manager.map {
            AnalyticsService(
                store: $0.analytics,
                deviceID: Self.loadOrCreateDeviceID(),
                appVersion: Self.bundleAppVersion
            )
        }
        // v15.17 · WP-52 通知通道接入 · macOS 注册 SystemNoticeChannel + SoundChannel
        // v15.18 · 按 FeatureFlag 决定启用的 channels（系统通知 / 声音 用户可关）
        // v15.18 · alertCenter 主开关 · 关闭时整个 evaluator 不启动（dispatcher 空 channels · evaluator 不评估）
        self.alertEvaluator = manager.map {
            let defaults = UserDefaults.standard
            let centerOn = defaults.object(forKey: "featureFlag.alert.center") as? Bool
                ?? FeatureFlag.alertCenter.defaultValue
            #if canImport(AppKit) && os(macOS)
            var channels: [any NotificationChannel] = []
            if centerOn {
                channels.append(InAppOverlayChannel())
                let sysOn = defaults.object(forKey: "featureFlag.alert.systemNotification") as? Bool
                    ?? FeatureFlag.alertSystemNotification.defaultValue
                let soundOn = defaults.object(forKey: "featureFlag.alert.sound") as? Bool
                    ?? FeatureFlag.alertSound.defaultValue
                if sysOn { channels.append(SystemNoticeChannel()) }
                if soundOn { channels.append(SoundChannel()) }
            }
            let dispatcher = NotificationDispatcher(channels: channels)
            #else
            let dispatcher = NotificationDispatcher()
            #endif
            return AlertEvaluator(history: $0.alertHistory, dispatcher: dispatcher)
        }
        // v15.4 模拟撮合引擎：100w 初始资金 + 4 主力合约注册（async actor 初始化用 Task 异步注册）
        // v15.6 启动加载持久化快照 · 无快照保留默认初始资金 · 注册合约始终运行（合约不入快照 · 启动 hardcoded）
        let engine = SimulatedTradingEngine(initialBalance: 1_000_000)
        self.simulatedTradingEngine = engine
        Task {
            await engine.registerContracts(SimulatedContractDefaults.list)
            if let snapshot = SimulatedTradingStore.load() {
                await engine.restore(snapshot)
            }
        }
        // app_launch 异步发 · 失败静默（埋点不阻塞 App 启动）
        // v15.18 · 启动按 FeatureFlag.analyticsEnabled 设置 enabled · 用户在 Settings 隐私 tab 可关闭
        if let service = self.analytics {
            let enabled = UserDefaults.standard.object(forKey: "featureFlag.analytics.enabled") as? Bool
                ?? FeatureFlag.analyticsEnabled.defaultValue
            Task {
                await service.setEnabled(enabled)
                _ = try? await service.record(.appLaunch, userID: Self.anonymousUserID)
            }
        }
        // v15.18 · WP-120 BannerService（stub source 默认空 · UserDefaults dismissal 持久）
        let banner = BannerService(
            store: UserDefaultsBannerDismissalStore(),
            source: StubBannerSource()
        )
        self.bannerService = banner
        // v15.18 · BannerRefreshDriver 5min poll 启动后周期 fetch（后端可热推送 / 撤回）
        let bannerDriver = BannerRefreshDriver(service: banner)
        self.bannerRefreshDriver = bannerDriver
        Task { await bannerDriver.start() }

        // v15.18 · WP-133b BatchUploadDriver wire（stub client · 后端就绪后切 HTTP client）
        // 周期 30s poll · 双阈值（5min OR 100 条）触发 · driver 自管 task 生命周期
        // onFailure callback 接 banner：连续 5 次失败 emit warning（让用户感知后台异常）
        let driver = manager.map { mgr in
            BatchUploadDriver(
                store: mgr.analytics,
                client: StubBatchUploadClient(),
                batchSize: 100,
                timeTriggerMs: 5 * 60 * 1000,
                pollIntervalSec: 30,
                onFailure: { [weak banner] consecutive, _, error in
                    guard let banner else { return }
                    if consecutive == 5 {   // 5 连败首次触发 · 不重复 emit
                        let nowMs = AnalyticsEvent.nowMs()
                        let warn = Banner(
                            id: "system.upload-failure",
                            title: "埋点上报中断",
                            body: "已连续 5 次失败 · 后台自动重试中（\(error)）",
                            level: .warning,
                            createdAtMs: nowMs,
                            expiredAtMs: nowMs + 60 * 60 * 1000   // 1 小时过期
                        )
                        await banner.emitLocal(warn)
                    }
                }
            )
        }
        self.batchUploadDriver = driver
        if let driver {
            Task { await driver.start() }
            // v15.18 · UserDefaults didChange 监听 · 切埋点开关时立即 hot-reload driver.setEnabled
            // 不存 token · App 生命周期与 NotificationCenter 同长（避免 deinit 复杂）
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                let enabled = UserDefaults.standard.object(forKey: "featureFlag.analytics.enabled") as? Bool
                    ?? FeatureFlag.analyticsEnabled.defaultValue
                Task { await driver.setEnabled(enabled) }
            }
        }
        // v15.18 · WP-133a session_start/end wire（didBecomeActive 触发首次 session_start · 3 分钟规则跨启动）
        // App.init 后 NSApplication 主循环开始 · 首个 didBecomeActive 通知会触发 sessionStart
        // willResignActive 时除发 session_end 外还 flush driver（防后台被杀丢事件）
        self.lifecycleObserver = self.analytics.map {
            AppLifecycleObserver(analytics: $0, userID: Self.anonymousUserID, uploadDriver: driver)
        }
        // v15.97 · 工作区跨启动恢复 v2（toggle 开 + lastWorkspaceID 命中 store → broadcast 通知 M5+ 消费者）
        // 异步执行 · 失败静默（不阻塞 App 启动）· 用 storeManager 校验 ID 真存在（防被删模板的过期 ID）
        if let manager = self.storeManager {
            Task { await Self.restoreLastWorkspaceIfNeeded(store: manager.workspaceBook) }
        }
    }

    /// v15.97 · 启动恢复上次工作区 · toggle 关 / 无 lastWorkspaceID / store 内不存在 → 静默跳过
    /// broadcast 用 .workspaceTemplateActivated 通知（与 WorkspaceWindow.activate 同口径）· object: templateID String
    /// 延迟 1.2s 等 SwiftUI Scene 装好（首个 WindowGroup .onAppear / 监听者 onReceive 注册完）
    private static func restoreLastWorkspaceIfNeeded(store: SQLiteWorkspaceBookStore) async {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: WorkspaceRestoreDefaults.restoreEnabledKey) as? Bool
            ?? WorkspaceRestoreDefaults.restoreEnabledDefault
        guard enabled,
              let raw = defaults.string(forKey: WorkspaceRestoreDefaults.lastWorkspaceIDKey),
              let id = UUID(uuidString: raw),
              let book = try? await store.load(),
              book.template(id: id) != nil
        else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .workspaceTemplateActivated,
                object: id.uuidString
            )
        }
    }

    /// 启动 StoreManager · 失败保留 nil · UI 走 Mock fallback（不影响 App 启动）
    private static func bootStoreManager() -> StoreManager? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = base.appendingPathComponent("FuturesTerminal/db")
        return try? StoreManager(rootDirectory: root, passphrase: nil)
    }

    /// 跨启动稳定 deviceID（v1 用 UserDefaults · 首启生成 UUID 写入 · 后续 readback）
    /// IAP 上线后可加 Keychain 备份；当前 v1 接受"用户清 UserDefaults 时 deviceID 重置"
    private static func loadOrCreateDeviceID() -> String {
        let key = "com.futures-terminal.analytics.deviceID"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: key)
        return newID
    }

    /// v17.228 · 构造 AppKitShellEnvironment helper · 给 V1 主窗 WindowGroup + 视图菜单 detach 按钮复用
    /// 多处需要 env 时不重复 8 字段构造代码
    private func makeEnv() -> AppKitShellEnvironment {
        AppKitShellEnvironment(
            shellVM: shellVM,
            storeManager: storeManager,
            analytics: analytics,
            alertEvaluator: alertEvaluator,
            simulatedTradingEngine: simulatedTradingEngine,
            bannerService: bannerService,
            appState: coordinator.appState,
            windowManager: coordinator.windowManager
        )
    }

    /// v1 占位 · 无登录态 · 接 Apple ID / 用户系统后替换
    static let anonymousUserID = "anonymous"

    /// v1 硬编码 · M6 打包后改为读 Bundle Info.plist CFBundleShortVersionString
    static let bundleAppVersion = "0.0.1"

    var body: some Scene {
        // v17.0 PoC Step 1 · Shell 主工作台（占位 · Step 2+ 完整实装）· 默认启动
        // 老 28 个 WindowGroup 保留作为"分离窗口"模式
        WindowGroup("主工作台", id: "shell") {
            ShellWindow()
                .environmentObject(shellVM)   // v17.59 · 共享 App 级 ShellViewModel
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .environment(\.bannerService, bannerService)
        }
        .defaultSize(width: 1600, height: 1000)

        // v17.208 · 方案 3 spike · AppKit NSSplitViewController + NSHostingController 桥接验证
        // 不动现有 Shell · 独立窗口 · 工具菜单「🧪 AppKit Spike（⌘⌥⇧K）」打开
        WindowGroup("AppKit Spike", id: "appkitSpike") {
            AppKitShellSpikeWindow()
                .environmentObject(shellVM)
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .environment(\.bannerService, bannerService)
        }
        .defaultSize(width: 1600, height: 900)

        // v17.209 · V1 重构 Step 2 · AppKit 主工作台（新 Shell）· D3 双窗口入口 ⌘⌃1
        // A5=B 决策 · SwiftUI WindowGroup + NSViewControllerRepresentable + NSSplitViewController 三层桥接
        // Step 2 · 3 split item 真组件（ShellSidebar / ChartScene / WatchlistWindow）+ 顶/底 PrimaryTabBar/BottomTradingBar/ShellStatusBar
        WindowGroup("主工作台 V1", id: "mainV1") {
            MainWindowView(env: makeEnv())
                .environmentObject(shellVM)
        }
        // v17.212 · default 1800x1100 · 留给 ChartScene toolbar 完整空间（sidebar 240 + watchlist 240 → chart 1320pt 够）
        .defaultSize(width: 1800, height: 1100)

        // 主图表窗口（保留 · 用户主动"分离"才打开 · Cmd+N 新建多个）
        // v15.17 · 移除全局 .preferredColorScheme(.dark) · ChartScene 内动态 chartTheme.colorScheme · sheet/popup 跟主题
        WindowGroup("K 线图表", id: "chart") {
            ChartScene()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .environment(\.bannerService, bannerService)
        }
        // 视觉迭代第 13 项：显式 defaultSize · 启动时合理大窗 · 不依赖 SwiftUI 默认
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewChartButton()
                Divider()
                OpenWatchlistButton()
                OpenReviewButton()
                OpenAlertButton()
                OpenJournalButton()
                OpenWorkspaceButton()
                OpenTradingButton()
                OpenTrainingButton()  // v15.23 batch14 · WP-54 模拟训练 ⌘⇧T
                OpenMultiChartButton() // v15.23 batch50 · WP-44 多图表 ⌘⌥M
                OpenSpreadButton()     // v15.27 · WP-套利分析 ⌘⌥S
                OpenOptionButton()     // v15.32 · WP-期权工作台 ⌘⌥O
                OpenSectorButton()     // v15.43 · WP-行情 V3 板块联动 ⌘⌥B
                OpenHeatmapButton()    // v15.44 · WP-行情 热力地图 ⌘⌥H
                OpenPositionButton()   // v15.47 · WP-行情 多空持仓 ⌘⌥P
                OpenCorrelationButton() // v15.48 · WP-行情 关联性矩阵 ⌘⌥C
                OpenMoneyFlowButton()   // v15.49 · WP-行情 资金流向 ⌘⌥N
                OpenCalendarSpreadButton() // v15.50 · WP-套利 跨期 ⌘⌥X
                OpenInstrumentDashboardButton() // v15.51 · WP-行情 品种深度分析 ⌘⌥I
                OpenSessionCompareButton()      // v15.52 · WP-行情 时段对比 ⌘⌥T
                OpenAnomalyMonitorButton()      // v15.54 · WP-行情 异常品种监控 ⌘⌥A
                OpenSpreadAlertButton()         // v15.55 · WP-套利 价差 alert ⌘⌥W
                OpenBacktestButton()            // v17.39 · D3 公式回测窗口 ⌘⌥K
            }
            CommandMenu("视图") {
                Text("周期切换：⌘1=1分 / ⌘2=5分 / ⌘3=15分 / ⌘4=30分 / ⌘5=60分 / ⌘6=日（K 线窗口聚焦时生效）")
                    .foregroundColor(.secondary)
                Divider()
                ToggleThemeButton()  // v15.17 · ⌘⇧D 全局切主题（任何窗口前台都能切）
                Divider()
                // v17.224 · V1 主窗 NSSplitView toggle 入口 · 防 collapse 死胡同
                ToggleSidebarButton(windowManager: coordinator.windowManager)
                ToggleMonitorButton(windowManager: coordinator.windowManager)
                Divider()
                // v17.228 · A2=C Mini v1 · Monitor 面板 NSPanel detach 入口
                DetachMonitorPanelButton(
                    kind: .watchlist,
                    label: "📤 拖出自选合约（NSPanel 浮顶副屏）",
                    envProvider: makeEnv,
                    windowManager: coordinator.windowManager
                )
                DetachMonitorPanelButton(
                    kind: .sector,
                    label: "📤 拖出板块联动（NSPanel 浮顶副屏）",
                    envProvider: makeEnv,
                    windowManager: coordinator.windowManager
                )
                DetachMonitorPanelButton(
                    kind: .position,
                    label: "📤 拖出多空持仓（NSPanel 浮顶副屏）",
                    envProvider: makeEnv,
                    windowManager: coordinator.windowManager
                )
                Divider()
                // v17.242 · Step 4 · Inspector 浮顶面板入口（⌘⌥I）· doc 章节 296-302
                OpenInspectorPanelButton(envProvider: makeEnv, windowManager: coordinator.windowManager)
                Divider()
                // v17.231 · V1 主窗面板布局切换 · 直接验「A3=C 1/2/4/6/9 网格」
                Menu("V1 主窗面板布局") {
                    PaneLayoutMenuButton(layout: .single, label: "▢ 单图", shellVM: shellVM)
                    PaneLayoutMenuButton(layout: .twoHorizontal, label: "◫ 左右双图", shellVM: shellVM)
                    PaneLayoutMenuButton(layout: .twoVertical, label: "⬓ 上下双图", shellVM: shellVM)
                    PaneLayoutMenuButton(layout: .four, label: "⊞ 四宫格", shellVM: shellVM)
                    PaneLayoutMenuButton(layout: .sixGrid, label: "▦ 六宫格", shellVM: shellVM)
                    PaneLayoutMenuButton(layout: .nineGrid, label: "▩ 九宫格", shellVM: shellVM)
                }
            }
            CommandMenu("工具") {
                ImportFormulaButton()
                Divider()
                OpenFormulaEditorButton()  // v15.22 batch4 · WP-65 公式编辑器（⌘⌥F）
                Divider()
                OpenCSVImportButton()      // v17.169 · CSV 行情导入器
                Divider()
                OpenCrossLinkageButton()   // v17.175 · 跨合约联动预警规则管理
                Divider()
                OpenAppKitSpikeButton()    // v17.208 · 方案 3 spike · AppKit 桥接可行性验证
                Divider()
                OpenMainWindowV1Button()   // v17.209 · V1 重构 Step 1 · ⌘⌃1 新 AppKit 主工作台
                OpenLegacyShellButton()    // v17.209 · D3 双窗口回退 · ⌘⌃0 旧 Shell（1 周稳定后删）
            }
            // v17.141 · 帮助菜单加全局快捷键速查（⌘⇧/ · 任何窗口前台都能触发）
            CommandGroup(replacing: .help) {
                OpenGlobalShortcutsButton()
            }
        }

        // 自选合约窗口（菜单触发打开 · 单实例 · WP-43 UI · M5 接 SQLiteWatchlistBookStore）
        WindowGroup("自选合约", id: "watchlist") {
            WatchlistWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 880, height: 600)

        // 复盘工作台（⌘R · 8 图独立窗口 · 与 K 线主图区分离）
        WindowGroup("复盘", id: "review") {
            ReviewWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 1280, height: 900)

        // 预警面板（⌘B · Bell · 独立窗口）
        WindowGroup("预警", id: "alert") {
            AlertWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 920, height: 640)

        // 交易日志（⌘J · Journal · 独立窗口 · WP-53 UI · M5 接 SQLiteJournalStore）
        WindowGroup("交易日志", id: "journal") {
            JournalWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 1100, height: 720)

        // 工作区模板（⌘K · workspace · 独立窗口 · WP-55 UI · M5 接 SQLiteWorkspaceBookStore）
        WindowGroup("工作区模板", id: "workspace") {
            WorkspaceWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 1100, height: 720)

        // 模拟交易（⌘T · trading · 独立窗口 · WP-54 v15.4 SimNow 模拟训练）
        WindowGroup("模拟交易", id: "trading") {
            TradingWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .followingChartTheme()  // v15.17 · 跟主图 chartTheme.v1 · sheet/popup 一致
        }
        .defaultSize(width: 1100, height: 720)

        // v15.23 batch14 · 模拟训练（⌘⇧T · training · 纪律规则 + 评分 + 历史 · WP-54 M5 节点 UI 闭环）
        WindowGroup("模拟训练", id: "training") {
            TrainingWindow()
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .followingChartTheme()
        }
        .defaultSize(width: 880, height: 680)

        // v15.23 batch50 · 多图表（⌘⌥M · multichart · 6 grid preset · WP-44 UI 启用）
        WindowGroup("多图表", id: "multichart") {
            MultiChartHost()
                .followingChartTheme()
        }
        .defaultSize(width: 1080, height: 720)

        // v15.22 batch4 · 麦语言公式编辑器（WP-65 · syntax 高亮 + 编辑 + 保存）
        WindowGroup("公式编辑器", id: "formulaEditor") {
            FormulaEditorWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 920, height: 640)

        // v17.202 真修 · CSV K 线导入独立窗口（⌘⇧⌥I）· 原 CommandMenu 内 .sheet 永不弹
        WindowGroup("导入 K 线 CSV", id: "csvImport") {
            CSVImportWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 720, height: 560)

        // v15.27 · WP-套利分析（⌘⌥S · 12 经典对 + 价差图 + ±2σ 通道 + Z-score 统计）
        WindowGroup("套利分析", id: "spread") {
            SpreadWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1080, height: 680)

        // v15.32 · WP-期权工作台（⌘⌥O · T 型链 + 实时 Greeks + 5 经典策略 + PnL 曲线）
        WindowGroup("期权工作台", id: "option") {
            OptionWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1180, height: 760)

        // v15.43 · WP-行情 V3 板块联动（⌘⌥B · 11 板块 Tab + 多空偏向 + 龙头/弱势 + 板块概览）
        WindowGroup("板块联动", id: "sector") {
            SectorWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1080, height: 700)

        // v15.44 · WP-行情 热力地图（⌘⌥H · 60+ 品种网格 · 涨跌染色 · 4 排序）
        WindowGroup("行情热力图", id: "heatmap") {
            HeatmapWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1100, height: 720)

        // v15.47 · WP-行情 多空持仓（⌘⌥P · 60+ 品种多空横条 + 净持仓）
        WindowGroup("多空持仓", id: "position") {
            PositionWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1080, height: 700)

        // v15.48 · WP-行情 关联性矩阵（⌘⌥C · N×N 品种相关性热力图 · 套利+对冲核心工具）
        WindowGroup("关联性矩阵", id: "correlation") {
            CorrelationWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1280, height: 800)

        // v15.49 · WP-行情 资金流向（⌘⌥N · 双向 TopN 榜 + 板块资金分布）
        WindowGroup("资金流向", id: "moneyflow") {
            MoneyFlowWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1100, height: 720)

        // v17.175 · 跨合约联动预警（v17.172 闭环 UI · 规则管理 + 手动评估）
        WindowGroup("跨合约联动", id: "crossLinkage") {
            CrossLinkageRulesWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 820, height: 760)

        // v15.50 · WP-套利 跨期（⌘⌥X · 同品种近-远月价差 + contango/backwardation 判定）
        WindowGroup("跨期套利", id: "calendarSpread") {
            CalendarSpreadWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1080, height: 760)

        // v15.51 · WP-行情 品种深度分析（⌘⌥I · 一站式仪表盘 · K 线+板块情绪+相关品种+跨窗口跳转）
        WindowGroup("品种深度分析", id: "instrumentDashboard") {
            InstrumentDashboardWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1280, height: 780)

        // v15.52 · WP-行情 时段对比（⌘⌥T · 夜盘vs日盘 / 上午vs下午 / 节后效应 3 模式）
        WindowGroup("时段对比", id: "sessionCompare") {
            SessionCompareWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1100, height: 760)

        // v15.54 · WP-行情 异常品种监控（⌘⌥A · 5 维度全市场扫描 · 价格/持仓/资金/背离/离群）
        WindowGroup("异常品种监控", id: "anomalyMonitor") {
            AnomalyMonitorWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1180, height: 780)

        // v15.55 · WP-套利 价差 alert（⌘⌥W · 26 对全市场偏离 · 12 跨品种 + 14 跨期）
        // v15.57 · 注入 alertEvaluator · 行 + 按钮一键加 ⌘B 预警面板
        // v15.67 · 注入 storeManager · spread alert 真持久化（重启恢复）
        WindowGroup("价差套利 alert", id: "spreadAlert") {
            SpreadAlertWindow()
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.storeManager, storeManager)
                .followingChartTheme()
        }
        .defaultSize(width: 1280, height: 760)

        // v17.39 · D3 公式回测窗口（⌘⌥K · MA 双均线 demo · 6 指标 HUD + equity 曲线 + trades 表）
        WindowGroup("公式回测", id: "backtest") {
            BacktestWindow()
                .followingChartTheme()
        }
        .defaultSize(width: 1280, height: 800)

        // v17.59 · 分离 Pane 多屏支持（Tab Detach NSWindow · v17.0 设计 §11）
        // openWindow(id: "detachedPane", value: paneID.uuidString) 触发
        // 通过 paneID 反查 ShellViewModel 找 PaneConfig · 共享同一 ShellViewModel 实例（环境注入）
        // 注意：每个 detached 窗口持有独立 PaneBody · 但 group 联动通过 shellVM 跨窗口同步
        WindowGroup("分离 Pane", id: "detachedPane", for: String.self) { $paneIDStr in
            DetachedPaneWindow(paneIDString: paneIDStr)
                .environmentObject(shellVM)   // v17.59 · 共享同一 ShellViewModel · 跨窗口 group 联动
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .environment(\.bannerService, bannerService)
        }
        .defaultSize(width: 1100, height: 700)

        // 偏好设置（Cmd+, 自动绑定 · macOS 标准）
        Settings {
            SettingsContentView()
                .environment(\.analytics, analytics)   // v15.18 · 隐私 tab 显示 events stats
        }
    }
}

// MARK: - 菜单按钮（@Environment(\.openWindow) 必须在 View 内调用 · 抽出来给 .commands 用）

private struct NewChartButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("新建图表") { openWindow(id: "chart") }
            .keyboardShortcut("n", modifiers: [.command])
    }
}

private struct OpenWatchlistButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("自选合约") { openWindow(id: "watchlist") }
            .keyboardShortcut("l", modifiers: [.command])
    }
}

private struct OpenReviewButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("复盘工作台") { openWindow(id: "review") }
            .keyboardShortcut("r", modifiers: [.command])
    }
}

/// v15.17 · 主菜单"切换主题（深色 / 浅色）"⌘⇧D · 全局快捷键
/// 直接读写 ChartThemeStore · 通过 UserDefaults.didChangeNotification 让所有窗口实时同步（hotfix #14 已搭好同步骨架）
private struct ToggleThemeButton: View {
    @State private var current: ChartTheme = ChartThemeStore.load() ?? .dark
    var body: some View {
        let arrow: String = current == .dark
            ? String(localized: "→ 浅色")
            : String(localized: "→ 深色")
        Button("切换主题（\(arrow)）") {
            let next: ChartTheme = (current == .dark) ? .light : .dark
            ChartThemeStore.save(next)
            current = next
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if let t = ChartThemeStore.load(), t != current { current = t }
        }
    }
}

private struct OpenAlertButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("预警面板") { openWindow(id: "alert") }
            .keyboardShortcut("b", modifiers: [.command])
    }
}

private struct OpenJournalButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("交易日志") { openWindow(id: "journal") }
            .keyboardShortcut("j", modifiers: [.command])
    }
}

private struct OpenWorkspaceButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("工作区模板") { openWindow(id: "workspace") }
            .keyboardShortcut("k", modifiers: [.command])
    }
}

/// v15.22 batch4 · WP-65 公式编辑器入口（工具菜单 · ⌘⌥F · syntax 高亮 + 打开 / 保存）
private struct OpenFormulaEditorButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("公式编辑器（⌘⌥F）") { openWindow(id: "formulaEditor") }
            .keyboardShortcut("f", modifiers: [.command, .option])
    }
}

/// v17.208 · 方案 3 spike · AppKit NSSplitViewController + NSHostingController 桥接验证
private struct OpenAppKitSpikeButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("🧪 AppKit Spike（⌘⌥⇧K）") { openWindow(id: "appkitSpike") }
            .keyboardShortcut("k", modifiers: [.command, .option, .shift])
    }
}

/// v17.209 · V1 重构 Step 1 · 新 AppKit 主工作台入口（⌘⌃1 · D3 双窗口入口）
/// A5=B 决策 · WindowGroup id "mainV1" · 内嵌 NSSplitViewController 3 列布局
private struct OpenMainWindowV1Button: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("🆕 主工作台 V1 · AppKit（⌘⌃1）") { openWindow(id: "mainV1") }
            .keyboardShortcut("1", modifiers: [.command, .control])
    }
}

/// v17.209 · D3 双窗口回退 · 旧 Shell 入口（⌘⌃0 · Mac 验证 1 周稳定后删）
private struct OpenLegacyShellButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("🧪 旧 Shell · 回退（⌘⌃0）") { openWindow(id: "shell") }
            .keyboardShortcut("0", modifiers: [.command, .control])
    }
}

/// v17.224 · V1 主窗 Sidebar toggle（⌘⌃[ · 防 NSSplitView collapse 死胡同）
private struct ToggleSidebarButton: View {
    let windowManager: WindowManager
    var body: some View {
        Button("显示/隐藏 Sidebar（⌘⌃[）") {
            windowManager.mainWindowController.toggleSidebar()
        }
        .keyboardShortcut("[", modifiers: [.command, .control])
    }
}

/// v17.224 · V1 主窗 Monitor (Watchlist) toggle（⌘⌃] · 防 NSSplitView collapse 死胡同）
private struct ToggleMonitorButton: View {
    let windowManager: WindowManager
    var body: some View {
        Button("显示/隐藏 自选合约（⌘⌃]）") {
            windowManager.mainWindowController.toggleMonitor()
        }
        .keyboardShortcut("]", modifiers: [.command, .control])
    }
}

/// v17.228 · A2=C Mini v1 · Monitor 面板 NSPanel detach 入口（视图菜单）
/// trader 把 Watchlist / Sector / Position 拖副屏 · NSPanel 浮顶不抢主窗焦点
private struct DetachMonitorPanelButton: View {
    let kind: MonitorPanelKind
    let label: String
    let envProvider: () -> AppKitShellEnvironment
    let windowManager: WindowManager
    var body: some View {
        Button(label) {
            windowManager.openMonitorPanel(kind, env: envProvider())
        }
    }
}

/// v17.231 · V1 主窗面板布局切换入口（视图菜单 · 直接测 1/2/4/6/9 网格）
/// CommandMenu 内不接 environmentObject · init 直接传 shellVM
private struct PaneLayoutMenuButton: View {
    let layout: PaneLayout
    let label: String
    let shellVM: ShellViewModel
    var body: some View {
        Button(label) {
            shellVM.setPaneLayout(layout)
        }
    }
}

/// v17.242 · Step 4 · V1 主窗 Inspector 浮顶面板入口（⌘⌃I · ⌘⌥I 已被「品种深度分析」全局占用）
/// V1 主窗专属前缀 ⌘⌃ 已用：⌘⌃1 V1 / ⌘⌃0 旧 Shell / ⌘⌃[ Sidebar / ⌘⌃] Monitor
private struct OpenInspectorPanelButton: View {
    let envProvider: () -> AppKitShellEnvironment
    let windowManager: WindowManager
    var body: some View {
        Button("🧭 Inspector 浮顶面板（⌘⌃I）") {
            windowManager.openInspectorPanel(env: envProvider())
        }
        .keyboardShortcut("i", modifiers: [.command, .control])
    }
}

private struct OpenTradingButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("模拟交易") { openWindow(id: "trading") }
            .keyboardShortcut("t", modifiers: [.command])
    }
}

/// v15.23 batch14 · WP-54 模拟训练入口（⌘⇧T · 纪律规则 + 评分 + 历史）
private struct OpenTrainingButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("模拟训练（⌘⇧T）") { openWindow(id: "training") }
            .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}

/// v17.175 · 跨合约联动预警入口（规则管理 + 手动评估 · ⌘⌥L）
private struct OpenCrossLinkageButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("跨合约联动预警（⌘⌥L）") { openWindow(id: "crossLinkage") }
            .keyboardShortcut("l", modifiers: [.command, .option])
    }
}

/// v15.23 batch50 · WP-44 多图表入口（⌘⌥M · 6 grid preset · 数据层 v1 → UI 启用）
private struct OpenMultiChartButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("多图表（⌘⌥M）") { openWindow(id: "multichart") }
            .keyboardShortcut("m", modifiers: [.command, .option])
    }
}

/// v15.27 · WP-套利分析入口（⌘⌥S · 12 经典对 + 价差图 + Z-score 统计）
private struct OpenSpreadButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("套利分析（⌘⌥S）") { openWindow(id: "spread") }
            .keyboardShortcut("s", modifiers: [.command, .option])
    }
}

/// v15.32 · WP-期权工作台入口（⌘⌥O · T 型链 + 实时 Greeks + 5 策略 PnL）
private struct OpenOptionButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("期权工作台（⌘⌥O）") { openWindow(id: "option") }
            .keyboardShortcut("o", modifiers: [.command, .option])
    }
}

/// v15.43 · WP-行情 V3 板块联动入口（⌘⌥B · 11 板块 + 多空偏向 + 龙头/弱势）
private struct OpenSectorButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("板块联动（⌘⌥B）") { openWindow(id: "sector") }
            .keyboardShortcut("b", modifiers: [.command, .option])
    }
}

/// v15.44 · WP-行情 热力地图入口（⌘⌥H · 60+ 品种 grid · 4 排序模式 · 全市场一图全览）
private struct OpenHeatmapButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("行情热力图（⌘⌥H）") { openWindow(id: "heatmap") }
            .keyboardShortcut("h", modifiers: [.command, .option])
    }
}

/// v15.47 · WP-行情 多空持仓入口（⌘⌥P · 60+ 品种多空横条 + 净持仓 + 市场情绪）
private struct OpenPositionButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("多空持仓（⌘⌥P）") { openWindow(id: "position") }
            .keyboardShortcut("p", modifiers: [.command, .option])
    }
}

/// v15.48 · WP-行情 关联性矩阵入口（⌘⌥C · N×N 品种相关性 · 套利对+对冲品种核心工具）
private struct OpenCorrelationButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("关联性矩阵（⌘⌥C）") { openWindow(id: "correlation") }
            .keyboardShortcut("c", modifiers: [.command, .option])
    }
}

/// v15.49 · WP-行情 资金流向入口（⌘⌥N · 双向 TopN 榜 + 板块分布 + 市场态势）
private struct OpenMoneyFlowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("资金流向（⌘⌥N）") { openWindow(id: "moneyflow") }
            .keyboardShortcut("n", modifiers: [.command, .option])
    }
}

/// v15.50 · WP-套利 跨期入口（⌘⌥X · 同品种近月-远月价差 + contango/backwardation）
private struct OpenCalendarSpreadButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("跨期套利（⌘⌥X）") { openWindow(id: "calendarSpread") }
            .keyboardShortcut("x", modifiers: [.command, .option])
    }
}

/// v15.51 · WP-行情 品种深度分析入口（⌘⌥I · 一站式仪表盘）
private struct OpenInstrumentDashboardButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("品种深度分析（⌘⌥I）") { openWindow(id: "instrumentDashboard") }
            .keyboardShortcut("i", modifiers: [.command, .option])
    }
}

/// v15.52 · WP-行情 时段对比入口（⌘⌥T · 夜盘 vs 日盘 / 上午 vs 下午 / 节后效应）
private struct OpenSessionCompareButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("时段对比（⌘⌥T）") { openWindow(id: "sessionCompare") }
            .keyboardShortcut("t", modifiers: [.command, .option])
    }
}

/// v15.54 · WP-行情 异常品种监控入口（⌘⌥A · 5 维度全市场扫描）
private struct OpenAnomalyMonitorButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("异常品种监控（⌘⌥A）") { openWindow(id: "anomalyMonitor") }
            .keyboardShortcut("a", modifiers: [.command, .option])
    }
}

/// v15.55 · WP-套利 价差 alert 入口（⌘⌥W · 26 对全市场偏离扫描）
private struct OpenSpreadAlertButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("价差套利 alert（⌘⌥W）") { openWindow(id: "spreadAlert") }
            .keyboardShortcut("w", modifiers: [.command, .option])
    }
}

/// v17.39 · D3 公式回测入口（⌘⌥K · SimpleBacktestEngine + mock 标的轨迹）
private struct OpenBacktestButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("公式回测（⌘⌥K）") { openWindow(id: "backtest") }
            .keyboardShortcut("k", modifiers: [.command, .option])
    }
}

/// v17.141 · 全工程快捷键速查菜单项（⌘⇧/ · 任何窗口前台触发 · post Notification 让 ShellWindow 弹 sheet）
/// macOS 系统 .help category 默认含 ⌘? · ⌘⇧/ 是它的常见替代键位（与 ChartScene 内 ⌘/ 互补）
private struct OpenGlobalShortcutsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("全局快捷键速查（⌘⇧/）") {
            // 先确保 Shell 在前台（用户可能从子窗口触发） · 再 post 通知让 sheet 弹出
            openWindow(id: "shell")
            NotificationCenter.default.post(name: .openGlobalShortcutsSheet, object: nil)
        }
        .keyboardShortcut("/", modifiers: [.command, .shift])
    }
}

/// v12.18 文华 .wh 公式批量导入（WP-63 commit 4 · 完整真闭环）
/// 工具菜单 → 选 .wh 文件 → WhImporter.importAll → NSAlert 显示编译报告
// v17.169 · CSV K 线导入按钮（工具菜单 · ⌘⇧⌥I 触发）
// v17.176 · v2 闭环：解析后 append 到 storeManager.kline（SQLite K 线缓存）
// v17.202 真修 · 原 @State + .sheet 在 CommandMenu 内 menu Button 不渲染 view tree · sheet 永远不弹
//   改用 openWindow(id: "csvImport") 弹独立 WindowGroup · 同 OpenFormulaEditorButton 模式
private struct OpenCSVImportButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("导入 K 线 CSV...") { openWindow(id: "csvImport") }
            .keyboardShortcut("i", modifiers: [.command, .shift, .option])
    }
}

/// v17.202 · CSV 导入独立窗口 · WindowGroup id "csvImport" 内嵌
/// 包装 KLineCSVImportSheet + 处理 storeManager append + NSAlert 反馈
struct CSVImportWindow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.storeManager) private var storeManager

    var body: some View {
        KLineCSVImportSheet { result, instrumentID, period in
            let store = storeManager
            Task { @MainActor in
                var importedCount = 0
                var saveError: String? = nil
                if let store, !result.bars.isEmpty {
                    do {
                        let tagged: [KLine] = result.bars.map { bar in
                            KLine(
                                instrumentID: instrumentID, period: period,
                                openTime: bar.openTime,
                                open: bar.open, high: bar.high, low: bar.low, close: bar.close,
                                volume: bar.volume,
                                openInterest: bar.openInterest,
                                turnover: bar.turnover
                            )
                        }
                        try await store.kline.append(tagged, instrumentID: instrumentID, period: period, maxBars: 0)
                        importedCount = tagged.count
                    } catch {
                        saveError = "\(error)"
                    }
                } else if store == nil {
                    saveError = "StoreManager 未启动 · 数据停留在内存（重启 App 后丢失）"
                }
                let alert = NSAlert()
                alert.messageText = "CSV 导入完成"
                alert.informativeText = """
                合约 \(instrumentID) · 周期 \(period.rawValue)
                解析 \(result.bars.count) 根 · 跳过 \(result.errors.count) 行
                时间格式 \(result.detectedFormat)
                SQLite 入库 \(importedCount) 根\(saveError.map { " · 失败 \($0)" } ?? "")

                重新打开主图（合约 \(instrumentID) · \(period.displayName)）即可加载。
                """
                if saveError != nil || !result.errors.isEmpty {
                    alert.alertStyle = .warning
                } else {
                    alert.alertStyle = .informational
                }
                alert.runModal()
                dismiss()
            }
        }
    }
}

private struct ImportFormulaButton: View {
    var body: some View {
        Button("导入文华公式（.wh）") { Self.runImport() }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }

    private static func runImport() {
        let panel = NSOpenPanel()
        panel.title = L("导入文华公式")
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = L("导入文华公式")

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let results = WhImporter.importAll(text)
            let success = results.filter { (try? $0.compiled.get()) != nil }.count
            let total = results.count
            let failedDetails = results.compactMap { r -> String? in
                guard case .failure(let err) = r.compiled else { return nil }
                return "  \(r.formula.name)：\(err.localizedDescription)"
            }
            alert.informativeText = """
            从 \(url.lastPathComponent) 导入 \(total) 个公式 · 成功编译 \(success) · 失败 \(total - success)
            \(failedDetails.isEmpty ? "" : "\n失败明细：\n" + failedDetails.prefix(10).joined(separator: "\n"))
            """
            alert.alertStyle = success == total ? .informational : .warning
        } catch {
            alert.informativeText = "导入失败：\(error.localizedDescription)"
            alert.alertStyle = .critical
        }
        alert.addButton(withTitle: L("确定"))
        alert.runModal()
    }
}

#else

@main
struct FuturesTerminalApp {
    static func main() {
        print("⚠️ FuturesTerminal · 仅 macOS（依赖 SwiftUI/AppKit/Metal）· 当前平台跳过")
    }
}

#endif
