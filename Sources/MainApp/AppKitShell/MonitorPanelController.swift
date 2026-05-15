// MainApp · AppKitShell · v17.228 · V1 重构 A2=C Mini v1
//
// Monitor 面板 NSPanel detach · doc 章节 293-309 + A2=C + 验收第 11 条
// 仅 Watchlist / Sector / Position 可拖副屏成 NSPanel
//
// NSPanel 关键设置：
// - styleMask 含 .nonactivatingPanel · 不抢主窗焦点
// - hidesOnDeactivate=false · App 失活时不隐藏
// - isFloatingPanel=true · 浮于主窗之上
// - becomesKeyOnlyIfNeeded=true · 仅交互时才 key window
// - setFrameAutosaveName · 关闭重启位置恢复
//
// Mini v1 简化：仅打开 NSPanel · 不动主窗 monitor 区（A2 C 完整版后续做主窗 monitor 区 detach 后切换）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 monitor 面板类型 · A2=C 决策仅 3 类可 detach
enum MonitorPanelKind: String, CaseIterable {
    case watchlist
    case sector
    case position

    var displayName: String {
        switch self {
        case .watchlist: return "自选合约"
        case .sector:    return "板块联动"
        case .position:  return "多空持仓"
        }
    }
}

/// V1 monitor 面板控制器 · 单例（由 WindowManager 持有）· 管理 3 个 NSPanel 生命周期
@MainActor
final class MonitorPanelController: NSObject, NSWindowDelegate {
    private let env: AppKitShellEnvironment
    private var panels: [MonitorPanelKind: NSPanel] = [:]

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init()
    }

    /// 打开（或激活前台）指定 monitor 面板
    func open(_ kind: MonitorPanelKind) {
        if let existing = panels[kind] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let hostingVC = makeHostingController(for: kind)
        let panel = makePanel(kind: kind, contentVC: hostingVC)
        panels[kind] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// 关闭指定 monitor 面板
    func close(_ kind: MonitorPanelKind) {
        panels[kind]?.close()
        panels[kind] = nil
    }

    private func makeHostingController(for kind: MonitorPanelKind) -> NSViewController {
        switch kind {
        case .watchlist: return AppKitShellHC.wrapAsMonitor(WatchlistWindow(), env: env)
        case .sector:    return AppKitShellHC.wrapAsMonitor(SectorWindow(), env: env)
        case .position:  return AppKitShellHC.wrapAsMonitor(PositionWindow(), env: env)
        }
    }

    private func makePanel(kind: MonitorPanelKind, contentVC: NSViewController) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.displayName
        // v17.231 修 · 去掉 isFloatingPanel · 之前用浮动窗口层级导致切到别的程序也盖不住面板
        // 现在用普通窗口层级 · 切其他程序时面板会被正常覆盖
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrameAutosaveName("monitorPanel.v1.\(kind.rawValue)")
        panel.contentViewController = contentVC
        panel.delegate = self
        return panel
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        // Swift 6 严格模式：notification 不 Sendable · 不能跨 actor 捕获
        // 修法：nonisolated 内先提取 ObjectIdentifier（Sendable struct）· 跨 actor 传 ID
        guard let panel = notification.object as? NSPanel else { return }
        let panelID = ObjectIdentifier(panel)
        Task { @MainActor [weak self] in
            guard let self else { return }
            for (kind, p) in self.panels where ObjectIdentifier(p) == panelID {
                self.panels[kind] = nil
                break
            }
        }
    }
}

#endif
