// WP-41 v15.18 · Elder Ray 多空力量指标（Alexander Elder · trader 经典）
//
// 算法：
//   BullPower(n) = High - EMA(Close, n)
//   BearPower(n) = Low - EMA(Close, n)
//
// 默认 n = 13
// 解读：
// - BullPower > 0 + 上升 → 多头主导
// - BearPower < 0 + 下降 → 空头主导
// - 双线背离 = 趋势衰竭信号

import Foundation
import Shared

public enum ElderRay: Indicator {
    public static let identifier = "ELDER"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 13, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "ElderRay period")
        let highs = kline.highs
        let lows = kline.lows
        let closes = kline.closes
        let count = closes.count

        let ema = Kernels.ema(closes, period: n)
        var bull = [Decimal?](repeating: nil, count: count)
        var bear = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let e = ema[i] else { continue }
            bull[i] = Kernels.round8(highs[i] - e)
            bear[i] = Kernels.round8(lows[i] - e)
        }
        return [
            IndicatorSeries(name: "Bull(\(n))", values: bull),
            IndicatorSeries(name: "Bear(\(n))", values: bear)
        ]
    }
}
