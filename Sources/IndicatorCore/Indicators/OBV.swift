// WP-41 · OBV · 累积能量潮（量价类）
// 无周期参数
// 公式：
//   OBV(0) = volume(0)
//   OBV(i) = OBV(i-1) + volume(i)   （close 上涨）
//          = OBV(i-1) - volume(i)   （close 下跌）
//          = OBV(i-1)               （close 平）

import Foundation

public enum OBV: Indicator {
    public static let identifier = "OBV"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let closes = kline.closes
        let volumes = kline.volumes
        let count = closes.count

        var out = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return [IndicatorSeries(name: "OBV", values: out)] }

        var running = Decimal(volumes[0])
        out[0] = running
        for i in 1..<count {
            if closes[i] > closes[i - 1] {
                running += Decimal(volumes[i])
            } else if closes[i] < closes[i - 1] {
                running -= Decimal(volumes[i])
            }
            out[i] = running
        }
        return [IndicatorSeries(name: "OBV", values: out)]
    }
}
