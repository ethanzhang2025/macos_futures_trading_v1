import SwiftUI
import Shared
import MarketData

struct PositionTable: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.border)
            if vm.trading.positions.isEmpty {
                emptyView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.trading.positions.indices, id: \.self) { idx in
                            row(vm.trading.positions[idx])
                            Divider().background(Theme.border.opacity(0.5))
                        }
                    }
                }
            }
        }
        .background(Theme.panelBackground)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("持仓").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.textPrimary)
            Spacer()
            Text("\(vm.trading.positions.count) 个").font(.system(size: 10)).foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func row(_ p: Position) -> some View {
        let currentPrice = vm.priceFallback(for: p.instrumentID) ?? p.openAvgPrice
        let pnl = p.floatingPnL(currentPrice: currentPrice)
        let pnlColor: Color = pnl > 0 ? Theme.up : pnl < 0 ? Theme.down : Theme.flat
        let directionColor: Color = p.direction == .long ? Theme.up : Theme.down

        return HStack(spacing: 4) {
            cell(p.instrumentID, width: 60, align: .leading, color: Theme.textPrimary, mono: true)
            cell(p.direction.displayName, width: 36, color: directionColor)
            cell("\(p.volume)", width: 40, align: .trailing, color: Theme.textPrimary, mono: true)
            cell(Formatters.price(p.openAvgPrice), width: 60, align: .trailing, color: Theme.textPrimary, mono: true)
            cell(Formatters.price(currentPrice), width: 60, align: .trailing, color: Theme.textPrimary, mono: true)
            cell(Formatters.change(pnl), width: 70, align: .trailing, color: pnlColor, mono: true)
            Spacer(minLength: 0)
            actionButton("平") { vm.trading.flatten(p, currentPrice: currentPrice) }
            actionButton("反") { vm.trading.reverse(p, currentPrice: currentPrice) }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func cell(_ text: String, width: CGFloat, align: Alignment = .center, color: Color = Theme.textMuted, mono: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, design: mono ? .monospaced : .default))
            .foregroundColor(color)
            .frame(width: width, alignment: align)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 24, height: 20)
                .background(Theme.selected.opacity(0.6))
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("暂无持仓").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
