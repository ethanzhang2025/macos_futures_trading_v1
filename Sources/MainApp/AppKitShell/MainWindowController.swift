// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
//
// MainWindow 控制器 · A5=B 决策下 NSWindow 由 SwiftUI WindowGroup 自动创建
// 本类持 weak NSWindow ref + 提供 attach/activate · C2 数值约束在 attach 内注入
// Step 6 后如切全 AppKit 模式可升级为 NSWindowController 子类 own NSWindow

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 主窗口控制器 · weak ref + 配置注入
@MainActor
final class MainWindowController {
    /// SwiftUI WindowGroup 创建的 NSWindow · MainSplitViewBridge.updateNSViewController 内首次拿到时 attach
    weak var window: NSWindow?

    /// 绑定 NSWindow 并注入 V1 标准配置（C2 数值约束）
    func attach(_ window: NSWindow) {
        self.window = window
        window.minSize = NSSize(width: 1200, height: 800)
        window.setFrameAutosaveName("main-workspace.v1")
        window.title = "主工作台 V1（AppKit）"
    }

    /// 激活窗口到前台
    func activate() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#endif
