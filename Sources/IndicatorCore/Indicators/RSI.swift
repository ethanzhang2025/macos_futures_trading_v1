// WP-41 · RSI · 相对强弱指数（震荡类）· Wilder 经典方法
// 参数：period（默认 14）
// 公式：
//   U(i) = max(close(i) - close(i-1), 0)
//   D(i) = max(close(i-1) - close(i), 0)
//   AvgU = Wilder(U, N) / AvgD = Wilder(D, N)
//   RSI = 100 * AvgU / (AvgU + AvgD)

import Foundation

public enum RSI: Indicator {
    public static let identifier = "RSI"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard let first = params.first else {
            throw IndicatorError.invalidParameter("缺少 period 参数")
        }
        let n = intValue(first)
        guard n >= 2 else {
            throw IndicatorError.invalidParameter("RSI period 必须 >= 2，实际 \(n)")
        }

        let closes = kline.closes
        let count = closes.count
        var gains = [Decimal](repeating: 0, count: count)
        var losses = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            let diff = closes[i] - closes[i - 1]
            if diff > 0 {
                gains[i] = diff
            } else if diff < 0 {
                losses[i] = -diff
            }
        }

        let avgU = Kernels.wilder(gains, period: n)
        let avgD = Kernels.wilder(losses, period: n)

        var rsi = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let u = avgU[i], let d = avgD[i] else { continue }
            let total = u + d
            if total == 0 {
                rsi[i] = 50
            } else {
                rsi[i] = Kernels.round8(Decimal(100) * u / total)
            }
        }
        return [IndicatorSeries(name: "RSI(\(n))", values: rsi)]
    }
}
