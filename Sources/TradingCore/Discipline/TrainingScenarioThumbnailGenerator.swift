// WP-54 v15.23 batch115 · 训练场景 K 线 thumbnail 数据生成器（跨平台 · Linux 可测）
//
// 用途：根据 TrainingScenarioPattern + seed 生成 ~60 根 OHLC 模拟 K 线
// trader 在选场景前一眼看懂走势特征 · 决定要不要练
//
// 设计：
// - 完全确定性（同 pattern + seed → 完全相同输出）· 测试可断言
// - 不依赖真实历史数据 · 形态化合成 · 视觉清晰度优于"真实"
// - 价格基线 100 + pattern 形态曲线 + 每根小幅 noise · OHLC 自洽（high≥max(o,c) low≤min(o,c)）

import Foundation

/// 简易 OHLC bar（thumbnail 内部用 · 不含 volume / time）
public struct TrainingThumbnailBar: Sendable, Equatable {
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(open: Double, high: Double, low: Double, close: Double) {
        self.open = open; self.high = high; self.low = low; self.close = close
    }

    public var isUp: Bool { close >= open }
}

/// 训练场景 thumbnail 数据生成器（无 UI 依赖 · TradingCore 跨平台）
public enum TrainingScenarioThumbnailGenerator {

    /// 默认 60 根 bar · 形态视觉清晰 · cell ≈ 60×40pt
    public static let defaultBarCount: Int = 60

    /// 生成形态对应的 bars · seed 控制 noise（同 pattern 不同 seed 视觉细节略不同）
    public static func bars(for pattern: TrainingScenarioPattern,
                            seed: UInt64 = 0xC0FFEE,
                            count: Int = defaultBarCount) -> [TrainingThumbnailBar] {
        guard count > 0 else { return [] }
        var rng = SeededPRNG(seed: seed)
        var bars: [TrainingThumbnailBar] = []
        bars.reserveCapacity(count)
        let n = max(2, count)
        for i in 0..<count {
            let p1 = Double(i) / Double(n - 1)
            let p2 = Double(min(i + 1, n - 1)) / Double(n - 1)
            let baseOpen = patternBasePrice(pattern, progress: p1)
            let baseClose = patternBasePrice(pattern, progress: p2)
            // noise 振幅按形态调整（极端形态保留更多干净走势 · 震荡形态加更多 noise 看起来真实）
            let noise = patternNoise(pattern)
            let open  = baseOpen  + (rng.nextSymmetric() * noise)
            let close = baseClose + (rng.nextSymmetric() * noise)
            let span  = abs(rng.nextSymmetric()) * noise * 0.8 + noise * 0.3
            let high  = max(open, close) + span
            let low   = min(open, close) - span
            bars.append(TrainingThumbnailBar(open: open, high: high, low: low, close: close))
        }
        return bars
    }

    /// 形态基线价格曲线（progress ∈ [0,1] · 输出价格 · base 100 ± delta）
    static func patternBasePrice(_ pattern: TrainingScenarioPattern, progress p: Double) -> Double {
        let p = max(0, min(1, p))
        switch pattern {
        case .oscillation:
            // 2.5 个完整 sin 周期 · 振幅 ±8
            return 100 + 8 * sin(p * 5 * .pi)
        case .uptrend:
            // 线性 +30 · 末段加速
            return 100 + 30 * (p * 0.7 + p * p * 0.3)
        case .downtrend:
            return 100 - 30 * (p * 0.7 + p * p * 0.3)
        case .vReversal:
            // 先 -25 再 +25 · 谷底在 progress=0.5
            return 100 - 25 * (1 - 2 * abs(p - 0.5))
        case .breakout:
            // 60% 横盘震荡 · 后 40% 单边突破 +25
            if p < 0.6 { return 100 + 3 * sin(p * 8 * .pi) }
            return 100 + 25 * ((p - 0.6) / 0.4)
        case .fakeBreakout:
            // 40% 横盘 + 15% 假突破 + 15% 跌回 + 30% 真突破
            if p < 0.4 { return 100 + 2 * sin(p * 8 * .pi) }
            else if p < 0.55 { return 100 + 15 * ((p - 0.4) / 0.15) }       // 假突破至 115
            else if p < 0.7  { return 115 - 14 * ((p - 0.55) / 0.15) }      // 跌回 101
            else             { return 101 + 28 * ((p - 0.7) / 0.3) }        // 真突破至 129
        case .gapAndHalt:
            // 30% 平稳 · 跳空 -15 · 后段急跌 -15
            if p < 0.3 { return 100 + 2 * sin(p * 6 * .pi) }
            else if p < 0.32 { return 100 - 15 * ((p - 0.3) / 0.02) }       // 跳空一根
            else { return 85 - 15 * ((p - 0.32) / 0.68) }                   // 持续阴跌
        case .nightRally:
            // 70% 平稳 · 后 30% 急拉 +25
            if p < 0.7 { return 100 + 1.5 * sin(p * 6 * .pi) }
            return 100 + 25 * ((p - 0.7) / 0.3)
        case .multiPhase:
            // 4 段：震荡 → 突破 → 趋势 → 反转
            if p < 0.25      { return 100 + 5 * sin(p * 16 * .pi) }
            else if p < 0.5  { return 100 + 12 * ((p - 0.25) / 0.25) }      // 突破至 112
            else if p < 0.75 { return 112 + 18 * ((p - 0.5) / 0.25) }       // 趋势至 130
            else             { return 130 - 25 * ((p - 0.75) / 0.25) }      // 反转至 105
        }
    }

    /// 形态对应的 noise 振幅
    static func patternNoise(_ pattern: TrainingScenarioPattern) -> Double {
        switch pattern {
        case .oscillation:    return 0.8
        case .uptrend:        return 0.6
        case .downtrend:      return 0.6
        case .vReversal:      return 0.7
        case .breakout:       return 0.5
        case .fakeBreakout:   return 0.7
        case .gapAndHalt:     return 1.2
        case .nightRally:     return 0.6
        case .multiPhase:     return 0.6
        }
    }
}

/// 极简线性同余 PRNG（确定性 · 跨平台一致 · 不用 Swift Random 避免不同版本差异）
struct SeededPRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed }

    /// [0, 1) 均匀分布
    mutating func nextDouble() -> Double {
        // splitmix64 步进
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        // 取高 53 位作为 [0, 1) double
        return Double(z >> 11) / Double(1 << 53)
    }

    /// [-1, 1) 对称分布
    mutating func nextSymmetric() -> Double { nextDouble() * 2 - 1 }
}
