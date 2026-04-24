// WP-41 · MA · 简单移动平均（趋势类）
// 参数：period（默认 20）

import Foundation

public enum MA: Indicator {
    public static let identifier = "MA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try periodInt(params)
        let values = Kernels.ma(kline.closes, period: n)
        return [IndicatorSeries(name: "MA(\(n))", values: values)]
    }
}

public enum EMA: Indicator {
    public static let identifier = "EMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 12, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try periodInt(params)
        let values = Kernels.ema(kline.closes, period: n)
        return [IndicatorSeries(name: "EMA(\(n))", values: values)]
    }
}

// MARK: - 参数校验

fileprivate func periodInt(_ params: [Decimal]) throws -> Int {
    guard let first = params.first else {
        throw IndicatorError.invalidParameter("缺少 period 参数")
    }
    let n = intValue(first)
    guard n > 0 else {
        throw IndicatorError.invalidParameter("period 必须大于 0，实际 \(n)")
    }
    return n
}
