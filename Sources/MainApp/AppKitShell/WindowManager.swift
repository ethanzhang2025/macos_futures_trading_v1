// MainApp · AppKitShell · v17.209 · V1 重构 Step 1
//
// 窗口生命周期管理器 · doc 章节 500-514 七项职责骨架
// Step 1 仅持 MainWindowController + 空 registry · Step 4-6 接 NSPanel / 重型窗口 / NSPopover
//
// EnvironmentKey 暴露 windowManager 注入到 SwiftUI tree（替代 NotificationCenter 跨窗口通信）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 重构窗口管理器 · 主窗 + 重型窗口 + NSPanel + NSPopover 统一入口
@MainActor
final class WindowManager: ObservableObject {
    private let appState: AppState

    /// 主窗口控制器（A5=B · NSWindow 由 SwiftUI WindowGroup 自动创建 · controller 持 weak ref + 配置）
    let mainWindowController: MainWindowController

    /// 重型独立窗口 registry · Step 6 接入 13 个（option / spread / review / training / ...）
    var heavyWindowRegistry: [String: NSWindow] = [:]

    /// NSPanel registry · Step 4 接入 Inspector / PatternHUD / MultiTimeframeHUD
    var panelRegistry: [String: NSPanel] = [:]

    /// Monitor 面板 detach 列表（A2=C · Watchlist / Sector / Position 可拖副屏成 NSPanel）
    /// Step 4 接入 · Step 1 占位
    var detachedMonitorPanelIDs: [String] = []

    init(appState: AppState) {
        self.appState = appState
        self.mainWindowController = MainWindowController()
    }

    /// 激活主窗口到前台（菜单 ⌘⌃1 触发 · D3 双窗口入口）
    func activateMainWindow() {
        mainWindowController.activate()
    }
}

/// EnvironmentKey · WindowManager 注入到 SwiftUI tree（@Environment(\.windowManager)）
private struct WindowManagerKey: EnvironmentKey {
    static let defaultValue: WindowManager? = nil
}

extension EnvironmentValues {
    var windowManager: WindowManager? {
        get { self[WindowManagerKey.self] }
        set { self[WindowManagerKey.self] = newValue }
    }
}

#endif
