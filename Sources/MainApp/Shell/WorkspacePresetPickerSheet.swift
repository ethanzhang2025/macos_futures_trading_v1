// MainApp · Shell · v17.67 · Workspace 预设选择 sheet
// 入口：WorkspaceTabBar + Menu「从预设新建...」/ ⌘K 命令面板「新建 workspace · 预设」
// 选中后 shellVM.newWorkspace(from: preset) · sheet 自动 dismiss

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct WorkspacePresetPickerSheet: View {

    @Binding var isPresented: Bool
    @EnvironmentObject var shellVM: ShellViewModel

    private let cardColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: cardColumns, spacing: 12) {
                    ForEach(WorkspacePreset.allCases) { preset in
                        presetCard(preset)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 580)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("从预设新建 Workspace")
                .font(.title3.bold())
            Text("trader 实战常用布局 · 一键应用 · 创建后可继续调整 Pane / symbol / period")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func presetCard(_ preset: WorkspacePreset) -> some View {
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("取消") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#endif
