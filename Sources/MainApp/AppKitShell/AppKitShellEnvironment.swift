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
    /// v17.214 · isHostedInShell=true 让 WatchlistWindow / OptionWindow / SpreadWindow 等
    /// 切到嵌入模式（缩 minWidth/minHeight 到 0 · 单栏布局 · 不抢父容器空间）· doc D2 章节
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
            .environment(\.isHostedInShell, true)
    }
}

/// NSHostingController 工厂 · 注入 env 后返回 NSViewController（NSSplitViewItem 接口需要）
@MainActor
enum AppKitShellHC {
    /// 包 SwiftUI View 成 NSHostingController · 自动注入 V1 标准 environment
    static func wrap<V: View>(_ view: V, env: AppKitShellEnvironment) -> NSViewController {
        NSHostingController(rootView: view.injectAppKitShellEnv(env))
    }
}

#endif
