import SwiftUI

/// 下方交易面板：Tab 切换 [持仓 | 委托]，替代原先直接展示的 PositionTable
struct TradingTabView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var tab: Tab = .positions

    enum Tab { case positions, orders, trades }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tabButton("持仓 \(vm.trading.positions.count)", .positions)
                tabButton("委托 \(vm.trading.orders.count)", .orders)
                tabButton("成交 \(vm.trading.trades.count)", .trades)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.panelBackground)

            Divider().background(Theme.border)

            switch tab {
            case .positions: PositionTable()
            case .orders:    OrdersTable()
            case .trades:    TradesTable()
            }
        }
        .background(Theme.panelBackground)
    }

    private func tabButton(_ title: String, _ value: Tab) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.system(size: 12, weight: tab == value ? .bold : .regular))
                .foregroundColor(tab == value ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tab == value ? Theme.selected.opacity(0.5) : Color.clear)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
}
