import Foundation

/// 持仓方向
public enum PositionDirection: Sendable {
    case long
    case short

    public var displayName: String {
        switch self {
        case .long:  return "多"
        case .short: return "空"
        }
    }
}

/// 持仓记录
public struct Position: Sendable {
    public let instrumentID: String
    public let direction: PositionDirection
    public var volume: Int
    public var todayVolume: Int
    public var avgPrice: Decimal
    public var openAvgPrice: Decimal
    public let preSettlementPrice: Decimal
    public var margin: Decimal
    public let volumeMultiple: Int

    public init(
        instrumentID: String,
        direction: PositionDirection,
        volume: Int,
        todayVolume: Int,
        avgPrice: Decimal,
        openAvgPrice: Decimal,
        preSettlementPrice: Decimal,
        margin: Decimal,
        volumeMultiple: Int
    ) {
        self.instrumentID = instrumentID
        self.direction = direction
        self.volume = volume
        self.todayVolume = todayVolume
        self.avgPrice = avgPrice
        self.openAvgPrice = openAvgPrice
        self.preSettlementPrice = preSettlementPrice
        self.margin = margin
        self.volumeMultiple = volumeMultiple
    }

    public var yesterdayVolume: Int { volume - todayVolume }

    /// 逐笔浮盈（按开仓均价）
    public func floatingPnL(currentPrice: Decimal) -> Decimal {
        let diff: Decimal
        switch direction {
        case .long:  diff = currentPrice - openAvgPrice
        case .short: diff = openAvgPrice - currentPrice
        }
        return diff * Decimal(volume) * Decimal(volumeMultiple)
    }

    /// 盯市浮盈（按昨结算价）
    public func markToMarketPnL(currentPrice: Decimal) -> Decimal {
        let diff: Decimal
        switch direction {
        case .long:  diff = currentPrice - preSettlementPrice
        case .short: diff = preSettlementPrice - currentPrice
        }
        return diff * Decimal(volume) * Decimal(volumeMultiple)
    }
}
