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
    @Published var subChartType: SubChartType = .macd
    @Published var timelinePoints: [SinaTimelinePoint] = []
    @Published var maConfig: MAConfig = .default
    @Published var showBoll: Bool = true
    let drawingState = DrawingState()

    var isTimeline: Bool { selectedPeriod == "分时" }

    private let api = SinaMarketData()
    private var pollingTask: Task<Void, Never>?

    let watchList = SinaFuturesSymbol.all
    private let periods = ["分时", "日线", "60分", "15分", "5分"]

    var selectedName: String {
        watchList.first { $0.symbol == selectedSymbol }?.name ?? selectedSymbol
    }

    var selectedQuote: SinaQuote? {
        quotes.first { $0.symbol == selectedSymbol }
    }

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

    func stopPolling() { pollingTask?.cancel() }

    func selectSymbol(_ symbol: String) {
        selectedSymbol = symbol
        Task { await loadKLines() }
    }

    func selectPeriod(_ period: String) {
        selectedPeriod = period
        Task { await loadKLines() }
    }

    // MARK: - 键盘操作

    /// 上一个合约
    func selectPrevSymbol() {
        guard let idx = watchList.firstIndex(where: { $0.symbol == selectedSymbol }), idx > 0 else { return }
        selectSymbol(watchList[idx - 1].symbol)
    }

    /// 下一个合约
    func selectNextSymbol() {
        guard let idx = watchList.firstIndex(where: { $0.symbol == selectedSymbol }), idx < watchList.count - 1 else { return }
        selectSymbol(watchList[idx + 1].symbol)
    }

    /// 按数字键切换周期
    func selectPeriodByKey(_ key: Int) {
        guard key >= 1, key <= periods.count else { return }
        selectPeriod(periods[key - 1])
    }

    /// 切换副图指标
    func cycleSubChart() {
        let all = SubChartType.allCases
        guard let idx = all.firstIndex(of: subChartType) else { return }
        subChartType = all[(idx + 1) % all.count]
    }

    // MARK: - 数据加载

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

    func loadKLines() async {
        isLoading = true
        do {
            if selectedPeriod == "分时" {
                let pts = (try? await api.fetchTimeline(symbol: selectedSymbol)) ?? []
                self.timelinePoints = pts
            } else {
                let bars: [SinaKLineBar]
                switch selectedPeriod {
                case "5分":  bars = try await api.fetchMinute5KLines(symbol: selectedSymbol)
                case "15分": bars = try await api.fetchMinute15KLines(symbol: selectedSymbol)
                case "60分": bars = try await api.fetchMinute60KLines(symbol: selectedSymbol)
                default:     bars = try await api.fetchDailyKLines(symbol: selectedSymbol)
                }
                self.klines = bars
            }
            self.errorMessage = nil
        } catch {
            self.errorMessage = "数据加载失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
