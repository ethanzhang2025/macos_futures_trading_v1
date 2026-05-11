// MainApp · Shell · v17.0 PoC Step 8
// Shell 全局快捷键 · ⌘ 体系（v17.0）+ F 键（v17.1 加）
// 用 invisible Button + keyboardShortcut（与训练 sheet 同模式）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellKeyboardShortcuts: View {
    @EnvironmentObject var shellVM: ShellViewModel

    var body: some View {
        Group {
            // ⌘+1..5 切一级模块
            primaryTabShortcut(.watching,  key: "1")
            primaryTabShortcut(.arbitrage, key: "2")
            primaryTabShortcut(.option,    key: "3")
            primaryTabShortcut(.review,    key: "4")
            primaryTabShortcut(.training,  key: "5")

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
            Button("") {
                shellVM.layout.sidebarCollapsed.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .opacity(0)

            // ⌘+Shift+B 切 底部交易区折叠
            Button("") {
                shellVM.layout.bottomBarCollapsed.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .opacity(0)

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
