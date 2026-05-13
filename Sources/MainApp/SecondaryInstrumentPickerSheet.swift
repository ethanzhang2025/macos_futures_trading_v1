// v17.189 · 副合约 overlay 选择 sheet（多合约 chart 同图叠加 normalized close）
//
// 流程：
// 1. ChartScene ⌘⌥M 弹此 sheet
// 2. user 输入副合约 ID + 选归一化模式
// 3. onConfirm 触发 · ChartScene loadSecondaryBars(id) → 渲染 overlay
// 4. onClear 关 overlay + 清空 ID

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import IndicatorCore

struct SecondaryInstrumentPickerSheet: View {

    let primaryInstrumentID: String
    let currentSecondaryID: String
    let currentMode: MultiInstrumentNormalizer.Mode
    // v17.190 · Mac 6.3 严格 · @MainActor 让 caller closure (ChartScene) 同 isolation · 避免 cross-actor cannot find
    let onConfirm: @MainActor (String, MultiInstrumentNormalizer.Mode) -> Void
    let onClear: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var inputID: String = ""
    @State private var selectedMode: MultiInstrumentNormalizer.Mode = .firstBaseline

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("多合约 chart overlay · 副合约对比")
                .font(.title2).bold()
            Text("主合约 \(primaryInstrumentID) 上叠加另一个合约的归一化 close 曲线 · trader 跨合约判断同向/背离")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("副合约 ID").font(.headline)
                TextField("如 hc2510 / i2509 / SR2509", text: $inputID)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Text("从本地 SQLite 缓存读取 · 必须先在该合约主图打开过一次才有数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("归一化模式").font(.headline)
                Picker("", selection: $selectedMode) {
                    ForEach(MultiInstrumentNormalizer.Mode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(selectedMode == .firstBaseline
                     ? "起点对齐：两条曲线 visible 区起点重合 · 之后按百分比变化映射 · 看相对涨跌"
                     : "区间对齐：副合约 [min,max] 缩放到主合约 [min,max] · 看趋势同向性")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                if !currentSecondaryID.isEmpty {
                    Button("清除 overlay") {
                        onClear()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("确认 · 叠加") {
                    let id = inputID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty else { return }
                    onConfirm(id, selectedMode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .onAppear {
            inputID = currentSecondaryID
            selectedMode = currentMode
        }
    }
}

#endif
