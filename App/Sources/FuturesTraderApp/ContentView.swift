import SwiftUI
import MarketData

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HSplitView {
            // 左侧：合约列表
            ContractSidebar()
                .frame(minWidth: 220, maxWidth: 280)

            // 中央：K线图 + 成交量
            VStack(spacing: 0) {
                ToolbarView()
                if vm.isLoading && vm.klines.isEmpty {
                    Spacer()
                    ProgressView("加载中...")
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                } else if vm.klines.isEmpty {
                    Spacer()
                    Text("暂无K线数据")
                        .foregroundColor(Theme.textSecondary)
                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundColor(Theme.up)
                    }
                    Spacer()
                } else {
                    KLineChartView(bars: vm.klines, quote: vm.selectedQuote)
                }
            }
            .background(Theme.background)

            // 右侧：盘口信息
            OrderBookPanel(quote: vm.selectedQuote, symbolName: vm.selectedName)
                .frame(minWidth: 190, maxWidth: 230)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
    }
}
