import SwiftUI
import MarketData

/// 预览用的Mock数据
enum PreviewData {
    static let viewModel: AppViewModel = {
        let vm = AppViewModel()
        return vm
    }()

    /// 生成模拟K线数据
    static let mockKLines: [SinaKLineBar] = {
        var bars: [SinaKLineBar] = []
        var price = 3500.0
        for i in 0..<100 {
            let change = Double.random(in: -50...50)
            let open = price
            let close = price + change
            let high = max(open, close) + Double.random(in: 0...30)
            let low = min(open, close) - Double.random(in: 0...30)
            let vol = Int.random(in: 50000...200000)
            let date = "2025-01-\(String(format: "%02d", (i % 28) + 1))"
            bars.append(SinaKLineBar(
                date: date,
                open: Decimal(open), high: Decimal(high),
                low: Decimal(low), close: Decimal(close),
                volume: vol
            ))
            price = close
        }
        return bars
    }()

    static let mockQuote = SinaQuote(
        symbol: "RB0", name: "螺纹钢",
        open: 3500, high: 3550, low: 3480, close: 3490,
        bidPrice: 3520, askPrice: 3521,
        lastPrice: 3520, settlementPrice: 3510,
        preSettlement: 3490, bidVolume: 150, askVolume: 120,
        openInterest: 1500000, volume: 850000, timestamp: ""
    )
}

// MARK: - 各视图的Preview

#Preview("K线图") {
    KLineChartView(bars: PreviewData.mockKLines, quote: PreviewData.mockQuote)
        .environmentObject(PreviewData.viewModel)
        .frame(width: 900, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("合约列表") {
    ContractSidebar()
        .environmentObject(PreviewData.viewModel)
        .frame(width: 260, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("盘口面板") {
    OrderBookPanel(quote: PreviewData.mockQuote, symbolName: "螺纹钢")
        .environmentObject(PreviewData.viewModel)
        .frame(width: 220, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("工具栏") {
    ToolbarView()
        .environmentObject(PreviewData.viewModel)
        .frame(width: 900)
        .preferredColorScheme(.dark)
}

#Preview("完整界面") {
    ContentView()
        .environmentObject(PreviewData.viewModel)
        .frame(width: 1300, height: 750)
        .preferredColorScheme(.dark)
}
