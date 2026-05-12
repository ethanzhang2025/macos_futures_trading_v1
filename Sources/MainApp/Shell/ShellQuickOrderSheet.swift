// MainApp · Shell · v17.57 · 空格快捷下单浮层
//
// 设计要点：
// - Stage A 不接 CTP · v1 占位 sheet（让 trader 视觉习惯"空格 = 下单"肌肉记忆）
// - v2 接 SimulatedTradingEngine · open/close/平仓/反手 真实模拟交易

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellQuickOrderSheet: View {

    @EnvironmentObject var shellVM: ShellViewModel
    @Binding var isPresented: Bool

    @State private var volume: Int = 1
    @State private var priceMode: PriceMode = .market

    enum PriceMode: String, CaseIterable, Identifiable {
        case market = "市价"
        case limit  = "限价"
        case opponent = "对手价"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("⚡ 模拟下单 · 空格")
                    .font(.headline)
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("合约").frame(width: 70, alignment: .leading).foregroundColor(.secondary)
                    Text(activeSymbol ?? "(无 active Pane)")
                        .font(.system(size: 13, design: .monospaced))
                }
                HStack {
                    Text("数量").frame(width: 70, alignment: .leading).foregroundColor(.secondary)
                    Stepper("\(volume) 手", value: $volume, in: 1...50)
                        .font(.system(size: 13, design: .monospaced))
                }
                HStack {
                    Text("价格").frame(width: 70, alignment: .leading).foregroundColor(.secondary)
                    Picker("", selection: $priceMode) {
                        ForEach(PriceMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .font(.system(size: 13))

            Divider()

            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Label("买开（多）", systemImage: "arrow.up.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)

                Button {
                    isPresented = false
                } label: {
                    Label("卖开（空）", systemImage: "arrow.down.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
            }
            .font(.system(size: 13, weight: .semibold))

            Text("v1 Stage A 占位 · v2 接 SimulatedTradingEngine 写真实持仓 · M6 后接 CTP 真实下单")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 440, height: 320)
    }

    private var activeSymbol: String? {
        guard let ws = shellVM.activeWorkspace else { return nil }
        let pane = shellVM.maximizedPaneID.flatMap { mid in ws.panes.first { $0.id == mid } }
            ?? ws.panes.first
        return pane.flatMap { shellVM.effectiveSymbol(for: $0) ?? $0.symbol }
    }
}

#endif
