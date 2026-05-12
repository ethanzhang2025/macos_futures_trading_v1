// MainApp · v17.60 · A1.2/A1.5 算法参数 UI sheet
//
// Renko / P&F / Kagi 三类算法图表的参数 trader 可调 sheet
// 仅当 chartType ∈ {.renko, .pointFigure, .kagi} 时在 toolbar 显示 ⚙️ 按钮触发
//
// 参数语义：
//   - Renko brickSize 百分比（基于 first close · 默认 0.5%）
//   - P&F boxSize 百分比（默认 0.5%）+ 反转 boxes 数（默认 3 经典）
//   - Kagi reversal 百分比（默认 1.0%）
//
// 持久化：ChartTypeOptionsStore（UserDefaults JSON · 全局共享 · 不分合约）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ChartTypeOptionsSheet: View {

    @Binding var isPresented: Bool
    let chartType: ChartType
    let onApply: (ChartTypeOptions) -> Void

    @State private var options: ChartTypeOptions = ChartTypeOptionsStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("⚙️ \(chartType.displayName) 参数")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Divider()

            // Renko · brickSize 百分比
            if chartType == .renko {
                paramRow(
                    label: "砖块大小（brickSize）",
                    valueText: String(format: "%.2f%%", options.renkoBrickPercent),
                    help: "百分比基于第一根 K 线的 close · 默认 0.5%"
                ) {
                    Slider(value: $options.renkoBrickPercent, in: 0.1...5.0, step: 0.05)
                }
                examplePreview(text: "示例 · close = 3500 → brickSize = ¥\(Int(round(3500 * options.renkoBrickPercent / 100)))")
            }

            // P&F · boxSize + reversal
            if chartType == .pointFigure {
                paramRow(
                    label: "格子大小（boxSize）",
                    valueText: String(format: "%.2f%%", options.pnfBoxPercent),
                    help: "百分比基于第一根 K 线的 close · 默认 0.5%"
                ) {
                    Slider(value: $options.pnfBoxPercent, in: 0.1...5.0, step: 0.05)
                }
                paramRow(
                    label: "反转 boxes",
                    valueText: "\(options.pnfReversalBoxes) 格",
                    help: "经典 3 格反转（Three-Box Reversal · 1 格灵敏 · 5 格保守）"
                ) {
                    Stepper("", value: $options.pnfReversalBoxes, in: 1...10)
                        .labelsHidden()
                }
                examplePreview(text: "示例 · close = 3500 → boxSize = ¥\(Int(round(3500 * options.pnfBoxPercent / 100))) · 反转 = \(options.pnfReversalBoxes) 格")
            }

            // Kagi · reversal 百分比
            if chartType == .kagi {
                paramRow(
                    label: "反转幅度（reversal）",
                    valueText: String(format: "%.2f%%", options.kagiReversalPercent),
                    help: "百分比基于第一根 K 线的 close · 经典 1%"
                ) {
                    Slider(value: $options.kagiReversalPercent, in: 0.1...10.0, step: 0.1)
                }
                examplePreview(text: "示例 · close = 3500 → reversal = ¥\(Int(round(3500 * options.kagiReversalPercent / 100)))")
            }

            Divider()

            HStack {
                Button("恢复默认") {
                    options = .default
                }
                Spacer()
                Button("取消") { isPresented = false }
                Button("应用并保存") {
                    ChartTypeOptionsStore.save(options)
                    onApply(options)
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }

    @ViewBuilder
    private func paramRow<Control: View>(label: String, valueText: String, help: String,
                                          @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            control()
            Text(help)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func examplePreview(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(4)
    }
}

#endif
