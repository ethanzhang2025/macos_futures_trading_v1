// MainApp · Shell · v17.0 PoC Step 8 + v17.57 F 键体系
// Shell 全局快捷键 · ⌘ 体系（v17.0）+ F 键文华兼容（v17.57）
// 用 invisible Button + keyboardShortcut（与训练 sheet 同模式）
//
// F 键映射（v17.0 设计 §6.2）：
//   F6  → 跳焦自选 sidebar
//   F8  → 当前 Pane 周期循环（同 group 联动）
//   F10 → 合约资料 sheet
//   F12 → 画线工具 hint（实际工具在 Pane toolbar）
//   空格 → 模拟下单浮层（Stage A 占位）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellKeyboardShortcuts: View {
    @EnvironmentObject var shellVM: ShellViewModel

    // v17.190 · Mac 6.3 严格 · 拆 4 个 inner Group 防 ViewBuilder buildBlock10 generic 推断超时
    var body: some View {
        Group {
            primaryShortcuts
            workspaceMgmtShortcuts
            workspaceTabShortcuts
            functionKeyShortcuts
        }
    }

    @ViewBuilder
    private var primaryShortcuts: some View {
        // ⌘+K 全局命令面板（v17.2）
        Button("") { shellVM.showCommandPalette = true }
            .keyboardShortcut("k", modifiers: [.command])
            .opacity(0)
        // ⌘+1..5 切一级模块
        primaryTabShortcut(.watching,  key: "1")
        primaryTabShortcut(.arbitrage, key: "2")
        primaryTabShortcut(.option,    key: "3")
        primaryTabShortcut(.review,    key: "4")
        primaryTabShortcut(.training,  key: "5")
    }

    @ViewBuilder
    private var workspaceMgmtShortcuts: some View {
        // ⌘+T 新建 workspace
        Button("") { shellVM.newWorkspace() }
            .keyboardShortcut("t", modifiers: [.command])
            .opacity(0)
        // ⌘+W 关闭当前 workspace（仅 active 存在 + 不止 1 个时）
        Button("") {
            if let id = shellVM.activeWorkspaceID,
               shellVM.workspaces.filter({ $0.primaryTab == shellVM.primaryTab }).count > 1 {
                shellVM.closeWorkspace(id)
            }
        }
        .keyboardShortcut("w", modifiers: [.command])
        .opacity(0)
        // ⌘+B 切 sidebar 折叠
        Button("") { shellVM.layout.sidebarCollapsed.toggle() }
            .keyboardShortcut("b", modifiers: [.command])
            .opacity(0)
        // ⌘+Shift+B 切 底部交易区折叠
        Button("") { shellVM.layout.bottomBarCollapsed.toggle() }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .opacity(0)
        // v17.61 · ⌘⌥I 切 右辅助 Inspector 显隐
        Button("") { shellVM.layout.inspectorVisible.toggle() }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .opacity(0)
        // v17.5 · Esc 退出 Pane 最大化（文华 Esc 风格）
        Button("") { shellVM.exitMaximize() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .disabled(shellVM.maximizedPaneID == nil)
    }

    @ViewBuilder
    private var workspaceTabShortcuts: some View {
        // ⌘+⌥+1..9 跳到第 N 个二级 Workspace
        workspaceShortcut(idx: 0, key: "1")
        workspaceShortcut(idx: 1, key: "2")
        workspaceShortcut(idx: 2, key: "3")
        workspaceShortcut(idx: 3, key: "4")
        workspaceShortcut(idx: 4, key: "5")
        workspaceShortcut(idx: 5, key: "6")
        workspaceShortcut(idx: 6, key: "7")
        workspaceShortcut(idx: 7, key: "8")
        workspaceShortcut(idx: 8, key: "9")
    }

    @ViewBuilder
    private var functionKeyShortcuts: some View {
        // v17.57 · F 键体系（文华 trader 兼容 · v17.0 P0.4）
        Button("") { shellVM.focusSidebar() }
            .keyboardShortcut(.f6, modifiers: [])
            .opacity(0)
        Button("") { shellVM.cyclePeriodOnActivePane() }
            .keyboardShortcut(.f8, modifiers: [])
            .opacity(0)
        Button("") { shellVM.openInstrumentInfo() }
            .keyboardShortcut(.f10, modifiers: [])
            .opacity(0)
        Button("") { shellVM.hintDrawingTool() }
            .keyboardShortcut(.f12, modifiers: [])
            .opacity(0)
        // 空格唤起下单浮层（v17.57 占位 · Stage A 不接 CTP）
        Button("") { shellVM.openQuickOrder() }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
    }

    @ViewBuilder
    private func primaryTabShortcut(_ tab: PrimaryTab, key: Character) -> some View {
        Button("") {
            if shellVM.primaryTab != tab {
                shellVM.primaryTab = tab
                shellVM.activateFirstWorkspaceOfPrimaryTab()
            }
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.command])
        .opacity(0)
    }

    @ViewBuilder
    private func workspaceShortcut(idx: Int, key: Character) -> some View {
        Button("") {
            let visible = shellVM.workspaces.filter { $0.primaryTab == shellVM.primaryTab }
            if idx < visible.count {
                shellVM.activate(visible[idx].id)
            }
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option])
        .opacity(0)
    }
}

#endif
