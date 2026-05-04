// v15.19 batch25 · Volume Profile（成交量分布 · trader 找支撑阻力区经典工具）
//
// 设计取舍：
// - 不走 Indicator 协议（不符合"按时序输出 IndicatorSeries"模型 · 输出按价格 bin）
// - 纯函数 · 可独立测试 · UI 副图直接调用
// - 输入 visible bars · 用户调节 bin 数（默认 24）
// - 单根 K 线的 volume 平均分配到 [low, high] 价格区间内（O(bins) 每根）
//
// 输出：[(priceLow, priceHigh, volume)] · 按价格升序
// 解读：
// - 高 volume bin = 成交密集区 = 支撑/阻力
// - 低 volume bin = 缺口区 = 价格易快速穿过

import Foundation

public enum VolumeProfile {

    public struct Bin: Sendable, Equatable {
        public let priceLow: Decimal
        public let priceHigh: Decimal
        public let volume: Double      // 累计成交量（Int → Double 防溢出 + 与渲染层一致）
        public init(priceLow: Decimal, priceHigh: Decimal, volume: Double) {
            self.priceLow = priceLow
            self.priceHigh = priceHigh
            self.volume = volume
        }

        public var priceCenter: Decimal {
            (priceLow + priceHigh) / Decimal(2)
        }
    }

    /// 计算 Volume Profile
    /// - Parameters:
    ///   - bars: 输入 K 线（通常是 visible 范围）
    ///   - binCount: 价格分桶数（默认 24 · 范围 [4, 200]）
    /// - Returns: 按价格升序排列的 bin · 空数据返回 []
    public static func compute(bars: [KLine], binCount: Int = 24) -> [Bin] {
        guard !bars.isEmpty else { return [] }
        let n = max(4, min(200, binCount))
        // 价格范围 = visible bars 中的 [min(low), max(high)]
        guard let lo = bars.map(\.low).min(), let hi = bars.map(\.high).max(), hi > lo else {
            // 单一价格 · 全部 volume 落入一个 bin
            let volSum = bars.reduce(0) { $0 + Double($1.volume) }
            let p = bars.first!.low
            return [Bin(priceLow: p, priceHigh: p, volume: volSum)]
        }
        let loD = NSDecimalNumber(decimal: lo).doubleValue
        let hiD = NSDecimalNumber(decimal: hi).doubleValue
        let span = hiD - loD
        let binWidth = span / Double(n)
        var volumes = [Double](repeating: 0, count: n)
        for bar in bars {
            let bLow = NSDecimalNumber(decimal: bar.low).doubleValue
            let bHigh = NSDecimalNumber(decimal: bar.high).doubleValue
            let bVol = Double(bar.volume)
            // 计算本根 K 线覆盖的 bin 起止
            let startIdx = max(0, min(n - 1, Int((bLow - loD) / binWidth)))
            let endIdx = max(0, min(n - 1, Int((bHigh - loD) / binWidth)))
            let touched = endIdx - startIdx + 1
            // 平均分配到覆盖的 bin（简化模型 · trader 经验 high/low 区间内成交基本均匀）
            let perBin = bVol / Double(touched)
            for i in startIdx...endIdx { volumes[i] += perBin }
        }
        return (0..<n).map { i in
            let pLow = loD + Double(i) * binWidth
            let pHigh = pLow + binWidth
            return Bin(
                priceLow: Decimal(pLow),
                priceHigh: Decimal(pHigh),
                volume: volumes[i]
            )
        }
    }
}
