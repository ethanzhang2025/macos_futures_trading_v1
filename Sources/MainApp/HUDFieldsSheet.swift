// MainApp · HUD 字段编辑 Sheet（v15.14 · 6 个 Toggle 列表）
//
// 设计要点：
// - 草稿模式：取消放弃 · 保存写回 @Binding（与 IndicatorParamsSheet 同模式）
// - 还原默认按钮（仅 .debug 开 · 与 v15.13 行为一致）
// - 全选 / 全不选 快捷按钮（实战常用）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

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
            Text("HUD 显示字段")
                .font(.title2).bold()
                .padding(.bottom, 4)
            Text("勾选要在 K 线图左上 HUD 显示的字段（主标识与指标值始终显示）")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 12)

            Form {
                Section("可选字段") {
                    ForEach(HUDFieldKind.allCases) { kind in
                        Toggle(kind.displayName, isOn: bindingFor(kind))
                    }
                }

                Section {
                    HStack {
                        Button("全选") { draft.fields = Set(HUDFieldKind.allCases) }
                        Button("全不选") { draft.fields = [] }
                        Button("仅调试（默认）") { draft.fields = [.debug] }
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
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 460, height: 480)
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
