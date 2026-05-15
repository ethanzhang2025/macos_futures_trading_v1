// MainApp · AppKitShell · v17.209 · V1 重构 Step 2
//
// SwiftUI WindowGroup → NSSplitViewController 桥接（A5=B 决策）
// doc 章节 730-775 · MainSplitViewBridge 是 NSViewControllerRepresentable
// updateNSViewController 内拿到 NSWindow 后调 windowManager.mainWindowController.attach

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗根视图 · WindowGroup("主工作台", id: "mainV1") 内嵌
/// Step 2b · VStack 包顶 PrimaryTabBar / 中 MainSplitViewBridge / 底 BottomTradingBar + ShellStatusBar
struct MainWindowView: View {
    let env: AppKitShellEnvironment

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 · PrimaryTabBar（doc 章节 184-231）
            // Step 2b 直接 SwiftUI 渲染 · 不需要 NSHostingController 包（A5=B WindowGroup 内 SwiftUI 已是 native）
            PrimaryTabBar()

            Divider()

            // 中部 · 3 列 NSSplitViewController（Sidebar / PaneContainer / Monitor）
            MainSplitViewBridge(env: env)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 底部 · BottomTradingBar（5 tab 常驻 · 持仓/委托/成交/资金/训练规则）
            BottomTradingBar()

            Divider()

            // 底部 · ShellStatusBar（连接状态 + 时间 + 风险度 + 训练 streak）
            ShellStatusBar()
        }
        .injectAppKitShellEnv(env)
    }
}

/// NSViewControllerRepresentable 桥接 NSSplitViewController 进 SwiftUI
struct MainSplitViewBridge: NSViewControllerRepresentable {
    let env: AppKitShellEnvironment

    func makeNSViewController(context: Context) -> MainSplitViewController {
        MainSplitViewController(env: env)
    }

    func updateNSViewController(_ nsViewController: MainSplitViewController, context: Context) {
        // viewDidLoad 时 view.window 尚未挂入 hierarchy · update 阶段才能拿到 NSWindow ref
        // 仅首次 attach（避免重复 setFrameAutosaveName 抢占同名 autosave）
        if let window = nsViewController.view.window,
           window !== env.windowManager.mainWindowController.window {
            env.windowManager.mainWindowController.attach(window)
        }
    }
}

#endif
