// WP-31a · SinaQuote → Tick 转换
// SinaQuote 含 1 档盘口；Tick 需 5 档 → 仅 1 档有数据，其余补 0
// 缺失字段（涨跌停 / 毫秒 / turnover）用 0 / 默认值兜底
// tradingDay / actionDay 用本地日期（YYYYMMDD 格式）

import Foundation
import Shared

enum SinaQuoteToTick {

    /// 将 SinaQuote 转换为 Shared.Tick
    /// - Parameters:
    ///   - quote: 新浪报价
    ///   - instrumentID: 业务侧合约 ID（与订阅 key 一致；通常 = quote.symbol，但允许 caller 显式传入做大小写归一化）
    ///   - now: 当前时间（注入便于测试；默认 Date()）
    static func convert(_ quote: SinaQuote, instrumentID: String, now: Date = Date()) -> Tick {
        let calendar = Calendar(identifier: .gregorian)
        let dayString = Self.dateFormatter.string(from: now)
        let timeString = Self.timeFormatter.string(from: now)
        let millis = calendar.component(.nanosecond, from: now) / 1_000_000

        return Tick(
            instrumentID: instrumentID,
            lastPrice: quote.lastPrice,
            volume: quote.volume,
            openInterest: Decimal(quote.openInterest),
            turnover: 0,                                    // Sina 无成交额字段，缺失补 0
            bidPrices: [quote.bidPrice, 0, 0, 0, 0],        // Sina 仅 1 档买价
            askPrices: [quote.askPrice, 0, 0, 0, 0],        // Sina 仅 1 档卖价
            bidVolumes: [quote.bidVolume, 0, 0, 0, 0],
            askVolumes: [quote.askVolume, 0, 0, 0, 0],
            highestPrice: quote.high,
            lowestPrice: quote.low,
            openPrice: quote.open,
            preClosePrice: quote.close,                     // SinaQuote.close = 昨收（与字段命名习惯不同，详 SinaQuote.swift）
            preSettlementPrice: quote.preSettlement,
            upperLimitPrice: 0,                             // Sina 无涨跌停字段
            lowerLimitPrice: 0,
            updateTime: timeString,
            updateMillisec: millis,
            tradingDay: dayString,
            actionDay: dayString
        )
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
