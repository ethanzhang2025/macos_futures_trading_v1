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

    public init(
        account: Account,
        orders: [OrderRecord],
        trades: [TradeRecord],
        positions: [Position],
        equityCurve: [EquityCurvePoint],
        orderRefCounter: Int,
        tradeIDCounter: Int
    ) {
        self.account = account
        self.orders = orders
        self.trades = trades
        self.positions = positions
        self.equityCurve = equityCurve
        self.orderRefCounter = orderRefCounter
        self.tradeIDCounter = tradeIDCounter
    }
}
