// WP-41 · 指标输入 · 列向量形式的 K 线批量数据
// 选列向量（非 [KLine] 数组）是为了指标计算时直接取 closes[] / highs[] 做向量运算，避免循环取字段

import Foundation

/// 批量 K 线数据 · 所有列等长
public struct KLineSeries: Sendable, Equatable {
    public let opens: [Decimal]
    public let highs: [Decimal]
    public let lows: [Decimal]
    public let closes: [Decimal]
    public let volumes: [Int]
    public let openInterests: [Int]

    public init(opens: [Decimal], highs: [Decimal], lows: [Decimal], closes: [Decimal], volumes: [Int], openInterests: [Int]) {
        precondition(opens.count == highs.count && highs.count == lows.count
                     && lows.count == closes.count && closes.count == volumes.count
                     && volumes.count == openInterests.count,
                     "KLineSeries 各列长度必须一致")
        self.opens = opens
        self.highs = highs
        self.lows = lows
        self.closes = closes
        self.volumes = volumes
        self.openInterests = openInterests
    }

    public var count: Int { closes.count }
}
