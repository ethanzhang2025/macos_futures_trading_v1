import SwiftUI
import MarketData
import Shared

@MainActor
final class AppViewModel: ObservableObject {
    @Published var quotes: [SinaQuote] = []
    @Published var selectedSymbol: String = "RB0"
    @Published var klines: [SinaKLineBar] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPeriod: String = "日线"

    private let api = SinaMarketData()
    private var pollingTask: Task<Void, Never>?

    /// 所有监控的合约
    let watchList = SinaFuturesSymbol.all

    /// 当前选中的合约名称
    var selectedName: String {
        watchList.first { $0.symbol == selectedSymbol }?.name ?? selectedSymbol
    }

    /// 当前选中的报价
    var selectedQuote: SinaQuote? {
        quotes.first { $0.symbol == selectedSymbol }
    }

    /// 启动行情轮询
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            await loadKLines()
            while !Task.isCancelled {
                await fetchQuotes()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// 停止轮询
    func stopPolling() {
        pollingTask?.cancel()
    }

    /// 切换合约
    func selectSymbol(_ symbol: String) {
        selectedSymbol = symbol
        Task { await loadKLines() }
    }

    /// 切换周期
    func selectPeriod(_ period: String) {
        selectedPeriod = period
        Task { await loadKLines() }
    }

    /// 获取实时报价
    private func fetchQuotes() async {
        let symbols = watchList.map { $0.symbol }
        do {
            let result = try await api.fetchQuotes(symbols: symbols)
            self.quotes = result
            self.errorMessage = nil
        } catch {
            self.errorMessage = "行情获取失败: \(error.localizedDescription)"
        }
    }

    /// 加载K线数据
    func loadKLines() async {
        isLoading = true
        do {
            let bars: [SinaKLineBar]
            switch selectedPeriod {
            case "5分":
                bars = try await api.fetchMinute5KLines(symbol: selectedSymbol)
            case "15分":
                bars = try await api.fetchMinute15KLines(symbol: selectedSymbol)
            case "60分":
                bars = try await api.fetchMinute60KLines(symbol: selectedSymbol)
            default:
                bars = try await api.fetchDailyKLines(symbol: selectedSymbol)
            }
            self.klines = bars
            self.errorMessage = nil
        } catch {
            self.errorMessage = "K线数据加载失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
