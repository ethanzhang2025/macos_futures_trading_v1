// MainApp · Shell · v17.67 · Workspace 预设选择 sheet
// 入口：WorkspaceTabBar + Menu「从预设新建...」/ ⌘K 命令面板「新建 workspace · 预设」
// v17.81 · 加用户自定义预设 section（💾 保存当前为预设 + 我的预设卡片含删除）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspacePresetPickerSheet: View {

    @Binding var isPresented: Bool
    @EnvironmentObject var shellVM: ShellViewModel

    @State private var showSaveSheet: Bool = false
    @State private var newPresetName: String = ""
    @State private var newPresetEmoji: String = "🎯"

    /// v17.85 · 重命名 sheet 状态（双击 userCard 触发）
    @State private var renamingPresetID: UUID?
    @State private var renameName: String = ""
    @State private var renameEmoji: String = "🎯"

    private let cardColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private let emojiChoices: [String] = ["🎯", "📊", "📈", "🌃", "💼", "🧮", "🔥", "⭐", "🪪", "🧭", "💱", "📋"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    builtinSection
                    if !shellVM.userPresets.isEmpty {
                        userSection
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 620)
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
        .sheet(isPresented: Binding(
            get: { renamingPresetID != nil },
            set: { if !$0 { renamingPresetID = nil } }
        )) {
            renameSheet
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("从预设新建 Workspace")
                    .font(.title3.bold())
                Text("内置 \(WorkspacePreset.allCases.count) + 自定义 \(shellVM.userPresets.count) · 一键应用 · 创建后可继续调整")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                newPresetName = shellVM.activeWorkspace?.name ?? ""
                newPresetEmoji = "🎯"
                showSaveSheet = true
            } label: {
                Label("保存当前为预设", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .disabled(shellVM.activeWorkspace == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var builtinSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("内置预设")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(WorkspacePreset.allCases) { preset in
                    builtinCard(preset)
                }
            }
        }
    }

    private var userSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("我的预设（\(shellVM.userPresets.count)）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("· 拖拽排序 · 双击重命名")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(Array(shellVM.userPresets.enumerated()), id: \.element.id) { index, preset in
                    userCard(preset, at: index)
                }
            }
        }
    }

    private func builtinCard(_ preset: WorkspacePreset) -> some View {
        Button {
            shellVM.newWorkspace(from: preset)
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(preset.emoji).font(.system(size: 18))
                    Text(preset.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(preset.paneLayout.emoji) \(preset.panes().count) 格")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Text(preset.recommendedPrimaryTab.emoji)
                        .font(.system(size: 11))
                    Text(preset.recommendedPrimaryTab.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(Color.secondary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func userCard(_ preset: UserWorkspacePreset, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                shellVM.newWorkspace(from: preset)
                isPresented = false
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(preset.emoji).font(.system(size: 18))
                        Text(preset.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(preset.paneLayout.emoji) \(preset.panes.count) 格")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(preset.primaryTab.emoji)
                            .font(.system(size: 11))
                        Text(preset.primaryTab.displayName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                .background(Color.purple.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Button {
                shellVM.deleteUserPreset(preset.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("删除此预设（不可撤销）")
        }
        // v17.85 · 双击 → 重命名 sheet
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            renamingPresetID = preset.id
            renameName = preset.name
            renameEmoji = preset.emoji
        })
        // v17.85 · 拖拽排序（macOS 13+ Transferable · 与 WatchlistWindow 同模式）
        .draggable(UserPresetRef(id: preset.id)) {
            HStack(spacing: 4) {
                Text(preset.emoji).font(.system(size: 14))
                Text(preset.name).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.purple.opacity(0.18))
            .cornerRadius(4)
        }
        .dropDestination(for: UserPresetRef.self) { refs, _ in
            guard let ref = refs.first, ref.id != preset.id else { return false }
            shellVM.moveUserPreset(ref.id, to: index)
            return true
        }
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("保存当前 Workspace 为预设").font(.headline)
            if let ws = shellVM.activeWorkspace {
                Text("源 Workspace：\(ws.name) · \(ws.paneLayout.displayName) · \(ws.panes.count) Pane")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Text("名称").frame(width: 50, alignment: .leading)
                TextField("例：今日早盘", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Emoji").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(emojiChoices, id: \.self) { e in
                        Button(e) { newPresetEmoji = e }
                            .buttonStyle(.plain)
                            .font(.system(size: 18))
                            .frame(width: 30, height: 30)
                            .background(newPresetEmoji == e ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if shellVM.saveActiveWorkspaceAsUserPreset(name: newPresetName, emoji: newPresetEmoji) != nil {
                        showSaveSheet = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var footer: some View {
        HStack {
            // v17.137 · 导出/导入用户预设（备份 / 分享 / 跨机迁移）
            Button {
                exportUserPresets()
            } label: {
                Label("导出全部 (\(shellVM.userPresets.count))", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .disabled(shellVM.userPresets.isEmpty)
            .tooltip("导出全部用户预设为 .json 文件 · 备份 / 分享 / 跨机器迁移")

            Button {
                importUserPresets()
            } label: {
                Label("导入...", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .tooltip("从 .json 文件导入用户预设 · 默认追加 · 可选全量替换")

            Spacer()
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - v17.137 · 导出 / 导入 用户预设

    private func exportUserPresets() {
        guard let data = shellVM.exportUserPresets() else {
            Toast.warn("导出失败", "无法序列化预设")
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出用户 Workspace 预设"
        panel.allowedContentTypes = [.json]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "workspace_presets_\(fmt.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            Toast.info("已导出", "\(shellVM.userPresets.count) 个预设 → \(url.lastPathComponent)")
        } catch {
            Toast.warn("导出失败", error.localizedDescription)
        }
    }

    private func importUserPresets() {
        let panel = NSOpenPanel()
        panel.title = "导入用户 Workspace 预设"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        // 已有预设时询问追加 / 替换 · 取消则中止
        guard let mode = chooseImportMode(currentCount: shellVM.userPresets.count) else { return }
        do {
            let result = try shellVM.importUserPresets(data: data, mode: mode)
            Toast.info(
                mode == .replaceAll ? "已替换为导入数据" : "已追加导入",
                "导入 \(result.importedCount) 个 · 当前共 \(result.totalAfterImport) 个"
            )
        } catch WorkspacePresetImportError.fileEmpty {
            Toast.warn("导入失败", "文件为空")
        } catch WorkspacePresetImportError.invalidJSON(let msg) {
            Toast.warn("导入失败", "JSON 格式不识别：\(msg)")
        } catch WorkspacePresetImportError.unsupportedSchemaVersion(let v) {
            Toast.warn("导入失败", "版本不支持（文件 v\(v) · 本机支持 ≤ v\(UserWorkspacePresetTransfer.currentSchemaVersion) · 升级应用后重试）")
        } catch {
            Toast.warn("导入失败", error.localizedDescription)
        }
    }

    /// 已有预设时弹 NSAlert 让用户选 append / replaceAll · 无预设直接 replaceAll（语义一致）· 取消返回 nil
    private func chooseImportMode(currentCount: Int) -> WorkspacePresetImportMode? {
        guard currentCount > 0 else { return .replaceAll }
        let alert = NSAlert()
        alert.messageText = "如何导入？"
        alert.informativeText = "当前已有 \(currentCount) 个用户预设。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "追加到现有")
        alert.addButton(withTitle: "全量替换")
        alert.addButton(withTitle: "取消")
        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:  return .append
        case .alertSecondButtonReturn: return .replaceAll
        default:                        return nil   // 取消
        }
    }

    // v17.85 · 重命名 sheet（双击 userCard 触发）
    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名预设").font(.headline)
            HStack {
                Text("名称").frame(width: 50, alignment: .leading)
                TextField("例：早盘多周期", text: $renameName)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Emoji").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(emojiChoices, id: \.self) { e in
                        Button(e) { renameEmoji = e }
                            .buttonStyle(.plain)
                            .font(.system(size: 18))
                            .frame(width: 30, height: 30)
                            .background(renameEmoji == e ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { renamingPresetID = nil }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if let id = renamingPresetID {
                        shellVM.renameUserPreset(id, to: renameName, emoji: renameEmoji)
                    }
                    renamingPresetID = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// v17.85 · Transferable 拖拽载荷
private struct UserPresetRef: Codable, Hashable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

#endif
