import Foundation

/// 交易所
public enum Exchange: String, Sendable, CaseIterable {
    case SHFE  = "SHFE"
    case INE   = "INE"
    case DCE   = "DCE"
    case CZCE  = "CZCE"
    case CFFEX = "CFFEX"
    case GFEX  = "GFEX"

    public var displayName: String {
        switch self {
        case .SHFE:  return "上期所"
        case .INE:   return "能源中心"
        case .DCE:   return "大商所"
        case .CZCE:  return "郑商所"
        case .CFFEX: return "中金所"
        case .GFEX:  return "广期所"
        }
    }

    /// 是否区分平今/平昨手续费
    public var distinguishCloseToday: Bool {
        self == .SHFE || self == .INE
    }
}

/// 合约信息
public struct Contract: Sendable {
    public let instrumentID: String
    public let instrumentName: String
    public let exchange: Exchange
    public let productID: String
    public let volumeMultiple: Int
    public let priceTick: Decimal
    public let deliveryMonth: Int
    public let expireDate: String
    public let longMarginRatio: Decimal
    public let shortMarginRatio: Decimal
    public let isTrading: Bool
    public let productName: String
    public let pinyinInitials: String

    public init(
        instrumentID: String,
        instrumentName: String,
        exchange: Exchange,
        productID: String,
        volumeMultiple: Int,
        priceTick: Decimal,
        deliveryMonth: Int,
        expireDate: String,
        longMarginRatio: Decimal,
        shortMarginRatio: Decimal,
        isTrading: Bool,
        productName: String,
        pinyinInitials: String
    ) {
        self.instrumentID = instrumentID
        self.instrumentName = instrumentName
        self.exchange = exchange
        self.productID = productID
        self.volumeMultiple = volumeMultiple
        self.priceTick = priceTick
        self.deliveryMonth = deliveryMonth
        self.expireDate = expireDate
        self.longMarginRatio = longMarginRatio
        self.shortMarginRatio = shortMarginRatio
        self.isTrading = isTrading
        self.productName = productName
        self.pinyinInitials = pinyinInitials
    }

    /// 一跳价值 = 最小变动价位 × 合约乘数
    public var tickValue: Decimal {
        priceTick * Decimal(volumeMultiple)
    }
}
