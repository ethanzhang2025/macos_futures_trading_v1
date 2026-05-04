// WP-41 v15.18 · Force Index (FI) 力量指标（Alexander Elder · 价 + 量复合）
//
// 算法：
//   FI(1) = (close[i] - close[i-1]) × volume[i]   // 第 0 根 nil
//   FI(n) = EMA(FI(1), n)                          // 平滑版
//
// 默认 n = 13
// 解读：
// - FI > 0 = 多头力量主导（涨 + 量配合）
// - FI < 0 = 空头力量主导（跌 + 量配合）
// - 极值峰对应趋势反转（零线穿越 = 多空切换）

import Foundation
import Shared

public enum ForceIndex: Indicator {
    public static let identifier = "FI"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 13, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "ForceIndex period")
        let closes = kline.closes
        let volumes = kline.volumes
        let count = closes.count
        guard count > 0 else {
            return [IndicatorSeries(name: "FI(\(n))", values: [])]
        }

        // FI(1) raw 序列
        var raw = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            raw[i] = (closes[i] - closes[i - 1]) * Decimal(volumes[i])
        }

        // FI(n) = EMA(raw, n) · 第 0 根置 nil（与 calculate 语义一致）
        let smoothed = Kernels.ema(raw, period: n)
        var out: [Decimal?] = smoothed
        if count > 0 { out[0] = nil }
        return [IndicatorSeries(name: "FI(\(n))", values: out)]
    }
}
