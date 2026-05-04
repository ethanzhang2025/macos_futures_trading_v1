// WP-41 v15.18 · Bollinger Bandwidth (BBW) 波动率紧缩指标（trader 找 squeeze）
//
// 算法：
//   BBW(n, k) = (UpperBand - LowerBand) / MiddleBand × 100
//   其中 BOLL(n, k) = MA(close, n) ± k × StdDev(close, n)
//
// 默认 n=20, k=2（与 BOLL 经典参数一致）
//
// 解读：
// - BBW 极低（如 < 历史 10% 分位）= squeeze · 即将爆发突破
// - BBW 升高 = 趋势展开 / 波动放大

import Foundation
import Shared

public enum BollingerBandwidth: Indicator {
    public static let identifier = "BBW"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 200),
        IndicatorParameter(name: "stdDev", defaultValue: 2, minValue: 1, maxValue: 5)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("BBW 需 2 参数：period, stdDev")
        }
        // 复用 BOLL 计算
        let bollSeries = try BOLL.calculate(kline: kline, params: params)
        guard bollSeries.count >= 3 else {
            return [IndicatorSeries(name: "BBW", values: [])]
        }
        let upper = bollSeries[0].values
        let middle = bollSeries[1].values
        let lower = bollSeries[2].values
        let count = upper.count

        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let u = upper[i], let m = middle[i], let l = lower[i], m > 0 else { continue }
            let bandwidth = (u - l) / m * Decimal(100)
            out[i] = Kernels.round8(bandwidth)
        }
        return [IndicatorSeries(name: "BBW", values: out)]
    }
}
