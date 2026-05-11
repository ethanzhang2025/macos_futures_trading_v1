// MainApp · Shell · v17.0 PoC Step 2
// 二级 Workspace Tab Bar（Chrome 标签风 · 拍板项 C 推荐）
// 仅显示当前 PrimaryTab 下的 workspace · 可新建 / 关闭 / 重命名

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct WorkspaceTabBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @State private var renamingID: UUID? = nil
    @State private var renamingText: String = ""

    private var visibleWorkspaces: [Workspace] {
        shellVM.workspaces.filter { $0.primaryTab == shellVM.primaryTab }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(visibleWorkspaces) { ws in
                    workspaceTab(ws)
                }
                newTabButton
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: ShellMetrics.workspaceTabBarHeight)
        .background(Color.secondary.opacity(0.05))
    }

    @ViewBuilder
    private func workspaceTab(_ ws: Workspace) -> some View {
        let isActive = (shellVM.activeWorkspaceID == ws.id)
        HStack(spacing: 4) {
            if renamingID == ws.id {
                TextField("名称", text: $renamingText, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 60, maxWidth: 120)
                    .onExitCommand { renamingID = nil }
            } else {
                Text(ws.name)
                    .font(.system(size: 12,
                                  weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                if visibleWorkspaces.count > 1 {
                    Button {
                        shellVM.closeWorkspace(ws.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭此 workspace")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive
                    ? Color(NSColor.windowBackgroundColor)
                    : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.clear,
                              lineWidth: 1)
        )
        .onTapGesture {
            if !isActive {
                shellVM.activate(ws.id)
            }
        }
        .onTapGesture(count: 2) {
            renamingID = ws.id
            renamingText = ws.name
        }
        .contextMenu {
            Button("重命名") {
                renamingID = ws.id
                renamingText = ws.name
            }
            if visibleWorkspaces.count > 1 {
                Button("关闭") {
                    shellVM.closeWorkspace(ws.id)
                }
            }
            Divider()
            Text("Pane 布局：\(ws.paneLayout.emoji) \(ws.paneLayout.displayName) · \(ws.panes.count) Pane")
        }
    }

    private var newTabButton: some View {
        Button {
            shellVM.newWorkspace()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("新建 workspace（⌘T）")
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            shellVM.renameWorkspace(id, to: trimmed)
        }
        renamingID = nil
    }
}

#endif
