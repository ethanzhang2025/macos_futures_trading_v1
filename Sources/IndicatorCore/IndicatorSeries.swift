// WP-41 · 指标输出 · 一条时间序列 + 语义标签
// 单指标可能输出多条（如 MACD → DIF/DEA/MACD；BOLL → 上/中/下轨），每条一个 IndicatorSeries

import Foundation

public struct IndicatorSeries: Sendable, Equatable {
    /// 序列语义标签，如 "MA(20)" / "DIF" / "BOLL-UPPER"
    public let name: String

    /// 时间对齐的值；未计算点为 nil（如周期未满）
    public let values: [Decimal?]

    public init(name: String, values: [Decimal?]) {
        self.name = name
        self.values = values
    }

    public var count: Int { values.count }
}
