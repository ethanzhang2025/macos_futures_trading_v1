// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
//
// SwiftUI WindowGroup → NSSplitViewController 桥接（A5=B 决策）
// doc 章节 730-775 · MainSplitViewBridge 是 NSViewControllerRepresentable
// updateNSViewController 内拿到 NSWindow 后调 windowManager.mainWindowController.attach

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗根视图 · WindowGroup("主工作台", id: "main") 内嵌
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    let windowManager: WindowManager

    var body: some View {
        MainSplitViewBridge(windowManager: windowManager)
            .environmentObject(appState)
    }
}

/// NSViewControllerRepresentable 桥接 NSSplitViewController 进 SwiftUI
struct MainSplitViewBridge: NSViewControllerRepresentable {
    @EnvironmentObject var appState: AppState
    let windowManager: WindowManager

    func makeNSViewController(context: Context) -> MainSplitViewController {
        MainSplitViewController()
    }

    func updateNSViewController(_ nsViewController: MainSplitViewController, context: Context) {
        // viewDidLoad 时 view.window 尚未挂入 hierarchy · update 阶段才能拿到 NSWindow ref
        // 仅首次 attach（避免重复 setFrameAutosaveName 抢占同名 autosave）
        if let window = nsViewController.view.window,
           window !== windowManager.mainWindowController.window {
            windowManager.mainWindowController.attach(window)
        }
    }
}

#endif
