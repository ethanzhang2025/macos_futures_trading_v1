import Foundation
import Shared

/// 条件单类型
public enum ConditionalOrderType: Sendable {
    case stopLoss          // 止损单
    case takeProfit        // 止盈单
    case priceTriggered    // 触价单
    case timeTriggered     // 时间条件单
}

/// 价格条件
public enum PriceCondition: Sendable {
    case above(Decimal)    // 价格高于
    case below(Decimal)    // 价格低于
    case crossAbove(Decimal) // 上穿
    case crossBelow(Decimal) // 下穿
}

/// 条件单状态
public enum ConditionalOrderStatus: Sendable {
    case active            // 活跃监控中
    case triggered         // 已触发
    case cancelled         // 已取消
    case paused            // 暂停（断线时）
    case failed            // 触发失败
}

/// 条件单
public struct ConditionalOrder: Sendable, Identifiable {
    public let id: String
    public let instrumentID: String
    public let type: ConditionalOrderType
    public let condition: PriceCondition
    public let orderRequest: OrderRequest
    public var status: ConditionalOrderStatus
    public let createTime: Date
    public var triggerTime: Date?
    public var message: String?

    public init(
        id: String = UUID().uuidString,
        instrumentID: String,
        type: ConditionalOrderType,
        condition: PriceCondition,
        orderRequest: OrderRequest,
        status: ConditionalOrderStatus = .active,
        createTime: Date = Date()
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.type = type
        self.condition = condition
        self.orderRequest = orderRequest
        self.status = status
        self.createTime = createTime
    }

    /// 检查当前价格是否满足触发条件
    public func shouldTrigger(currentPrice: Decimal, previousPrice: Decimal?) -> Bool {
        guard status == .active else { return false }
        switch condition {
        case .above(let target):
            return currentPrice >= target
        case .below(let target):
            return currentPrice <= target
        case .crossAbove(let target):
            guard let prev = previousPrice else { return false }
            return prev < target && currentPrice >= target
        case .crossBelow(let target):
            guard let prev = previousPrice else { return false }
            return prev > target && currentPrice <= target
        }
    }
}

/// 条件单管理器
/// v15.17 · @unchecked Sendable + NSLock · 配 Stage B 多 tick 流并发 fanout（同 instrumentID 多源）
/// Stage A 未激活（仅测试中实例化）· 加锁是 Stage B 接入前的准备
public final class ConditionalOrderManager: @unchecked Sendable {
    private var orders: [String: ConditionalOrder] = [:]
    private var previousPrices: [String: Decimal] = [:]
    private let lock = NSLock()

    public init() {}

    /// 添加条件单
    public func add(_ order: ConditionalOrder) {
        lock.lock(); defer { lock.unlock() }
        orders[order.id] = order
    }

    /// 取消条件单
    public func cancel(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        orders[id]?.status = .cancelled
    }

    /// 暂停所有（断线时）
    public func pauseAll() {
        lock.lock(); defer { lock.unlock() }
        for id in orders.keys {
            if orders[id]?.status == .active {
                orders[id]?.status = .paused
            }
        }
    }

    /// 恢复所有（重连后）
    public func resumeAll() {
        lock.lock(); defer { lock.unlock() }
        for id in orders.keys {
            if orders[id]?.status == .paused {
                orders[id]?.status = .active
            }
        }
    }

    /// 检查Tick是否触发条件单，返回被触发的条件单列表
    public func checkTrigger(instrumentID: String, currentPrice: Decimal) -> [ConditionalOrder] {
        lock.lock(); defer { lock.unlock() }
        let prevPrice = previousPrices[instrumentID]
        previousPrices[instrumentID] = currentPrice

        var triggered: [ConditionalOrder] = []
        for (id, order) in orders {
            guard order.instrumentID == instrumentID, order.status == .active else { continue }
            if order.shouldTrigger(currentPrice: currentPrice, previousPrice: prevPrice) {
                orders[id]?.status = .triggered
                orders[id]?.triggerTime = Date()
                triggered.append(orders[id]!)
            }
        }
        return triggered
    }

    /// 获取所有活跃条件单
    public var activeOrders: [ConditionalOrder] {
        lock.lock(); defer { lock.unlock() }
        return orders.values.filter { $0.status == .active }
    }

    /// 获取所有条件单
    public var allOrders: [ConditionalOrder] {
        lock.lock(); defer { lock.unlock() }
        return Array(orders.values)
    }
}
