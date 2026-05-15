// MainApp · AppKitShell · v17.209 · V1 重构 Step 2c
//
// Environment 注入 helper · doc C1 章节
// NSHostingController 跨边界 SwiftUI environment 丢失 · 需手动重注入
// spike 验证：每 NSHostingController 需注入 6 个旧 environment + V1 新加 2 个
//
// 用法：
//   let env = AppKitShellEnvironment(shellVM:..., storeManager:..., ..., appState:..., windowManager:...)
//   let sidebarVC = AppKitShellHC.wrap(ShellSidebar(), env: env)
//   let item = NSSplitViewItem(viewController: sidebarVC)

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Shared
import StoreCore
import TradingCore
import AlertCore

/// V1 主窗共享 environment 容器 · 一次构造多处复用
@MainActor
struct AppKitShellEnvironment {
    let shellVM: ShellViewModel
    let storeManager: StoreManager?
    let analytics: AnalyticsService?
    let alertEvaluator: AlertEvaluator?
    let simulatedTradingEngine: SimulatedTradingEngine?
    let bannerService: BannerService?
    let appState: AppState
    let windowManager: WindowManager
}

extension View {
    /// 一行注入 9 个 environment（V1 主窗子组件 NSHostingController 跨边界用）
    /// 不注入 isHostedInShell · ChartScene line 385 看 isHostedInShell 决定是否隐藏 toolbar
    /// 仅 monitor split item 内的子组件需要 isHostedInShell=true · 用 AppKitShellHC.wrapAsMonitor
    /// v17.223 · 注入 isInV1MainWindow=true · 让子组件知道在 V1 主窗内
    /// ChartScene 据此把 minWidth/minHeight 缩到 0 · 不撑大 NSHostingController.view 覆盖 NSSplitView divider
    func injectAppKitShellEnv(_ env: AppKitShellEnvironment) -> some View {
        self
            .environmentObject(env.shellVM)
            .environmentObject(env.appState)
            .environment(\.storeManager, env.storeManager)
            .environment(\.analytics, env.analytics)
            .environment(\.alertEvaluator, env.alertEvaluator)
            .environment(\.simulatedTradingEngine, env.simulatedTradingEngine)
            .environment(\.bannerService, env.bannerService)
            .environment(\.windowManager, env.windowManager)
            .environment(\.isInV1MainWindow, true)
    }
}

/// EnvironmentKey · V1 主窗内嵌标识（区别于 isHostedInShell · 仅监盘面板用）
/// 让 ChartScene / 其它子组件知道在 V1 NSSplitView 内 · 缩 minWidth/minHeight=0
/// 防止 SwiftUI rootView ideal size 撑大 NSHostingController.view 覆盖 divider hit test
private struct IsInV1MainWindowKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isInV1MainWindow: Bool {
        get { self[IsInV1MainWindowKey.self] }
        set { self[IsInV1MainWindowKey.self] = newValue }
    }
}

/// NSHostingController 工厂 · 注入 env 后返回 NSViewController（NSSplitViewItem 接口需要）
@MainActor
enum AppKitShellHC {
    /// 包 SwiftUI View 成 NSHostingController · 自动注入 V1 标准 8 个 environment
    /// 用于 Sidebar / ChartScene 等不需要 isHostedInShell 的子组件
    static func wrap<V: View>(_ view: V, env: AppKitShellEnvironment) -> NSViewController {
        NSHostingController(rootView: view.injectAppKitShellEnv(env))
    }

    /// V1 主窗 monitor split item 专用 wrap · 额外注入 isHostedInShell=true
    /// 让 WatchlistWindow / SectorWindow / PositionWindow 切到嵌入模式（单栏 / 缩 minSize=0）
    /// doc D2 章节 · isHostedInShell 在 V1 实际语义是 isInMonitorPanel · 保留名字避免改 30+ 调用点
    static func wrapAsMonitor<V: View>(_ view: V, env: AppKitShellEnvironment) -> NSViewController {
        NSHostingController(rootView:
            view
                .injectAppKitShellEnv(env)
                .environment(\.isHostedInShell, true)
        )
    }
}

#endif
