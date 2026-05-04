// WP-41 v15.18 · ATR% 标准化波动率指标（trader 跨品种比较用）
//
// 算法：
//   ATR%(n) = ATR(n) / Close × 100
//
// 解读：
// - 跨品种比较波动率（绝对 ATR 不可比 · ATR% 标准化后可比）
// - 期货品种波动率排序 · 例如螺纹 1.5% vs 黄金 0.8%
//
// 默认 n = 14（与 ATR 一致）

import Foundation
import Shared

public enum ATRPercent: Indicator {
    public static let identifier = "ATRP"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        // 复用 ATR 计算
        let atrSeries = try ATR.calculate(kline: kline, params: params)
        guard !atrSeries.isEmpty else {
            return [IndicatorSeries(name: "ATRP", values: [])]
        }
        let atr = atrSeries[0].values
        let closes = kline.closes
        let count = atr.count

        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let a = atr[i], i < closes.count, closes[i] > 0 else { continue }
            out[i] = Kernels.round8(a / closes[i] * Decimal(100))
        }
        return [IndicatorSeries(name: "ATRP", values: out)]
    }
}
