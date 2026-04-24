// WP-31 · SinaMarketData 适配 HistoricalKLineProvider 协议
// 手术式改动：不动 SinaMarketData 原有行为，仅通过 extension 实现 protocol 方法，内部调原方法 + 结果类型 adapt
// 与 Legacy 保持完全等价的运行时行为

import Foundation

extension SinaKLineBar {
    /// 转为 provider-agnostic 的 HistoricalKLine
    fileprivate func toHistoricalKLine() -> HistoricalKLine {
        HistoricalKLine(
            date: date,
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volume,
            openInterest: openInterest
        )
    }
}

extension SinaMarketData: HistoricalKLineProvider {
    public func historicalDaily(symbol: String) async throws -> [HistoricalKLine] {
        let bars = try await fetchDailyKLines(symbol: symbol)
        return bars.map { $0.toHistoricalKLine() }
    }

    public func historicalMinute(symbol: String, intervalMinutes: Int) async throws -> [HistoricalKLine] {
        let bars: [SinaKLineBar]
        switch intervalMinutes {
        case 5:  bars = try await fetchMinute5KLines(symbol: symbol)
        case 15: bars = try await fetchMinute15KLines(symbol: symbol)
        case 60: bars = try await fetchMinute60KLines(symbol: symbol)
        default: throw MarketDataError.unsupportedInterval(intervalMinutes)
        }
        return bars.map { $0.toHistoricalKLine() }
    }
}
