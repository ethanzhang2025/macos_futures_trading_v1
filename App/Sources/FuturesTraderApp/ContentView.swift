import SwiftUI
import MarketData

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HSplitView {
            // 左侧：合约列表
            ContractSidebar()
                .frame(minWidth: 240, maxWidth: 300)

            // 中央：K线图 + MACD
            VStack(spacing: 0) {
                ToolbarView()
                if vm.isLoading && vm.klines.isEmpty {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else if vm.klines.isEmpty {
                    Spacer()
                    Text("暂无K线数据")
                        .foregroundColor(.secondary)
                    if let err = vm.errorMessage {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                    Spacer()
                } else {
                    KLineChartView(bars: vm.klines, quote: vm.selectedQuote)
                }
            }

            // 右侧：盘口信息（始终显示）
            OrderBookPanel(quote: vm.selectedQuote, symbolName: vm.selectedName)
                .frame(minWidth: 200, maxWidth: 240)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
    }
}
