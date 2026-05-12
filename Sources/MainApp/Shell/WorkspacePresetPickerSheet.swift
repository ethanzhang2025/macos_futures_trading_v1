// MainApp · Shell · v17.67 · Workspace 预设选择 sheet
// 入口：WorkspaceTabBar + Menu「从预设新建...」/ ⌘K 命令面板「新建 workspace · 预设」
// v17.81 · 加用户自定义预设 section（💾 保存当前为预设 + 我的预设卡片含删除）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct WorkspacePresetPickerSheet: View {

    @Binding var isPresented: Bool
    @EnvironmentObject var shellVM: ShellViewModel

    @State private var showSaveSheet: Bool = false
    @State private var newPresetName: String = ""
    @State private var newPresetEmoji: String = "🎯"

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
            Text("我的预设（\(shellVM.userPresets.count)）")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            LazyVGrid(columns: cardColumns, spacing: 12) {
                ForEach(shellVM.userPresets) { preset in
                    userCard(preset)
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

    private func userCard(_ preset: UserWorkspacePreset) -> some View {
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
            Spacer()
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#endif
