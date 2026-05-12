import Foundation

/// K线周期
public enum KLinePeriod: String, Sendable, Codable, CaseIterable {
    case second1  = "1s"
    case second3  = "3s"
    case second5  = "5s"
    case second10 = "10s"
    case second15 = "15s"
    case second30 = "30s"
    case minute1  = "1m"
    case minute3  = "3m"
    case minute5  = "5m"
    case minute15 = "15m"
    case minute30 = "30m"
    case hour1    = "1h"
    case hour2    = "2h"
    case hour4    = "4h"
    case daily    = "D"
    case weekly   = "W"
    case monthly  = "M"
    // v17.7 · TradingView 对齐 A2.2 · 季 / 半年 / 年（长线 trader）
    case quarterly  = "Q"
    case semiAnnual = "HY"
    case annual     = "Y"

    /// 周期秒数（用于K线合成）
    public var seconds: Int {
        switch self {
        case .second1:    return 1
        case .second3:    return 3
        case .second5:    return 5
        case .second10:   return 10
        case .second15:   return 15
        case .second30:   return 30
        case .minute1:    return 60
        case .minute3:    return 180
        case .minute5:    return 300
        case .minute15:   return 900
        case .minute30:   return 1800
        case .hour1:      return 3600
        case .hour2:      return 7200
        case .hour4:      return 14400
        case .daily:      return 86400
        case .weekly:     return 604800
        case .monthly:    return 2592000     // 30 天近似
        case .quarterly:  return 7776000     // 90 天近似
        case .semiAnnual: return 15552000    // 180 天近似
        case .annual:     return 31536000    // 365 天近似
        }
    }

    /// 中文显示名
    public var displayName: String {
        switch self {
        case .second1:    return "1秒"
        case .second3:    return "3秒"
        case .second5:    return "5秒"
        case .second10:   return "10秒"
        case .second15:   return "15秒"
        case .second30:   return "30秒"
        case .minute1:    return "1分"
        case .minute3:    return "3分"
        case .minute5:    return "5分"
        case .minute15:   return "15分"
        case .minute30:   return "30分"
        case .hour1:      return "1时"
        case .hour2:      return "2时"
        case .hour4:      return "4时"
        case .daily:      return "日线"
        case .weekly:     return "周线"
        case .monthly:    return "月线"
        case .quarterly:  return "季线"
        case .semiAnnual: return "半年线"
        case .annual:     return "年线"
        }
    }
}

/// K线数据
public struct KLine: Sendable, Codable, Equatable {
    /// 合约代码
    public let instrumentID: String
    /// 周期
    public let period: KLinePeriod
    /// K线开始时间
    public let openTime: Date
    /// 开盘价
    public var open: Decimal
    /// 最高价
    public var high: Decimal
    /// 最低价
    public var low: Decimal
    /// 收盘价
    public var close: Decimal
    /// 成交量
    public var volume: Int
    /// 持仓量
    public var openInterest: Decimal
    /// 成交额
    public var turnover: Decimal

    public init(
        instrumentID: String,
        period: KLinePeriod,
        openTime: Date,
        open: Decimal,
        high: Decimal,
        low: Decimal,
        close: Decimal,
        volume: Int,
        openInterest: Decimal,
        turnover: Decimal
    ) {
        self.instrumentID = instrumentID
        self.period = period
        self.openTime = openTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.openInterest = openInterest
        self.turnover = turnover
    }

    /// 用Tick更新当前K线
    public mutating func update(with tick: Tick) {
        if tick.lastPrice > high { high = tick.lastPrice }
        if tick.lastPrice < low { low = tick.lastPrice }
        close = tick.lastPrice
        volume += tick.volume
        openInterest = tick.openInterest
        turnover += tick.turnover
    }

    /// 是否为阳线
    public var isBullish: Bool { close >= open }

    /// 涨跌幅（相对开盘价）
    public var changePercent: Decimal {
        guard open != 0 else { return 0 }
        return (close - open) / open * 100
    }

    /// 振幅
    public var amplitude: Decimal {
        guard open != 0 else { return 0 }
        return (high - low) / open * 100
    }
}

// MARK: - Renko 砖块图变换（v17.52 A1.2）

