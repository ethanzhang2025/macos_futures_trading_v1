// WP-41 · BOLL · 布林带（波动率 / 通道类）
// 参数：period（20）/ k（2，标准差倍数）
// 公式：
//   MID   = MA(close, N)
//   UPPER = MID + k * StdDev(close, N)
//   LOWER = MID - k * StdDev(close, N)

import Foundation

public enum BOLL: Indicator {
    public static let identifier = "BOLL"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500),
        IndicatorParameter(name: "k", defaultValue: 2, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("BOLL 需要 2 个参数（period / k）")
        }
        let n = intValue(params[0])
        let k = params[1]
        guard n >= 2, k > 0 else {
            throw IndicatorError.invalidParameter("BOLL 参数非法: period=\(n) k=\(k)")
        }

        let mid = Kernels.ma(kline.closes, period: n)
        let sd = Kernels.stddev(kline.closes, period: n)
        let count = kline.count

        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = mid[i], let s = sd[i] {
                upper[i] = Kernels.round8(m + k * s)
                lower[i] = Kernels.round8(m - k * s)
            }
        }
        return [
            IndicatorSeries(name: "BOLL-MID", values: mid),
            IndicatorSeries(name: "BOLL-UPPER", values: upper),
            IndicatorSeries(name: "BOLL-LOWER", values: lower)
        ]
    }
}
