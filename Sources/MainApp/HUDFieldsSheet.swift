// MainApp · HUD 字段编辑 Sheet（v15.14 · v15.62 视觉 polish · 加图标 + 示例 preview）
//
// 设计要点：
// - 草稿模式：取消放弃 · 保存写回 @Binding（与 IndicatorParamsSheet 同模式）
// - 还原默认按钮（v15.58 起 default = .debug + .sectorInfo）
// - 全选 / 全不选 快捷按钮（实战常用）
// - v15.62 · 每行 SF Symbol 图标 + 简短示例 caption · 已选计数显示

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

struct HUDFieldsSheet: View {

    @Binding var book: HUDFieldsBook
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HUDFieldsBook

    init(book: Binding<HUDFieldsBook>) {
        self._book = book
        self._draft = State(initialValue: book.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("HUD 显示字段")
                    .font(.title2).bold()
                Spacer()
                Text("已选 \(draft.fields.count) / \(HUDFieldKind.allCases.count)")
                    .font(.callout.monospaced())
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            Text("勾选要在 K 线图角落 HUD 浮窗显示的字段（主标识与指标值始终显示 · 浮窗位置可在工具栏菜单切换 4 角）")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)

            Form {
                Section("可选字段") {
                    ForEach(HUDFieldKind.displayOrder) { kind in
                        Toggle(isOn: bindingFor(kind)) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 22, alignment: .center)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(kind.displayName)
                                        .font(.callout)
                                    Text(kind.sampleText)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Button("全选") { draft.fields = Set(HUDFieldKind.allCases) }
                        Button("全不选") { draft.fields = [] }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("还原默认") { draft = .default }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    book = draft
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft == book)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 540, height: 620)
    }

    private func bindingFor(_ kind: HUDFieldKind) -> Binding<Bool> {
        Binding(
            get: { draft.fields.contains(kind) },
            set: { newValue in
                if newValue { draft.fields.insert(kind) }
                else { draft.fields.remove(kind) }
            }
        )
    }
}

#endif
