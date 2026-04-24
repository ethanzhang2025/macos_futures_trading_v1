// HistoricalKLineProvider · 历史 K 线查询 provider 协议
// WP-31 抽象 · 为 WP-40 图表 / WP-50 复盘 / WP-51 回放 提供 provider-agnostic 历史数据接口
// 现有实现：SinaMarketData（Legacy，通过 SinaMarketData+Provider.swift 适配）
// 未来实现：CTPHistoricalProvider（Stage B）/ 本地缓存 Provider

import Foundation

/// 统一 K 线结构 · 与各 provider 原生类型解耦
public struct HistoricalKLine: Sendable, Equatable {
    /// 时间戳字符串（日 K 为 "YYYY-MM-DD"；分钟 K 为 "YYYY-MM-DD HH:mm"）
    public let date: String
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    public let volume: Int
    /// 持仓量（部分 provider 无此字段时传 0）
    public let openInterest: Int

    public init(date: String, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Int, openInterest: Int) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.openInterest = openInterest
    }
}

/// 历史 K 线查询 provider
public protocol HistoricalKLineProvider: Sendable {
    /// 查询日 K 线
    func historicalDaily(symbol: String) async throws -> [HistoricalKLine]

    /// 查询分钟 K 线
    /// - Parameter intervalMinutes: 支持周期（5 / 15 / 60）；不支持则抛 `.unsupportedInterval`
    func historicalMinute(symbol: String, intervalMinutes: Int) async throws -> [HistoricalKLine]
}

/// 历史数据 provider 的统一错误类型
public enum MarketDataError: Error, CustomStringConvertible, Equatable {
    case unsupportedInterval(Int)
    case providerError(String)

    public var description: String {
        switch self {
        case .unsupportedInterval(let m): return "不支持的周期: \(m) 分钟"
        case .providerError(let msg): return "Provider 错误: \(msg)"
        }
    }
}
