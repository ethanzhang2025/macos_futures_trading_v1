import Foundation
import Shared

/// 追踪止损单
/// 止损价随最高浮盈动态调整，锁定利润
public struct TrailingStop: Sendable, Identifiable {
    public let id: String
    public let instrumentID: String
    public let direction: PositionDirection  // 持仓方向（止损方向相反）
    public let trailAmount: Decimal          // 回撤金额（固定点数）
    public let orderVolume: Int              // 平仓手数
    public var status: ConditionalOrderStatus
    public var highestPrice: Decimal?        // 多头追踪的最高价
    public var lowestPrice: Decimal?         // 空头追踪的最低价
    public var currentStopPrice: Decimal?    // 当前止损价
    public let createTime: Date
    public var triggerTime: Date?

    public init(
        id: String = UUID().uuidString,
        instrumentID: String,
        direction: PositionDirection,
        trailAmount: Decimal,
        orderVolume: Int
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.direction = direction
        self.trailAmount = trailAmount
        self.orderVolume = orderVolume
        self.status = .active
        self.createTime = Date()
    }

    /// 更新价格，返回是否触发
    public mutating func update(currentPrice: Decimal) -> Bool {
        guard status == .active else { return false }

        switch direction {
        case .long:
            // 多头持仓：追踪最高价，回落trailAmount触发平多
            if highestPrice == nil || currentPrice > highestPrice! {
                highestPrice = currentPrice
                currentStopPrice = currentPrice - trailAmount
            }
            if currentPrice <= currentStopPrice! {
                status = .triggered
                triggerTime = Date()
                return true
            }
        case .short:
            // 空头持仓：追踪最低价，反弹trailAmount触发平空
            if lowestPrice == nil || currentPrice < lowestPrice! {
                lowestPrice = currentPrice
                currentStopPrice = currentPrice + trailAmount
            }
            if currentPrice >= currentStopPrice! {
                status = .triggered
                triggerTime = Date()
                return true
            }
        }
        return false
    }

    /// 生成平仓委托
    public func makeCloseOrder() -> OrderRequest {
        let closeDirection: Direction = direction == .long ? .sell : .buy
        return OrderRequest(
            instrumentID: instrumentID,
            direction: closeDirection,
            offsetFlag: .close,
            priceType: .marketPrice,
            price: 0,
            volume: orderVolume
        )
    }
}
