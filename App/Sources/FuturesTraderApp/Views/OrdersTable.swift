import SwiftUI
import Shared

/// 委托单历史表（从 MockTradingService.orders 渲染，最新在上）
struct OrdersTable: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Group {
            if vm.trading.orders.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        headerRow
                        ForEach(vm.trading.orders, id: \.orderRef) { order in
                            row(order)
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
            cell("委托", width: 40, align: .trailing, header: true)
            cell("成交", width: 40, align: .trailing, header: true)
            cell("状态", width: 70, align: .leading, header: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.chartBackground.opacity(0.3))
    }

    private func row(_ o: OrderRecord) -> some View {
        let directionColor: Color = o.direction == .buy ? Theme.up : Theme.down
        let statusColor: Color = {
            switch o.status {
            case .filled:             return Theme.textPrimary
            case .cancelled, .rejected: return Theme.textMuted
            case .submitted, .pending:  return Color.orange
            case .partFilled:           return Color.yellow
            case .unknown:              return Theme.textSecondary
            }
        }()
        return HStack(spacing: 0) {
            cell(o.insertTime, width: 66, align: .leading, mono: true)
            cell(o.instrumentID, width: 60, align: .leading, color: Theme.textPrimary, mono: true)
            cell(o.direction.displayName, width: 36, color: directionColor)
            cell(o.offsetFlag.displayName, width: 40, color: Theme.textSecondary)
            cell(Formatters.price(o.price), width: 60, align: .trailing, color: Theme.textPrimary, mono: true)
            cell("\(o.totalVolume)", width: 40, align: .trailing, color: Theme.textPrimary, mono: true)
            cell("\(o.filledVolume)", width: 40, align: .trailing, color: Theme.textPrimary, mono: true)
            cell(o.statusMessage, width: 70, align: .leading, color: statusColor)
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
            Text("暂无委托").font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
