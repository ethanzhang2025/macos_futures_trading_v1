import Foundation

/// 买卖方向
public enum Direction: String, Sendable, Codable {
    case buy  = "0"
    case sell = "1"

    public var displayName: String {
        switch self {
        case .buy:  return "买"
        case .sell: return "卖"
        }
    }
}

/// 开平标志
public enum OffsetFlag: String, Sendable, Codable {
    case open       = "0"  // 开仓
    case close      = "1"  // 平仓
    case forceClose = "2"  // 强平
    case closeToday = "3"  // 平今
    case closeYesterday = "4"  // 平昨

    public var displayName: String {
        switch self {
        case .open:           return "开仓"
        case .close:          return "平仓"
        case .forceClose:     return "强平"
        case .closeToday:     return "平今"
        case .closeYesterday: return "平昨"
        }
    }
}

/// 报单价格类型
public enum OrderPriceType: String, Sendable {
    case limitPrice  = "2"  // 限价
    case marketPrice = "1"  // 市价
}

/// 委托状态
public enum OrderStatus: String, Sendable, Codable {
    case pending        // 待报
    case submitted      // 已报
    case partFilled     // 部分成交
    case filled         // 全部成交
    case cancelled      // 已撤
    case rejected       // 拒绝
    case unknown        // 未知

    public var displayName: String {
        switch self {
        case .pending:    return "待报"
        case .submitted:  return "已报"
        case .partFilled: return "部分成交"
        case .filled:     return "全部成交"
        case .cancelled:  return "已撤"
        case .rejected:   return "废单"
        case .unknown:    return "未知"
        }
    }

    public var isActive: Bool {
        self == .pending || self == .submitted || self == .partFilled
    }
}

/// 委托请求
public struct OrderRequest: Sendable {
    public let instrumentID: String
    public let direction: Direction
    public let offsetFlag: OffsetFlag
    public let priceType: OrderPriceType
    public let price: Decimal
    public let volume: Int

    public init(
        instrumentID: String,
        direction: Direction,
        offsetFlag: OffsetFlag,
        priceType: OrderPriceType,
        price: Decimal,
        volume: Int
    ) {
        self.instrumentID = instrumentID
        self.direction = direction
        self.offsetFlag = offsetFlag
        self.priceType = priceType
        self.price = price
        self.volume = volume
    }
}

/// 委托记录
public struct OrderRecord: Sendable, Codable, Equatable {
    public let orderRef: String
    public let instrumentID: String
    public let direction: Direction
    public let offsetFlag: OffsetFlag
    public let price: Decimal
    public let totalVolume: Int
    public var filledVolume: Int
    public var status: OrderStatus
    public let insertTime: String
    public var statusMessage: String

    public init(
        orderRef: String,
        instrumentID: String,
        direction: Direction,
        offsetFlag: OffsetFlag,
        price: Decimal,
        totalVolume: Int,
        filledVolume: Int,
        status: OrderStatus,
        insertTime: String,
        statusMessage: String
    ) {
        self.orderRef = orderRef
        self.instrumentID = instrumentID
        self.direction = direction
        self.offsetFlag = offsetFlag
        self.price = price
        self.totalVolume = totalVolume
        self.filledVolume = filledVolume
        self.status = status
        self.insertTime = insertTime
        self.statusMessage = statusMessage
    }

    public var remainingVolume: Int { totalVolume - filledVolume }
}

/// 成交记录
public struct TradeRecord: Sendable, Codable, Equatable {
    public let tradeID: String
    public let orderRef: String
    public let instrumentID: String
    public let direction: Direction
    public let offsetFlag: OffsetFlag
    public let price: Decimal
    public let volume: Int
    public let tradeTime: String
    public let commission: Decimal

    public init(
        tradeID: String,
        orderRef: String,
        instrumentID: String,
        direction: Direction,
        offsetFlag: OffsetFlag,
        price: Decimal,
        volume: Int,
        tradeTime: String,
        commission: Decimal
    ) {
        self.tradeID = tradeID
        self.orderRef = orderRef
        self.instrumentID = instrumentID
        self.direction = direction
        self.offsetFlag = offsetFlag
        self.price = price
        self.volume = volume
        self.tradeTime = tradeTime
        self.commission = commission
    }
}
