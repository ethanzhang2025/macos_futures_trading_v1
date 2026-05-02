// WP-54 v15.6 · 模拟交易快照（持久化用）
//
// SimulatedTradingEngine.snapshot() / restore(_:) 出入参 · Codable 直接 JSON 序列化
// 持久化层（UserDefaults / SQLite）只看这个 struct · 不耦合 engine 内部实现
//
// 不持久化的 state（按设计省略）：
// - continuations（事件订阅 · App 重启后由 UI 重新订阅）
// - contracts（启动时由 App 静态注册 8 默认合约 · 不需保存）

import Foundation
import Shared

/// 模拟交易完整状态快照（v15.6 持久化的最小集合）
public struct SimulatedTradingSnapshot: Sendable, Codable, Equatable {
    public var account: Account
    public var orders: [OrderRecord]
    public var trades: [TradeRecord]
    /// 持仓数组（key=instrumentID + direction · restore 时 engine 自己重建 dict）
    public var positions: [Position]
    public var equityCurve: [EquityCurvePoint]
    public var orderRefCounter: Int
    public var tradeIDCounter: Int
    /// v15.17 · 每合约最近 markPrice 缓存（hotfix #11 P1-12 多合约浮盈用）
    /// 持久化让重启后多合约浮盈立刻正确 · 不必等下一次 onTick 才有 mark · decodeIfPresent 兼容旧快照
    public var instrumentLastPrice: [String: Decimal]

    public init(
        account: Account,
        orders: [OrderRecord],
        trades: [TradeRecord],
        positions: [Position],
        equityCurve: [EquityCurvePoint],
        orderRefCounter: Int,
        tradeIDCounter: Int,
        instrumentLastPrice: [String: Decimal] = [:]
    ) {
        self.account = account
        self.orders = orders
        self.trades = trades
        self.positions = positions
        self.equityCurve = equityCurve
        self.orderRefCounter = orderRefCounter
        self.tradeIDCounter = tradeIDCounter
        self.instrumentLastPrice = instrumentLastPrice
    }

    // v15.17 · 旧快照兼容（v15.6-v15.16 没 instrumentLastPrice 字段）· decodeIfPresent fallback 空字典
    private enum CodingKeys: String, CodingKey {
        case account, orders, trades, positions, equityCurve, orderRefCounter, tradeIDCounter, instrumentLastPrice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.account = try c.decode(Account.self, forKey: .account)
        self.orders = try c.decode([OrderRecord].self, forKey: .orders)
        self.trades = try c.decode([TradeRecord].self, forKey: .trades)
        self.positions = try c.decode([Position].self, forKey: .positions)
        self.equityCurve = try c.decode([EquityCurvePoint].self, forKey: .equityCurve)
        self.orderRefCounter = try c.decode(Int.self, forKey: .orderRefCounter)
        self.tradeIDCounter = try c.decode(Int.self, forKey: .tradeIDCounter)
        self.instrumentLastPrice = try c.decodeIfPresent([String: Decimal].self, forKey: .instrumentLastPrice) ?? [:]
    }
}
