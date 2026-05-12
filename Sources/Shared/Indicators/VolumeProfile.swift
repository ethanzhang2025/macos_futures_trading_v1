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

// MARK: - v17.63 · VP 模式（TradingView Visible Range / Session / Fixed Range）

/// Volume Profile 计算范围模式
public enum VolumeProfileMode: String, Sendable, Codable, CaseIterable {
    /// 全量 bars（默认 · 长期价格分布 · 与 v17.31 一致）
    case fullRange
    /// Visible Range · 仅当前视口可见 bars（trader 局部分析）
    case visibleRange
    /// Session · 最近 1 个交易日 bars（近似按周期估算 bar 数）
    case session
    /// Fixed Range · 用户指定 bar 范围（startIndex / endIndex）
    case fixedRange

    public var displayName: String {
        switch self {
        case .fullRange:    return "全量 Full"
        case .visibleRange: return "可见 Visible"
        case .session:      return "本交易日 Session"
        case .fixedRange:   return "区间 Fixed"
        }
    }
}

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

    /// v17.63 · 按模式切分 bars 后计算 VP（TradingView 4 模式对齐）
    /// - Parameters:
    ///   - bars: 全量 bars（数据源 · 由调用方提供）
    ///   - mode: 模式（fullRange / visibleRange / session / fixedRange）
    ///   - visibleRange: visibleRange 模式需要的可见区间（startIndex, endIndex 闭区间 · half-open 风格）
    ///   - sessionBarCount: session 模式取最后 N 根 bars（默认 240 · 1m × 240 ≈ 4h 交易日近似）
    ///   - fixedRange: fixedRange 模式的 (startIndex, endIndex) · 与 visibleRange 同义
    ///   - binCount: 价格分桶数（默认 24）
    public static func compute(
        bars: [KLine],
        mode: VolumeProfileMode,
        visibleRange: (start: Int, end: Int)? = nil,
        sessionBarCount: Int = 240,
        fixedRange: (start: Int, end: Int)? = nil,
        binCount: Int = 24
    ) -> [Bin] {
        let slice: [KLine]
        switch mode {
        case .fullRange:
            slice = bars
        case .visibleRange:
            if let r = visibleRange {
                let s = max(0, min(bars.count, r.start))
                let e = max(s, min(bars.count, r.end))
                slice = Array(bars[s..<e])
            } else {
                slice = bars
            }
        case .session:
            let n = min(bars.count, max(1, sessionBarCount))
            slice = Array(bars.suffix(n))
        case .fixedRange:
            if let r = fixedRange {
                let s = max(0, min(bars.count, r.start))
                let e = max(s, min(bars.count, r.end))
                slice = Array(bars[s..<e])
            } else {
                slice = bars
            }
        }
        return compute(bars: slice, binCount: binCount)
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

    /// v17.30 B2 · Value Area · POC 起步向两侧贪心扩展到累计成交量 ≥ percent 阈值
    /// 经典 trader 70% 区 = 多数交易者认可的价格带 · 突破即被市场重新定价
    public struct ValueArea: Sendable, Equatable {
        public let pocIndex: Int        // POC bin 下标（成交量峰值）
        public let vahIndex: Int        // Value Area High 上沿 bin 下标
        public let valIndex: Int        // Value Area Low 下沿 bin 下标
        public let pocPrice: Decimal    // POC bin 中价
        public let vahPrice: Decimal    // VAH bin 上沿
        public let valPrice: Decimal    // VAL bin 下沿
        public let coveredVolume: Double
        public let totalVolume: Double

        public init(pocIndex: Int, vahIndex: Int, valIndex: Int,
                    pocPrice: Decimal, vahPrice: Decimal, valPrice: Decimal,
                    coveredVolume: Double, totalVolume: Double) {
            self.pocIndex = pocIndex
            self.vahIndex = vahIndex
            self.valIndex = valIndex
            self.pocPrice = pocPrice
            self.vahPrice = vahPrice
            self.valPrice = valPrice
            self.coveredVolume = coveredVolume
            self.totalVolume = totalVolume
        }
    }

    /// 计算 Value Area · bins 按价格升序（compute 输出）· percent 默认 0.7（70% · TradingView 默认）
    /// 算法：从 POC 起 · 比较上下相邻两 bin · 取 volume 大者纳入 · 重复直到 ≥ 阈值
    /// 单 bin / 空 bins / percent ≤ 0 → nil
    public static func valueArea(bins: [Bin], percent: Double = 0.7) -> ValueArea? {
        guard !bins.isEmpty, percent > 0 else { return nil }
        let total = bins.reduce(0) { $0 + $1.volume }
        guard total > 0 else { return nil }
        let target = total * min(1.0, percent)

        guard let pocIdx = bins.indices.max(by: { bins[$0].volume < bins[$1].volume }) else {
            return nil
        }
        var lowIdx = pocIdx
        var highIdx = pocIdx
        var covered = bins[pocIdx].volume

        while covered < target {
            let canExpandUp = highIdx < bins.count - 1
            let canExpandDown = lowIdx > 0
            if !canExpandUp && !canExpandDown { break }
            if canExpandUp && (!canExpandDown || bins[highIdx + 1].volume >= bins[lowIdx - 1].volume) {
                highIdx += 1
                covered += bins[highIdx].volume
            } else {
                lowIdx -= 1
                covered += bins[lowIdx].volume
            }
        }

        return ValueArea(
            pocIndex: pocIdx,
            vahIndex: highIdx,
            valIndex: lowIdx,
            pocPrice: bins[pocIdx].priceCenter,
            vahPrice: bins[highIdx].priceHigh,
            valPrice: bins[lowIdx].priceLow,
            coveredVolume: covered,
            totalVolume: total
        )
    }
}
