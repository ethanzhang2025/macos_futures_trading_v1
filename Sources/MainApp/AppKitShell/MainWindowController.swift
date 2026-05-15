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

    /// v17.224 · MainSplitViewController 引用 · MainSplitViewBridge.updateNSViewController 时设置
    /// 用于 toggleSidebar / toggleMonitor 菜单 + 快捷键调用（防 collapse 死胡同）
    weak var splitViewController: MainSplitViewController?

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

    /// v17.224 · 切 Sidebar 显隐（菜单「视图 → 显示/隐藏 Sidebar」+ ⌘⌃[）
    func toggleSidebar() {
        guard let split = splitViewController,
              split.splitViewItems.indices.contains(0) else { return }
        split.splitViewItems[0].animator().isCollapsed.toggle()
    }

    /// v17.224 · 切 Monitor 显隐（菜单「视图 → 显示/隐藏 Watchlist」+ ⌘⌃]）
    func toggleMonitor() {
        guard let split = splitViewController,
              split.splitViewItems.indices.contains(2) else { return }
        split.splitViewItems[2].animator().isCollapsed.toggle()
    }
}

#endif
