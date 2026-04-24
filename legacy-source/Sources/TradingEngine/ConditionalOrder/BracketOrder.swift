import Foundation
import Shared

/// 括号单（Bracket Order）— 开仓 + 止损 + 止盈 三合一
/// 开仓成交后自动挂出止损和止盈（OCO模式）
public struct BracketOrder: Sendable, Identifiable {
    public let id: String
    public let entryOrder: OrderRequest       // 开仓委托
    public let stopLossOffset: Decimal        // 止损偏移（距开仓价的点数）
    public let takeProfitOffset: Decimal      // 止盈偏移（距开仓价的点数）
    public let instrumentID: String
    public let direction: Direction           // 开仓方向
    public var status: BracketStatus
    public var entryPrice: Decimal?           // 实际成交价
    public var ocoOrder: OCOOrder?            // 成交后生成的OCO
    public let createTime: Date

    public init(
        id: String = UUID().uuidString,
        instrumentID: String,
        direction: Direction,
        entryOrder: OrderRequest,
        stopLossOffset: Decimal,
        takeProfitOffset: Decimal
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.direction = direction
        self.entryOrder = entryOrder
        self.stopLossOffset = stopLossOffset
        self.takeProfitOffset = takeProfitOffset
        self.status = .pendingEntry
        self.createTime = Date()
    }

    /// 开仓成交后调用，生成OCO止损止盈单
    public mutating func onEntryFilled(fillPrice: Decimal) -> OCOOrder {
        entryPrice = fillPrice
        status = .entryFilled

        let stopPrice: Decimal
        let profitPrice: Decimal
        let stopCondition: PriceCondition
        let profitCondition: PriceCondition
        let closeDirection: Direction

        switch direction {
        case .buy:
            // 买入开多 → 止损在下方，止盈在上方
            stopPrice = fillPrice - stopLossOffset
            profitPrice = fillPrice + takeProfitOffset
            stopCondition = .below(stopPrice)
            profitCondition = .above(profitPrice)
            closeDirection = .sell
        case .sell:
            // 卖出开空 → 止损在上方，止盈在下方
            stopPrice = fillPrice + stopLossOffset
            profitPrice = fillPrice - takeProfitOffset
            stopCondition = .above(stopPrice)
            profitCondition = .below(profitPrice)
            closeDirection = .buy
        }

        let stopOrder = OrderRequest(
            instrumentID: instrumentID,
            direction: closeDirection,
            offsetFlag: .close,
            priceType: .marketPrice,
            price: 0,
            volume: entryOrder.volume
        )
        let profitOrder = OrderRequest(
            instrumentID: instrumentID,
            direction: closeDirection,
            offsetFlag: .close,
            priceType: .limitPrice,
            price: profitPrice,
            volume: entryOrder.volume
        )

        let oco = OCOOrder(
            instrumentID: instrumentID,
            stopLoss: stopCondition,
            takeProfit: profitCondition,
            stopLossOrder: stopOrder,
            takeProfitOrder: profitOrder
        )
        ocoOrder = oco
        return oco
    }
}

public enum BracketStatus: Sendable {
    case pendingEntry    // 等待开仓成交
    case entryFilled     // 开仓已成交，OCO已挂出
    case completed       // OCO触发，全部完成
    case cancelled       // 已取消
}
