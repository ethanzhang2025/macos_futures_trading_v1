// WP-41 v15.18 · Aroon 指标（趋势强度 + 方向 · trader 流行）
//
// 算法（Tushar Chande 1995）：
//   AroonUp(n)    = ((n - daysSinceHighestHigh)  / n) × 100
//   AroonDown(n)  = ((n - daysSinceLowestLow)    / n) × 100
//   AroonOsc      = AroonUp - AroonDown   (-100 ~ +100)
//
// 解读：
// - AroonUp 接近 100 = 近期创新高（强多头）
// - AroonDown 接近 100 = 近期创新低（强空头）
// - AroonOsc > 0 多头 / < 0 空头 / ≈ 0 横盘
//
// 输出：3 series（AroonUp / AroonDown / AroonOsc · 上层一图三线）

import Foundation
import Shared

public enum Aroon: Indicator {
    public static let identifier = "AROON"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "Aroon period")
        guard n >= 2 else {
            throw IndicatorError.invalidParameter("Aroon period 必须 >= 2，实际 \(n)")
        }
        let highs = kline.highs
        let lows = kline.lows
        let count = highs.count

        var up = [Decimal?](repeating: nil, count: count)
        var down = [Decimal?](repeating: nil, count: count)
        var osc = [Decimal?](repeating: nil, count: count)
        let nDec = Decimal(n)

        for i in 0..<count {
            // warmup 期 (i < n - 1) 数据不足窗口 · nil
            guard i >= n - 1 else { continue }
            let start = i - n + 1
            // 找窗口内最近一次最高 / 最低（按距 i 的天数 · 0 = 当前 bar · n-1 = 窗口最旧）
            var highIdx = start
            var lowIdx = start
            for j in (start + 1)...i {
                if highs[j] >= highs[highIdx] { highIdx = j }   // 同值取最近（更新 idx）
                if lows[j] <= lows[lowIdx] { lowIdx = j }
            }
            let daysSinceHigh = Decimal(i - highIdx)
            let daysSinceLow = Decimal(i - lowIdx)
            let upVal = (nDec - daysSinceHigh) / nDec * Decimal(100)
            let downVal = (nDec - daysSinceLow) / nDec * Decimal(100)
            up[i] = Kernels.round8(upVal)
            down[i] = Kernels.round8(downVal)
            osc[i] = Kernels.round8(upVal - downVal)
        }

        return [
            IndicatorSeries(name: "AroonUp(\(n))", values: up),
            IndicatorSeries(name: "AroonDown(\(n))", values: down),
            IndicatorSeries(name: "AroonOsc(\(n))", values: osc)
        ]
    }
}
