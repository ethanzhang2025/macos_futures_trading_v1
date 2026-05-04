// WP-41 v15.18 · SuperTrend 趋势跟踪指标
//
// 算法（Wilder ATR + 自适应 band）：
//   HL2 = (high + low) / 2
//   upperBand = HL2 + multiplier * ATR(period)
//   lowerBand = HL2 - multiplier * ATR(period)
//   finalUpper / finalLower 翻转规则：
//     finalUpper = (upperBand < prevFinalUpper) || (prevClose > prevFinalUpper) ? upperBand : prevFinalUpper
//     finalLower = (lowerBand > prevFinalLower) || (prevClose < prevFinalLower) ? lowerBand : prevFinalLower
//   trend = +1 (多头) / -1 (空头)
//   ST = trend == +1 ? finalLower : finalUpper
//
// 输出：单线 ST + trend 方向（用 sign · 上层渲染按 trend 颜色区分上涨绿 / 下跌红）

import Foundation
import Shared

public enum SuperTrend: Indicator {
    public static let identifier = "SUPERTREND"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "multiplier", defaultValue: 3, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("SuperTrend 需 2 参数：period, multiplier")
        }
        let n = intValue(params[0])
        let mult = params[1]
        guard n >= 1 else {
            throw IndicatorError.invalidParameter("SuperTrend period 必须 >= 1, 实际 \(n)")
        }

        let highs = kline.highs
        let lows = kline.lows
        let closes = kline.closes
        let count = closes.count
        guard count > 0 else {
            return [
                IndicatorSeries(name: "ST(\(n),\(mult))", values: []),
                IndicatorSeries(name: "TREND", values: [])
            ]
        }

        // 复用 ATR 计算
        let atrSeries = try ATR.calculate(kline: kline, params: [Decimal(n)])
        let atr = atrSeries[0].values

        var stOut: [Decimal?] = Array(repeating: nil, count: count)
        var trendOut: [Decimal?] = Array(repeating: nil, count: count)

        var prevFinalUpper: Decimal = 0
        var prevFinalLower: Decimal = 0
        var prevTrend: Int = 1   // 默认多头开局

        for i in 0..<count {
            guard let atrVal = atr[i] else { continue }    // ATR warmup 期 nil
            let hl2 = (highs[i] + lows[i]) / 2
            let upperBand = hl2 + mult * atrVal
            let lowerBand = hl2 - mult * atrVal
            let prevClose = i > 0 ? closes[i - 1] : closes[i]

            let finalUpper: Decimal
            if prevFinalUpper == 0 {
                finalUpper = upperBand
            } else if upperBand < prevFinalUpper || prevClose > prevFinalUpper {
                finalUpper = upperBand
            } else {
                finalUpper = prevFinalUpper
            }

            let finalLower: Decimal
            if prevFinalLower == 0 {
                finalLower = lowerBand
            } else if lowerBand > prevFinalLower || prevClose < prevFinalLower {
                finalLower = lowerBand
            } else {
                finalLower = prevFinalLower
            }

            // trend 翻转规则：close 突破对侧 final → 翻转
            let trend: Int
            if prevTrend == 1 && closes[i] < finalLower {
                trend = -1
            } else if prevTrend == -1 && closes[i] > finalUpper {
                trend = 1
            } else {
                trend = prevTrend
            }

            let st = trend == 1 ? finalLower : finalUpper
            stOut[i] = Kernels.round8(st)
            trendOut[i] = Decimal(trend)

            prevFinalUpper = finalUpper
            prevFinalLower = finalLower
            prevTrend = trend
        }

        return [
            IndicatorSeries(name: "ST(\(n),\(mult))", values: stOut),
            IndicatorSeries(name: "TREND", values: trendOut)
        ]
    }
}
