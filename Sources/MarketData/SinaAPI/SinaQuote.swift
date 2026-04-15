import Foundation

/// 新浪期货行情报价
public struct SinaQuote: Sendable {
    public let symbol: String        // 合约代码（如RB0）
    public let name: String          // 名称
    public let open: Decimal         // 开盘价
    public let high: Decimal         // 最高价
    public let low: Decimal          // 最低价
    public let close: Decimal        // 昨收盘
    public let bidPrice: Decimal     // 买价
    public let askPrice: Decimal     // 卖价
    public let lastPrice: Decimal    // 最新价
    public let settlementPrice: Decimal  // 结算价
    public let preSettlement: Decimal    // 昨结算
    public let bidVolume: Int        // 买量
    public let askVolume: Int        // 卖量
    public let openInterest: Int     // 持仓量
    public let volume: Int           // 成交量
    public let timestamp: String     // 时间

    /// 涨跌
    public var change: Decimal {
        lastPrice - preSettlement
    }

    /// 涨跌幅(%)
    public var changePercent: Decimal {
        guard preSettlement != 0 else { return 0 }
        return change / preSettlement * 100
    }

    /// 是否上涨
    public var isUp: Bool { change > 0 }
}

/// 新浪K线数据（单根）
public struct SinaKLineBar: Sendable {
    public let date: String
    public let open: Decimal
    public let high: Decimal
    public let low: Decimal
    public let close: Decimal
    public let volume: Int

    public init(date: String, open: Decimal, high: Decimal, low: Decimal, close: Decimal, volume: Int) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

/// 分时数据点
public struct SinaTimelinePoint: Sendable {
    public let time: String      // HH:MM
    public let price: Decimal
    public let avgPrice: Decimal
    public let volume: Int

    public init(time: String, price: Decimal, avgPrice: Decimal, volume: Int) {
        self.time = time
        self.price = price
        self.avgPrice = avgPrice
        self.volume = volume
    }
}

/// 常用期货合约代码映射
public enum SinaFuturesSymbol {
    public static let all: [(symbol: String, name: String, pinyin: String)] = [
        ("RB0", "螺纹钢", "LWG"),
        ("HC0", "热卷", "RJ"),
        ("I0", "铁矿石", "TKS"),
        ("J0", "焦炭", "JT"),
        ("JM0", "焦煤", "JM"),
        ("AU0", "黄金", "HJ"),
        ("AG0", "白银", "BY"),
        ("CU0", "铜", "T"),
        ("AL0", "铝", "L"),
        ("ZN0", "锌", "X"),
        ("NI0", "镍", "N"),
        ("SC0", "原油", "YY"),
        ("M0", "豆粕", "DP"),
        ("Y0", "豆油", "DY"),
        ("P0", "棕榈油", "ZLY"),
        ("C0", "玉米", "YM"),
        ("A0", "豆一", "DY"),
        ("L0", "聚乙烯", "JYX"),
        ("PP0", "聚丙烯", "JBX"),
        ("V0", "PVC", "PVC"),
        ("EB0", "苯乙烯", "BYX"),
        ("EG0", "乙二醇", "YEC"),
        ("SR0", "白糖", "BT"),
        ("CF0", "棉花", "MH"),
        ("TA0", "PTA", "PTA"),
        ("MA0", "甲醇", "JC"),
        ("FG0", "玻璃", "BL"),
        ("SA0", "纯碱", "CJ"),
        ("UR0", "尿素", "NS"),
        ("AP0", "苹果", "PG"),
        ("IF0", "沪深300", "HS300"),
        ("IC0", "中证500", "ZZ500"),
        ("IM0", "中证1000", "ZZ1000"),
        ("IH0", "上证50", "SZ50"),
        ("SI0", "工业硅", "GYG"),
        ("LC0", "碳酸锂", "TSL"),
    ]
}
