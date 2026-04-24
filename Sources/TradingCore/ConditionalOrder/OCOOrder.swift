import Foundation
import Shared

/// OCO单（One Cancels Other）— 止损止盈二选一
/// 触发一个后自动取消另一个
public struct OCOOrder: Sendable, Identifiable {
    public let id: String
    public let instrumentID: String
    public let stopLoss: PriceCondition       // 止损条件
    public let takeProfit: PriceCondition     // 止盈条件
    public let stopLossOrder: OrderRequest    // 止损委托
    public let takeProfitOrder: OrderRequest  // 止盈委托
    public var status: OCOStatus
    public let createTime: Date
    public var triggerTime: Date?
    public var triggeredSide: OCOTriggeredSide?

    public init(
        id: String = UUID().uuidString,
        instrumentID: String,
        stopLoss: PriceCondition,
        takeProfit: PriceCondition,
        stopLossOrder: OrderRequest,
        takeProfitOrder: OrderRequest
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.stopLossOrder = stopLossOrder
        self.takeProfitOrder = takeProfitOrder
        self.status = .active
        self.createTime = Date()
    }

    /// 检查是否触发，返回触发的委托（如果有）
    public mutating func check(currentPrice: Decimal, previousPrice: Decimal?) -> OrderRequest? {
        guard status == .active else { return nil }

        // 先检查止损
        if shouldTrigger(condition: stopLoss, current: currentPrice, previous: previousPrice) {
            status = .triggered
            triggeredSide = .stopLoss
            triggerTime = Date()
            return stopLossOrder
        }

        // 再检查止盈
        if shouldTrigger(condition: takeProfit, current: currentPrice, previous: previousPrice) {
            status = .triggered
            triggeredSide = .takeProfit
            triggerTime = Date()
            return takeProfitOrder
        }

        return nil
    }

    private func shouldTrigger(condition: PriceCondition, current: Decimal, previous: Decimal?) -> Bool {
        switch condition {
        case .above(let target):     return current >= target
        case .below(let target):     return current <= target
        case .crossAbove(let target):
            guard let prev = previous else { return false }
            return prev < target && current >= target
        case .crossBelow(let target):
            guard let prev = previous else { return false }
            return prev > target && current <= target
        }
    }
}

public enum OCOStatus: Sendable {
    case active
    case triggered
    case cancelled
    case paused
}

public enum OCOTriggeredSide: Sendable {
    case stopLoss
    case takeProfit
}
