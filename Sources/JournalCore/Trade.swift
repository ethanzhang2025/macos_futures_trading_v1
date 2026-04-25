// WP-53 模块 1 · Trade 标准成交模型
// A09 禁做项："不要把原始交割单数据直接当最终业务模型使用"
//   → Trade 是 RawDeal CSV 解析后的标准化模型（DealCSVParser.toTrade 转换层完成 normalize）
//   → 上层（JournalGenerator / 复盘 8 图 / 月度统计）只消费 Trade，不接触 RawDeal
//
// 与 Shared.TradeRecord 的区别：
// - TradeRecord 是 CTP 实时回报快照（绑定 orderRef/tradeID String 编号 / tradeTime String）
// - Trade 是历史 CSV 导入的标准化模型（Date 时间 / Decimal 手续费 / 来源标记）
// 二者通过模块隔离命名（JournalCore.Trade vs Shared.TradeRecord）

import Foundation
import Shared

/// 成交来源 · 标记 Trade 从哪里来（影响后续 dedup / 修正策略）
public enum TradeSource: String, Sendable, Codable, CaseIterable {
    /// 文华财经 CSV 导入
    case wenhua
    /// 通用 CSV 导入（其他券商 / 自定义格式）
    case generic
    /// 手动录入（用户在 App 内填写）
    case manual
}

/// 标准成交记录 · CSV 导入归一化层
public struct Trade: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    /// 原始 CSV 中的成交编号（券商提供；用于 dedup）
    public var tradeReference: String
    public var instrumentID: String
    public var direction: Direction
    public var offsetFlag: OffsetFlag
    public var price: Decimal
    public var volume: Int
    public var commission: Decimal
    public var timestamp: Date
    public var source: TradeSource

    public init(
        id: UUID = UUID(),
        tradeReference: String,
        instrumentID: String,
        direction: Direction,
        offsetFlag: OffsetFlag,
        price: Decimal,
        volume: Int,
        commission: Decimal,
        timestamp: Date,
        source: TradeSource
    ) {
        self.id = id
        self.tradeReference = tradeReference
        self.instrumentID = instrumentID
        self.direction = direction
        self.offsetFlag = offsetFlag
        self.price = price
        self.volume = volume
        self.commission = commission
        self.timestamp = timestamp
        self.source = source
    }

    /// 成交金额（不含手续费）= price × volume × volumeMultiple
    /// volumeMultiple 由调用方提供（来自 Contract.volumeMultiple，本结构无 contract 引用）
    public func notional(volumeMultiple: Int) -> Decimal {
        price * Decimal(volume) * Decimal(volumeMultiple)
    }
}
