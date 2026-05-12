// MainApp · Shell · v17.0 PoC Step 2
// 二级 Workspace Tab Bar（Chrome 标签风 · 拍板项 C 推荐）
// 仅显示当前 PrimaryTab 下的 workspace · 可新建 / 关闭 / 重命名

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceTabBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @State private var renamingID: UUID? = nil
    @State private var renamingText: String = ""

    private var visibleWorkspaces: [Workspace] {
        shellVM.workspaces.filter { $0.primaryTab == shellVM.primaryTab }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(visibleWorkspaces.enumerated()), id: \.element.id) { index, ws in
                        workspaceTab(ws, at: index)
                    }
                    newTabButton
                }
                .padding(.horizontal, 8)
            }
            Spacer()
            paneLayoutMenu
                .padding(.trailing, 8)
        }
        .frame(height: ShellMetrics.workspaceTabBarHeight)
        .background(Color.secondary.opacity(0.05))
    }

    /// v17.0 Step 4 · 当前 workspace 的 PaneLayout 切换 Menu（1/2/4/6/9）
    @ViewBuilder
    private var paneLayoutMenu: some View {
        if let ws = shellVM.activeWorkspace {
            Menu {
                ForEach(PaneLayout.allCases.filter { $0 != .custom }) { layout in
                    Button {
                        shellVM.setPaneLayout(layout)
                    } label: {
                        Text("\(ws.paneLayout == layout ? "✓ " : "  ")\(layout.emoji) \(layout.displayName)")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(ws.paneLayout.emoji)
                    Text(ws.paneLayout.displayName)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 100)
            .help("切换 Pane 布局")
        }
    }

    @ViewBuilder
    private func workspaceTab(_ ws: Workspace, at index: Int) -> some View {
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
            Button("复制 Workspace") {
                shellVM.duplicateWorkspace(ws.id)
            }
            // v17.74 · Tab 排序（同 PrimaryTab 内左右移 · 边界禁用）
            Divider()
            let tabIdx = visibleWorkspaces.firstIndex(where: { $0.id == ws.id }) ?? 0
            Button("← 左移") { shellVM.moveWorkspace(ws.id, by: -1) }
                .disabled(tabIdx == 0)
            Button("→ 右移") { shellVM.moveWorkspace(ws.id, by: +1) }
                .disabled(tabIdx >= visibleWorkspaces.count - 1)
            Divider()
            // v17.62 · Workspace 导入 / 导出 JSON（trader 分享布局）
            Button("📤 导出为 JSON…") {
                exportWorkspace(ws)
            }
            Button("📥 从 JSON 导入…") {
                importWorkspace()
            }
            if visibleWorkspaces.count > 1 {
                Divider()
                Button("关闭") {
                    shellVM.closeWorkspace(ws.id)
                }
            }
            Divider()
            Text("Pane 布局：\(ws.paneLayout.emoji) \(ws.paneLayout.displayName) · \(ws.panes.count) Pane")
        }
        // v17.87 · 拖拽排序（升级 v17.74 右键 ← → · 与 WatchlistWindow / WorkspacePreset 同模式）
        .draggable(WorkspaceTabRef(id: ws.id)) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack").font(.system(size: 11))
                Text(ws.name).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.18))
            .cornerRadius(4)
        }
        .dropDestination(for: WorkspaceTabRef.self) { refs, _ in
            guard let ref = refs.first, ref.id != ws.id else { return false }
            shellVM.moveWorkspace(ref.id, toLocalIndex: index)
            return true
        }
    }

    // MARK: - v17.62 · 导入 / 导出（NSSavePanel / NSOpenPanel · macOS 原生）

    private func exportWorkspace(_ ws: Workspace) {
        guard let data = shellVM.exportWorkspace(ws.id) else { return }
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "\(ws.name).workspace.json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.title = "导出 Workspace"
        savePanel.message = "选择保存位置（其他 trader 可通过\"导入\"加载此布局）"
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? data.write(to: url)
        }
    }

    private func importWorkspace() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.title = "导入 Workspace"
        openPanel.message = "选择 .workspace.json 文件（导入后 group 联动自动重置 · 防与现有冲突）"
        if openPanel.runModal() == .OK, let url = openPanel.url,
           let data = try? Data(contentsOf: url) {
            _ = shellVM.importWorkspace(from: data)
        }
    }

    /// v17.67 · + 按钮改为 Menu · 「空白」/「从预设新建...」二选
    private var newTabButton: some View {
        Menu {
            Button("➕ 空白 Workspace") {
                shellVM.newWorkspace()
            }
            .keyboardShortcut("t", modifiers: [.command])
            Divider()
            Section("从预设新建") {
                ForEach(WorkspacePreset.allCases) { preset in
                    Button("\(preset.emoji) \(preset.displayName)") {
                        shellVM.newWorkspace(from: preset)
                    }
                }
                Divider()
                Button("📋 全部预设…") {
                    shellVM.showPresetPickerSheet = true
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("新建 workspace · 空白（⌘T）或从预设")
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

// v17.87 · Transferable 拖拽载荷
private struct WorkspaceTabRef: Codable, Hashable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

#endif
