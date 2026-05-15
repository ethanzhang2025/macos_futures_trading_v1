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
    /// 一行注入 8 个标准 environment（V1 主窗子组件 NSHostingController 跨边界用）
    /// 不注入 isHostedInShell · ChartScene line 385 看 isHostedInShell 决定是否隐藏 toolbar
    /// 仅 monitor split item 内的子组件需要 isHostedInShell=true · 用 AppKitShellHC.wrapAsMonitor
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
