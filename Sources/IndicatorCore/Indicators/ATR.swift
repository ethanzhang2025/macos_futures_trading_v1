// WP-41 · ATR · 真实波幅均值（波动率类）· Wilder 方法
// 参数：period（14）
// 公式：
//   TR(i) = max(high(i)-low(i), |high(i)-close(i-1)|, |low(i)-close(i-1)|)
//   ATR  = Wilder(TR, N)

import Foundation

public enum ATR: Indicator {
    public static let identifier = "ATR"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard let first = params.first else {
            throw IndicatorError.invalidParameter("缺少 period 参数")
        }
        let n = intValue(first)
        guard n >= 1 else {
            throw IndicatorError.invalidParameter("ATR period 必须 >= 1，实际 \(n)")
        }

        let highs = kline.highs
        let lows = kline.lows
        let closes = kline.closes
        let count = closes.count

        var tr = [Decimal](repeating: 0, count: count)
        // 第 0 根 TR = high - low（无 prevClose）
        if count > 0 { tr[0] = highs[0] - lows[0] }
        for i in 1..<count {
            let hl = highs[i] - lows[i]
            // Decimal 通过 SignedNumeric 支持 Swift.abs，无需自定义辅助
            let hc = abs(highs[i] - closes[i - 1])
            let lc = abs(lows[i] - closes[i - 1])
            tr[i] = max(hl, max(hc, lc))
        }

        let atr = Kernels.wilder(tr, period: n)
        return [IndicatorSeries(name: "ATR(\(n))", values: atr)]
    }
}
