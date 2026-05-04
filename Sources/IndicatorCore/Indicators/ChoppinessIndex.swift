// WP-41 v15.18 · Choppiness Index 震荡度指标（E.W. Dreiss · trader 用于趋势 vs 横盘判定）
//
// 算法：
//   CI(n) = 100 × log10(SUM(TR, n) / (HHV(high, n) - LLV(low, n))) / log10(n)
//   其中 TR = max(high-low, |high-prevClose|, |low-prevClose|)
//
// 值域 0-100：
// - CI > 61.8（黄金分割）= 强横盘（高震荡）
// - CI < 38.2 = 强趋势（突破方向不确定 · 配合方向指标判断）
//
// 默认 n = 14

import Foundation
import Shared

public enum Choppiness: Indicator {
    public static let identifier = "CHOPPINESS"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "Choppiness period")
        let highs = kline.highs
        let lows = kline.lows
        let closes = kline.closes
        let count = closes.count

        // TR 序列（首根 = high - low · 后续 max 三差）
        var tr = [Decimal](repeating: 0, count: count)
        if count > 0 { tr[0] = highs[0] - lows[0] }
        for i in 1..<count {
            let hl = highs[i] - lows[i]
            let hc = abs(highs[i] - closes[i - 1])
            let lc = abs(lows[i] - closes[i - 1])
            tr[i] = max(hl, max(hc, lc))
        }

        let log10n = Foundation.log10(Double(n))
        guard log10n > 0 else {
            throw IndicatorError.invalidParameter("Choppiness log10(\(n)) 非正")
        }

        var out = [Decimal?](repeating: nil, count: count)
        // 数据不足窗口 · 直接返回全 nil（避免 Swift Range 越界 trap）
        guard count >= n else {
            return [IndicatorSeries(name: "CI(\(n))", values: out)]
        }
        for i in (n - 1)..<count {
            let start = i - n + 1
            let trSum = tr[start...i].reduce(Decimal(0), +)
            let hh = highs[start...i].max() ?? 0
            let ll = lows[start...i].min() ?? 0
            let range = hh - ll
            guard range > 0 else { continue }
            let ratio = NSDecimalNumber(decimal: trSum / range).doubleValue
            guard ratio > 0 else { continue }
            let ci = 100 * Foundation.log10(ratio) / log10n
            out[i] = Kernels.round8(Decimal(ci))
        }

        return [IndicatorSeries(name: "CI(\(n))", values: out)]
    }
}
