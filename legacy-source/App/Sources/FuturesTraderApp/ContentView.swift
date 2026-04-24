import SwiftUI
import MarketData

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VSplitView {
                    mainArea
                        .frame(minHeight: 360)
                    TradingTabView()
                        .frame(minHeight: 100, idealHeight: 160, maxHeight: 260)
                }
                AccountBar()
            }
            .background(Theme.background)
            .preferredColorScheme(.dark)
            .onAppear { vm.startPolling() }
            .onDisappear { vm.stopPolling() }

            // 指标设置浮层
            if vm.showingIndicatorSettings {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showingIndicatorSettings = false }
                IndicatorSettingsView(params: $vm.indicatorParams, isPresented: $vm.showingIndicatorSettings)
            }
        }
    }

    private var mainArea: some View {
        HSplitView {
            ContractSidebar()
                .frame(minWidth: 220, maxWidth: 280)

            VStack(spacing: 0) {
                ToolbarView()
                if vm.isTimeline {
                    if vm.isLoading && vm.timelinePoints.isEmpty { loadingView }
                    else if vm.timelinePoints.isEmpty { emptyView }
                    else {
                        let preClose = vm.selectedQuote?.preSettlement ?? vm.selectedQuote?.close ?? 0
                        TimelineChartView(points: vm.timelinePoints, quote: vm.selectedQuote, preClose: preClose)
                    }
                } else {
                    if vm.isLoading && vm.klines.isEmpty { loadingView }
                    else if vm.klines.isEmpty { emptyView }
                    else { KLineChartView(bars: vm.klines, quote: vm.selectedQuote) }
                }
            }
            .background(Theme.background)

            VSplitView {
                OrderBookPanel(quote: vm.selectedQuote, symbolName: vm.selectedName)
                    .frame(minHeight: 260)
                OrderPanel()
                    .frame(minHeight: 240)
            }
            .frame(minWidth: 210, maxWidth: 250)
        }
    }

    private var loadingView: some View {
        VStack { Spacer(); ProgressView("加载中...").foregroundColor(Theme.textSecondary); Spacer() }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Text("暂无数据").foregroundColor(Theme.textSecondary)
            if let err = vm.errorMessage { Text(err).font(.caption).foregroundColor(Theme.up) }
            Spacer()
        }
    }
}
