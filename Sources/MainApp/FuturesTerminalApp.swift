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
        self.alertEvaluator = manager.map {
            AlertEvaluator(history: $0.alertHistory, dispatcher: NotificationDispatcher())
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
        WindowGroup("K 线图表", id: "chart") {
            ChartScene()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewChartButton()
                Divider()
                OpenWatchlistButton()
                OpenReviewButton()
                OpenAlertButton()
                OpenJournalButton()
                OpenWorkspaceButton()
            }
            CommandMenu("视图") {
                Text("（多周期切换已支持工具条 Picker · 键盘 ⌘1~9 待 Mac 切机集中接）")
                    .foregroundColor(.secondary)
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

        // 复盘工作台（⌘R · 8 图独立窗口 · 与 K 线主图区分离）
        WindowGroup("复盘", id: "review") {
            ReviewWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }

        // 预警面板（⌘B · Bell · 独立窗口）
        WindowGroup("预警", id: "alert") {
            AlertWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }

        // 交易日志（⌘J · Journal · 独立窗口 · WP-53 UI · M5 接 SQLiteJournalStore）
        WindowGroup("交易日志", id: "journal") {
            JournalWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }

        // 工作区模板（⌘K · workspace · 独立窗口 · WP-55 UI · M5 接 SQLiteWorkspaceBookStore）
        WindowGroup("工作区模板", id: "workspace") {
            WorkspaceWindow()
                .environment(\.storeManager, storeManager)
                .environment(\.analytics, analytics)
                .environment(\.alertEvaluator, alertEvaluator)
                .preferredColorScheme(.dark)
        }

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

#else

@main
struct FuturesTerminalApp {
    static func main() {
        print("⚠️ FuturesTerminal · 仅 macOS（依赖 SwiftUI/AppKit/Metal）· 当前平台跳过")
    }
}

#endif
