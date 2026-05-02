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

    init() {
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
        // 之前 dispatcher 创建空 channels · 用户预警仅 console log 不实用
        self.alertEvaluator = manager.map {
            #if canImport(AppKit) && os(macOS)
            let dispatcher = NotificationDispatcher(channels: [
                InAppOverlayChannel(),
                SystemNoticeChannel(),
                SoundChannel()
            ])
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
        if let service = self.analytics {
            Task { _ = try? await service.record(.appLaunch, userID: Self.anonymousUserID) }
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

    /// v1 占位 · 无登录态 · 接 Apple ID / 用户系统后替换
    static let anonymousUserID = "anonymous"

    /// v1 硬编码 · M6 打包后改为读 Bundle Info.plist CFBundleShortVersionString
    static let bundleAppVersion = "0.0.1"

    var body: some Scene {
        // 主图表窗口（默认启动 + Cmd+N 新建多个 · 每窗口独立 renderer / viewport）
        // v15.17 · 移除全局 .preferredColorScheme(.dark) · ChartScene 内动态 chartTheme.colorScheme · sheet/popup 跟主题
        WindowGroup("K 线图表", id: "chart") {
            ChartScene()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
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
            }
            CommandMenu("视图") {
                Text("周期切换：⌘1=1分 / ⌘2=5分 / ⌘3=15分 / ⌘4=30分 / ⌘5=60分 / ⌘6=日（K 线窗口聚焦时生效）")
                    .foregroundColor(.secondary)
            }
            CommandMenu("工具") {
                ImportFormulaButton()
            }
        }

        // 自选合约窗口（菜单触发打开 · 单实例 · WP-43 UI · M5 接 SQLiteWatchlistBookStore）
        WindowGroup("自选合约", id: "watchlist") {
            WatchlistWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 880, height: 600)

        // 复盘工作台（⌘R · 8 图独立窗口 · 与 K 线主图区分离）
        WindowGroup("复盘", id: "review") {
            ReviewWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 900)

        // 预警面板（⌘B · Bell · 独立窗口）
        WindowGroup("预警", id: "alert") {
            AlertWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 920, height: 640)

        // 交易日志（⌘J · Journal · 独立窗口 · WP-53 UI · M5 接 SQLiteJournalStore）
        WindowGroup("交易日志", id: "journal") {
            JournalWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 720)

        // 工作区模板（⌘K · workspace · 独立窗口 · WP-55 UI · M5 接 SQLiteWorkspaceBookStore）
        WindowGroup("工作区模板", id: "workspace") {
            WorkspaceWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 720)

        // 模拟交易（⌘T · trading · 独立窗口 · WP-54 v15.4 SimNow 模拟训练）
        WindowGroup("模拟交易", id: "trading") {
            TradingWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.simulatedTradingEngine, simulatedTradingEngine)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 720)

        // 偏好设置（Cmd+, 自动绑定 · macOS 标准）
        Settings {
            SettingsContentView()
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

private struct OpenTradingButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("模拟交易") { openWindow(id: "trading") }
            .keyboardShortcut("t", modifiers: [.command])
    }
}

/// v12.18 文华 .wh 公式批量导入（WP-63 commit 4 · 完整真闭环）
/// 工具菜单 → 选 .wh 文件 → WhImporter.importAll → NSAlert 显示编译报告
private struct ImportFormulaButton: View {
    var body: some View {
        Button("导入文华公式（.wh）") { Self.runImport() }
            .keyboardShortcut("i", modifiers: [.command, .shift])
    }

    private static func runImport() {
        let panel = NSOpenPanel()
        panel.title = "导入文华公式"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "导入文华公式"

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
        alert.addButton(withTitle: "确定")
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
