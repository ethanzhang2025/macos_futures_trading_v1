// WP-54 v15.3 · 模拟交易事件流
// SimulatedTradingEngine.observe() AsyncStream 推送事件 · UI / 测试订阅

import Foundation
import Shared

/// 模拟交易事件
public enum SimulatedTradingEvent: Sendable {
    /// 委托已提交（撮合前）· 含分配的 orderID
    case orderSubmitted(OrderRecord)
    /// 委托被引擎拒绝（资金/持仓/参数等校验失败）
    case orderRejected(orderRef: String, reason: OrderRejectReason)
    /// 委托完整成交 · 含委托记录终态 + 单笔成交（v1 简化：不分笔）
    case orderFilled(OrderRecord, TradeRecord)
    /// 委托已撤
    case orderCancelled(OrderRecord)
    /// 持仓变更（开/平后 · 含变更后持仓快照 · volume=0 表示已清仓）
    case positionChanged(Position)
    /// 账户资金变更（保证金/盈亏/手续费 任意变化都会推送）
    case accountChanged(Account)
}

/// 委托被拒绝的原因
public enum OrderRejectReason: Sendable, Error, Equatable {
    /// 合约不存在（contracts 字典未配置该 instrumentID）
    case unknownInstrument(String)
    /// 可用资金 < 开仓所需保证金
    case insufficientFunds(required: Decimal, available: Decimal)
    /// 平仓但持仓数量不足
    case insufficientPosition(direction: PositionDirection, required: Int, available: Int)
    /// 价格非法（< 0 或限价单 price=0）
    case invalidPrice(Decimal)
    /// 数量非法（≤ 0）
    case invalidVolume(Int)

    public var displayMessage: String {
        switch self {
        case .unknownInstrument(let id):
            return "合约 \(id) 不存在"
        case .insufficientFunds(let required, let available):
            return "资金不足：需要 \(required)，可用 \(available)"
        case .insufficientPosition(let direction, let required, let available):
            return "\(direction.displayName) 持仓不足：需要 \(required)，实际 \(available)"
        case .invalidPrice(let p):
            return "价格非法：\(p)"
        case .invalidVolume(let v):
            return "数量非法：\(v)"
        }
    }
}