extension KLine {
    /// 把原始 OHLC K 线变换为 Renko 砖块序列 · TradingView 对齐 A1.2
    /// 算法（经典 close-based Renko · brickSize 价格阈值）：
    ///   anchor 起始 = bars[0].close
    ///   遍历每根原 bar：
    ///     while close - anchor >= brickSize  → 输出阳砖 (open=anchor, close=anchor+brickSize) · anchor 上移
    ///     while anchor - close >= brickSize  → 输出阴砖 (open=anchor, close=anchor-brickSize) · anchor 下移
    /// 每砖 open/close 严格相距 brickSize（high/low 与 open/close 一致 · 经典砖块视觉）
    /// volume/openInterest/turnover 取触发 bar 原值（不分摊 · 视觉信息保留）
    /// openTime 跟随触发 bar（多砖可共享时间 · 时间轴不严格 · 与 TradingView 一致）
    public static func renko(from bars: [KLine], brickSize: Decimal) -> [KLine] {
        guard !bars.isEmpty, brickSize > 0 else { return [] }
        var result: [KLine] = []
        result.reserveCapacity(bars.count)
        var anchor: Decimal = bars[0].close
        for bar in bars {
            while bar.close - anchor >= brickSize {
                let open = anchor
                let close = anchor + brickSize
                result.append(KLine(
                    instrumentID: bar.instrumentID,
                    period: bar.period,
                    openTime: bar.openTime,
                    open: open, high: close, low: open, close: close,
                    volume: bar.volume,
                    openInterest: bar.openInterest,
                    turnover: bar.turnover
                ))
                anchor = close
            }
            while anchor - bar.close >= brickSize {
                let open = anchor
                let close = anchor - brickSize
                result.append(KLine(
                    instrumentID: bar.instrumentID,
                    period: bar.period,
                    openTime: bar.openTime,
                    open: open, high: open, low: close, close: close,
                    volume: bar.volume,
                    openInterest: bar.openInterest,
                    turnover: bar.turnover
                ))
                anchor = close
            }
        }
        return result
    }

    /// 默认 brickSize 启发式：first close × 0.5%（中性 trader 习惯 · UI 配置交给 ChartScene）
    public static func defaultRenkoBrickSize(for bars: [KLine]) -> Decimal {
        guard let first = bars.first else { return 1 }
        let raw = first.close * Decimal(string: "0.005")!
        return raw > 0 ? raw : 1
    }
}

// MARK: - Heikin Ashi 变换（v17.13 A1.1）

extension KLine {
    /// 把原始 OHLC K 线变换为 Heikin Ashi（平均 K 线）· trader 看趋势更稳的图表类型
    /// 公式：
    ///   HA_close[i] = (open + high + low + close) / 4
    ///   HA_open[0]  = (open[0] + close[0]) / 2
    ///   HA_open[i]  = (HA_open[i-1] + HA_close[i-1]) / 2 · for i > 0
    ///   HA_high[i]  = max(high, HA_open, HA_close)
    ///   HA_low[i]   = min(low, HA_open, HA_close)
    /// volume / openInterest / turnover 保持原值（HA 只重塑价格 4 值 · 体量数据不变）
    public static func heikinAshi(from bars: [KLine]) -> [KLine] {
        guard !bars.isEmpty else { return [] }
        var result: [KLine] = []
        result.reserveCapacity(bars.count)
        let four = Decimal(4)
        let two = Decimal(2)
        var prevHAOpen: Decimal = (bars[0].open + bars[0].close) / two
        var prevHAClose: Decimal = (bars[0].open + bars[0].high + bars[0].low + bars[0].close) / four
        for (i, bar) in bars.enumerated() {
            let haClose = (bar.open + bar.high + bar.low + bar.close) / four
            let haOpen: Decimal = (i == 0) ? (bar.open + bar.close) / two : (prevHAOpen + prevHAClose) / two
            let haHigh = max(bar.high, max(haOpen, haClose))
            let haLow  = min(bar.low,  min(haOpen, haClose))
            result.append(KLine(
                instrumentID: bar.instrumentID,
                period: bar.period,
                openTime: bar.openTime,
                open: haOpen,
                high: haHigh,
                low: haLow,
                close: haClose,
                volume: bar.volume,
                openInterest: bar.openInterest,
                turnover: bar.turnover
            ))
            prevHAOpen = haOpen
            prevHAClose = haClose
        }
        return result
    }
}
