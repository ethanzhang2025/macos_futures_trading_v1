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
    /// v15.98 · 策略标签（透传自开仓 Trade.setup · nil 未标）
    public var setup: String?

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
        totalCommission: Decimal,
        setup: String? = nil
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
        self.setup = setup
    }

    /// 持仓时长（秒）
    public var holdingSeconds: TimeInterval {
        closeTime.timeIntervalSince(openTime)
    }

    /// 是否盈利
    public var isWin: Bool { realizedPnL > 0 }

    // MARK: - Codable（兼容旧 JSON · 缺 setup 时回退 nil）

    private enum CodingKeys: String, CodingKey {
        case id, instrumentID, side, openTradeID, closeTradeID,
             openTime, closeTime, openPrice, closePrice, volume,
             realizedPnL, totalCommission, setup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.instrumentID = try c.decode(String.self, forKey: .instrumentID)
        self.side = try c.decode(PositionSide.self, forKey: .side)
        self.openTradeID = try c.decode(UUID.self, forKey: .openTradeID)
        self.closeTradeID = try c.decode(UUID.self, forKey: .closeTradeID)
        self.openTime = try c.decode(Date.self, forKey: .openTime)
        self.closeTime = try c.decode(Date.self, forKey: .closeTime)
        self.openPrice = try c.decode(Decimal.self, forKey: .openPrice)
        self.closePrice = try c.decode(Decimal.self, forKey: .closePrice)
        self.volume = try c.decode(Int.self, forKey: .volume)
        self.realizedPnL = try c.decode(Decimal.self, forKey: .realizedPnL)
        self.totalCommission = try c.decode(Decimal.self, forKey: .totalCommission)
        self.setup = try c.decodeIfPresent(String.self, forKey: .setup)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(instrumentID, forKey: .instrumentID)
        try c.encode(side, forKey: .side)
        try c.encode(openTradeID, forKey: .openTradeID)
        try c.encode(closeTradeID, forKey: .closeTradeID)
        try c.encode(openTime, forKey: .openTime)
        try c.encode(closeTime, forKey: .closeTime)
        try c.encode(openPrice, forKey: .openPrice)
        try c.encode(closePrice, forKey: .closePrice)
        try c.encode(volume, forKey: .volume)
        try c.encode(realizedPnL, forKey: .realizedPnL)
        try c.encode(totalCommission, forKey: .totalCommission)
        try c.encodeIfPresent(setup, forKey: .setup)
    }
}
