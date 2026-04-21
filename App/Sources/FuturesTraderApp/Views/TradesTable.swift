import SwiftUI
import Shared

/// 成交记录表：渲染 MockTradingService.trades，最新在上
struct TradesTable: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Group {
            if vm.trading.trades.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(vm.trading.trades, id: \.tradeID) { trade in
                            row(trade)
                            Divider().background(Theme.border.opacity(0.5))
                        }
                    }
                }
            }
        }
        .background(Theme.panelBackground)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell("时间", width: 66, align: .leading, header: true)
            cell("合约", width: 60, align: .leading, header: true)
            cell("方向", width: 36, header: true)
            cell("开平", width: 40, header: true)
            cell("价格", width: 60, align: .trailing, header: true)
            cell("手数", width: 40, align: .trailing, header: true)
            cell("手续费", width: 60, align: .trailing, header: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.chartBackground.opacity(0.3))
    }

    private func row(_ t: TradeRecord) -> some View {
        let directionColor: Color = t.direction == .buy ? Theme.up : Theme.down
        return HStack(spacing: 0) {
            cell(t.tradeTime, width: 66, align: .leading, mono: true)
            cell(t.instrumentID, width: 60, align: .leading, color: Theme.textPrimary, mono: true)
            cell(t.direction.displayName, width: 36, color: directionColor)
            cell(t.offsetFlag.displayName, width: 40, color: Theme.textSecondary)
            cell(Formatters.price(t.price), width: 60, align: .trailing, color: Theme.textPrimary, mono: true)
            cell("\(t.volume)", width: 40, align: .trailing, color: Theme.textPrimary, mono: true)
            cell(Formatters.price(t.commission), width: 60, align: .trailing, color: Theme.textSecondary, mono: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func cell(_ text: String, width: CGFloat, align: Alignment = .center, color: Color = Theme.textSecondary, mono: Bool = false, header: Bool = false) -> some View {
        Text(text)
            .font(.system(size: header ? 10 : 11, weight: header ? .medium : .regular, design: mono ? .monospaced : .default))
            .foregroundColor(header ? Theme.textMuted : color)
            .frame(width: width, alignment: align)
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("暂无成交").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
