// MainApp · Shell · v17.64 · Sidebar layout 配置 sheet
//
// 用户调整 5 section 顺序 + 显隐 · 应用即时生效（@AppStorage / UserDefaults 双向）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellSidebarLayoutSheet: View {

    @Binding var isPresented: Bool
    @State private var settings: SidebarLayoutSettings = SidebarLayoutStore.load()
    let onApply: (SidebarLayoutSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📋 Sidebar 自定义")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Text("拖拽不可用 · 用 ↑↓ 调整顺序 · ☑ 控制显隐")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Divider()

            // section 列表 · 按当前 order 渲染
            VStack(spacing: 4) {
                ForEach(Array(settings.order.enumerated()), id: \.element) { (idx, sec) in
                    sectionRow(sec, idx: idx)
                }
            }

            Divider()

            HStack {
                Button("恢复默认") {
                    settings = .default
                }
                Spacer()
                Button("取消") { isPresented = false }
                Button("应用并保存") {
                    SidebarLayoutStore.save(settings)
                    onApply(settings)
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
    }

    @ViewBuilder
    private func sectionRow(_ sec: SidebarSection, idx: Int) -> some View {
        HStack(spacing: 10) {
            Text(sec.emoji).font(.system(size: 13))
            Text(sec.displayName)
                .font(.system(size: 13))
                .frame(width: 70, alignment: .leading)
                .foregroundColor(settings.hidden.contains(sec) ? .secondary : .primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { !settings.hidden.contains(sec) },
                set: { newVal in
                    if newVal { settings.hidden.remove(sec) }
                    else { settings.hidden.insert(sec) }
                }
            ))
            .labelsHidden()
            .help(settings.hidden.contains(sec) ? "隐藏 · 点击显示" : "显示 · 点击隐藏")
            Button {
                settings.moveUp(sec)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(idx == 0)
            .help("上移")
            Button {
                settings.moveDown(sec)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(idx == settings.order.count - 1)
            .help("下移")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.05))
        .cornerRadius(4)
    }
}

#endif
