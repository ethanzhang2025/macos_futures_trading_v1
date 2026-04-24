// WP-41 · OpenInterest · 持仓量（期货特有类 · 12 之一）
// 无周期参数，直接暴露 K 线的 openInterests 字段（TradingView 没有，我们必须有）
// 后续期货特有指标（ΔOI / 主力合约切换 / 涨跌停板线等）会基于本指标派生

import Foundation

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
