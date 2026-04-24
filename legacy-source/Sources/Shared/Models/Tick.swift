import Foundation

/// 期货Tick行情数据
public struct Tick: Sendable {
    /// 合约代码（如 rb2501）
    public let instrumentID: String
    /// 最新价
    public let lastPrice: Decimal
    /// 成交量（本次）
    public let volume: Int
    /// 持仓量
    public let openInterest: Decimal
    /// 成交额
    public let turnover: Decimal
    /// 买一到买五价
    public let bidPrices: [Decimal]
    /// 卖一到卖五价
    public let askPrices: [Decimal]
    /// 买一到买五量
    public let bidVolumes: [Int]
    /// 卖一到卖五量
    public let askVolumes: [Int]
    /// 最高价
    public let highestPrice: Decimal
    /// 最低价
    public let lowestPrice: Decimal
    /// 开盘价
    public let openPrice: Decimal
    /// 昨收盘价
    public let preClosePrice: Decimal
    /// 昨结算价
    public let preSettlementPrice: Decimal
    /// 涨停价
    public let upperLimitPrice: Decimal
    /// 跌停价
    public let lowerLimitPrice: Decimal
    /// 更新时间 (HH:MM:SS)
    public let updateTime: String
    /// 更新毫秒
    public let updateMillisec: Int
    /// 交易日 (YYYYMMDD)
    public let tradingDay: String
    /// 自然日 (YYYYMMDD)
    public let actionDay: String

    public init(
        instrumentID: String,
        lastPrice: Decimal,
        volume: Int,
        openInterest: Decimal,
        turnover: Decimal,
        bidPrices: [Decimal],
        askPrices: [Decimal],
        bidVolumes: [Int],
        askVolumes: [Int],
        highestPrice: Decimal,
        lowestPrice: Decimal,
        openPrice: Decimal,
        preClosePrice: Decimal,
        preSettlementPrice: Decimal,
        upperLimitPrice: Decimal,
        lowerLimitPrice: Decimal,
        updateTime: String,
        updateMillisec: Int,
        tradingDay: String,
        actionDay: String
    ) {
        self.instrumentID = instrumentID
        self.lastPrice = lastPrice
        self.volume = volume
        self.openInterest = openInterest
        self.turnover = turnover
        self.bidPrices = bidPrices
        self.askPrices = askPrices
        self.bidVolumes = bidVolumes
        self.askVolumes = askVolumes
        self.highestPrice = highestPrice
        self.lowestPrice = lowestPrice
        self.openPrice = openPrice
        self.preClosePrice = preClosePrice
        self.preSettlementPrice = preSettlementPrice
        self.upperLimitPrice = upperLimitPrice
        self.lowerLimitPrice = lowerLimitPrice
        self.updateTime = updateTime
        self.updateMillisec = updateMillisec
        self.tradingDay = tradingDay
        self.actionDay = actionDay
    }
}
