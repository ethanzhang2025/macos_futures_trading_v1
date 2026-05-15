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

    /// v17.228 · A2=C Mini v1 · Monitor 面板 NSPanel detach controller（lazy · 首次 open 才创建）
    /// env 跨循环依赖 callsite 传入 · doc 章节 293-309
    private var monitorPanelController: MonitorPanelController?

    init(appState: AppState) {
        self.appState = appState
        self.mainWindowController = MainWindowController()
    }

    /// 激活主窗口到前台（菜单 ⌘⌃1 触发 · D3 双窗口入口）
    func activateMainWindow() {
        mainWindowController.activate()
    }

    /// v17.228 · 打开 Monitor 面板 NSPanel · 已开则激活前台
    func openMonitorPanel(_ kind: MonitorPanelKind, env: AppKitShellEnvironment) {
        if monitorPanelController == nil {
            monitorPanelController = MonitorPanelController(env: env)
        }
        monitorPanelController?.open(kind)
    }

    /// v17.228 · 关闭 Monitor 面板 NSPanel
    func closeMonitorPanel(_ kind: MonitorPanelKind) {
        monitorPanelController?.close(kind)
    }

    /// v17.229 · Step 6 · 重型独立窗口统一路由 · doc 章节 237-254（13 类重型窗口）
    /// 当前实现走 SwiftUI openWindow · 后续可平滑切到 WindowManager 直接管 NSWindow 创建
    func openHeavyWindow(_ kind: HeavyWindowKind, using openWindow: OpenWindowAction) {
        openWindow(id: kind.windowID)
    }
}

/// v17.229 · Step 6 · 13 类重型独立窗口集中标识 · doc 章节 237-254
enum HeavyWindowKind: String, CaseIterable {
    case option
    case spread
    case calendarSpread
    case spreadAlert
    case review
    case journal
    case training
    case formulaEditor
    case anomalyMonitor
    case instrumentDashboard
    case sessionCompare
    case correlation
    case moneyflow

    var windowID: String { rawValue }
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
