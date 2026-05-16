// MainApp · AppKitShell · v17.242 · V1 重构 Step 4
//
// Inspector 浮顶面板 · doc 章节 293-309 NSPanel 规则 + Step 4 章节
// V1 主窗 ⌘⌥I 触发 · NSPanel 浮于主窗之上不抢焦点 · 可拖副屏
//
// 设计要点：
// - 单 NSPanel · 复用打开（已开则激活前台）
// - styleMask 含 .nonactivatingPanel · 点 panel 不抢主窗焦点
// - hidesOnDeactivate=false · 程序失活时仍显示
// - 不设 isFloatingPanel（v17.231 教训：跨程序也浮顶不可接受）
// - ShellInspector 通过 onClose closure 回调 panel.close

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit

/// V1 Inspector 浮顶面板控制器 · 单例（WindowManager lazy 持有）
@MainActor
final class InspectorPanelController: NSObject, NSWindowDelegate {
    private let env: AppKitShellEnvironment
    private var panel: NSPanel?

    init(env: AppKitShellEnvironment) {
        self.env = env
        super.init()
    }

    /// 打开（或激活前台）Inspector 面板
    func open() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// 关闭 Inspector 面板
    func close() {
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NSPanel {
        // v17.245 修 · 默认尺寸 320×600 → 420×820（用户反馈太小 · ShellInspector 内 inspectorWidth=280 + padding + 4 段内容）
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 820),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Inspector"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.setFrameAutosaveName("inspectorPanel.v1")
        panel.delegate = self
        // ShellInspector 头部 X 按钮通过 onClose 关闭 panel · NSPanel 系统 X 按钮也可关
        let inspector = ShellInspector(onClose: { [weak self] in self?.close() })
        panel.contentViewController = AppKitShellHC.wrap(inspector, env: env)
        return panel
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.panel = nil
        }
    }
}

#endif
