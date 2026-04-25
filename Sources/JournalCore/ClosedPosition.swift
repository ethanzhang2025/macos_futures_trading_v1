// WP-50 模块 1 · 闭合持仓（开仓 trade + 平仓 trade 的配对结果）
// 复盘 8 图的核心数据单位 —— 单笔已实现盈亏的最小载体
//
// PnL 公式：
// - 多头（buy-open → sell-close）：(closePrice - openPrice) × volume × multiplier - 总手续费
// - 空头（sell-open → buy-close）：(openPrice - closePrice) × volume × multiplier - 总手续费
//
// 持仓时长：closeTrade.timestamp - openTrade.timestamp（单位秒）

import Foundation
import Shared

/// 持仓方向
public enum PositionSide: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case long   // 多头（buy-open）
    case short  // 空头（sell-open）
}

/// 闭合持仓 · 一对开+平 trade 的产物
public struct ClosedPosition: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var instrumentID: String
    public var side: PositionSide
    public var openTradeID: UUID
    public var closeTradeID: UUID
    public var openTime: Date
    public var closeTime: Date
    public var openPrice: Decimal
    public var closePrice: Decimal
    public var volume: Int
    /// 已实现盈亏（已扣手续费）
    public var realizedPnL: Decimal
    /// 总手续费（开 + 平）
    public var totalCommission: Decimal

    public init(
        id: UUID = UUID(),
        instrumentID: String,
        side: PositionSide,
        openTradeID: UUID,
        closeTradeID: UUID,
        openTime: Date,
        closeTime: Date,
        openPrice: Decimal,
        closePrice: Decimal,
        volume: Int,
        realizedPnL: Decimal,
        totalCommission: Decimal
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.side = side
        self.openTradeID = openTradeID
        self.closeTradeID = closeTradeID
        self.openTime = openTime
        self.closeTime = closeTime
        self.openPrice = openPrice
        self.closePrice = closePrice
        self.volume = volume
        self.realizedPnL = realizedPnL
        self.totalCommission = totalCommission
    }

    /// 持仓时长（秒）
    public var holdingSeconds: TimeInterval {
        closeTime.timeIntervalSince(openTime)
    }

    /// 是否盈利
    public var isWin: Bool { realizedPnL > 0 }
}
