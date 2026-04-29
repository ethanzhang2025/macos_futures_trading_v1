// WP-41 · OpenInterest · 持仓量（期货特有类 · 12 之一）
// 无周期参数，直接暴露 K 线的 openInterests 字段（TradingView 没有，我们必须有）
// 后续期货特有指标（ΔOI / 主力合约切换 / 涨跌停板线等）会基于本指标派生
//
// WP-41 v3 第 14 批：OpenInterest 实现 IncrementalIndicator · 直通（同 Volume 模式 · 极简）

import Foundation
import Shared

public enum OpenInterest: Indicator {
    public static let identifier = "OI"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        // 显式声明目标类型避开 Decimal? 转换的 map 表达式
        let values: [Decimal?] = kline.openInterests.map { Decimal($0) }
        return [IndicatorSeries(name: "OI", values: values)]
    }
}

// MARK: - WP-41 v3 第 14 批 · OpenInterest 增量 API（直通 · 同 Volume 模式 · 极简 · 无周期 · 无 warm-up · 无内部状态）

extension OpenInterest: IncrementalIndicator {

    /// state：空（OI 是 Int → Decimal 直通 · 无累积/无窗口/无 prev · 极简 · 与 Volume 增量同模式）
    public struct IncrementalState: Sendable {}

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        IncrementalState()
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // KLine.openInterest 已是 Decimal · 直接输出（与 calculate `openInterests.map { Decimal($0) }` 等价 · KLineSeries.openInterests 是 [Int]）
        [newBar.openInterest]
    }
}
