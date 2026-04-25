import Foundation

/// K线周期
public enum KLinePeriod: String, Sendable, CaseIterable {
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

    /// 周期秒数（用于K线合成）
    public var seconds: Int {
        switch self {
        case .second1:  return 1
        case .second3:  return 3
        case .second5:  return 5
        case .second10: return 10
        case .second15: return 15
        case .second30: return 30
        case .minute1:  return 60
        case .minute3:  return 180
        case .minute5:  return 300
        case .minute15: return 900
        case .minute30: return 1800
        case .hour1:    return 3600
        case .hour2:    return 7200
        case .hour4:    return 14400
        case .daily:    return 86400
        case .weekly:   return 604800
        case .monthly:  return 2592000
        }
    }

    /// 中文显示名
    public var displayName: String {
        switch self {
        case .second1:  return "1秒"
        case .second3:  return "3秒"
        case .second5:  return "5秒"
        case .second10: return "10秒"
        case .second15: return "15秒"
        case .second30: return "30秒"
        case .minute1:  return "1分"
        case .minute3:  return "3分"
        case .minute5:  return "5分"
        case .minute15: return "15分"
        case .minute30: return "30分"
        case .hour1:    return "1时"
        case .hour2:    return "2时"
        case .hour4:    return "4时"
        case .daily:    return "日线"
        case .weekly:   return "周线"
        case .monthly:  return "月线"
        }
    }
}

/// K线数据
public struct KLine: Sendable, Codable {
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
