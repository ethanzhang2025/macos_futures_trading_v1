// WP-41 第二批 · 结构类 4 真实指标 + 2 归属调整说明
// 真实：PivotPoints / ZigZag / Ichimoku / Fractal
// 归属调整：
//   · Andrew's Pitchfork → 归 WP-42 画线工具（本质是 3 点定义的画线叉，非纯算法指标）
//   · Elliott Wave → 不做（完整波浪识别是机器学习级别任务，TradingView 也仅提供画线辅助。Stage C 视用户呼声再评）
//
// WP-41 v3 第 14 批：PivotPoints 实现 IncrementalIndicator · 基于前一根 H/L/C 计算（无周期 · 7 列输出）

import Foundation
import Shared

// MARK: - PivotPoints · 经典枢轴点
// 每根 K 线基于前一根的 H/L/C 计算当日 P/R1/S1/R2/S2/R3/S3

public enum PivotPoints: Indicator {
    public static let identifier = "PIVOT"
    public static let category: IndicatorCategory = .structure
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var p = [Decimal?](repeating: nil, count: count)
        var r1 = [Decimal?](repeating: nil, count: count)
        var s1 = [Decimal?](repeating: nil, count: count)
        var r2 = [Decimal?](repeating: nil, count: count)
        var s2 = [Decimal?](repeating: nil, count: count)
        var r3 = [Decimal?](repeating: nil, count: count)
        var s3 = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let h = kline.highs[i - 1]
            let l = kline.lows[i - 1]
            let c = kline.closes[i - 1]
            let pivot = (h + l + c) / Decimal(3)
            p[i] = Kernels.round8(pivot)
            r1[i] = Kernels.round8(Decimal(2) * pivot - l)
            s1[i] = Kernels.round8(Decimal(2) * pivot - h)
            r2[i] = Kernels.round8(pivot + (h - l))
            s2[i] = Kernels.round8(pivot - (h - l))
            r3[i] = Kernels.round8(h + Decimal(2) * (pivot - l))
            s3[i] = Kernels.round8(l - Decimal(2) * (h - pivot))
        }
        return [
            IndicatorSeries(name: "P", values: p),
            IndicatorSeries(name: "R1", values: r1),
            IndicatorSeries(name: "S1", values: s1),
            IndicatorSeries(name: "R2", values: r2),
            IndicatorSeries(name: "S2", values: s2),
            IndicatorSeries(name: "R3", values: r3),
            IndicatorSeries(name: "S3", values: s3)
        ]
    }
}

// MARK: - ZigZag · 之字转向
// 参数：percent 阈值（默认 5%）
// 算法：从起点追踪极端点（peak/trough），反向幅度超过阈值时标记前一极端为新转点

public enum ZigZag: Indicator {
    public static let identifier = "ZIGZAG"
    public static let category: IndicatorCategory = .structure
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "percent", defaultValue: 5, minValue: Decimal(string: "0.1")!, maxValue: 50)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard let first = params.first else {
            throw IndicatorError.invalidParameter("ZigZag 需要 percent 参数")
        }
        let threshold = first / Decimal(100)  // 5 → 0.05
        guard threshold > 0 else {
            throw IndicatorError.invalidParameter("ZigZag percent 必须 > 0")
        }
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        guard count >= 2 else { return [IndicatorSeries(name: "ZIGZAG", values: out)] }

        // 起点用 close[0] 作为候选
        var lastPivotIdx = 0
        var lastPivotPrice = kline.closes[0]
        var dir: Int = 0  // 1 up, -1 down, 0 undetermined
        out[0] = Kernels.round8(lastPivotPrice)

        for i in 1..<count {
            let p = kline.closes[i]
            let changeFromLast = (p - lastPivotPrice) / lastPivotPrice
            if dir == 0 {
                if changeFromLast >= threshold {
                    dir = 1; lastPivotIdx = i; lastPivotPrice = p
                } else if changeFromLast <= -threshold {
                    dir = -1; lastPivotIdx = i; lastPivotPrice = p
                }
            } else if dir == 1 {
                if p >= lastPivotPrice {
                    lastPivotIdx = i; lastPivotPrice = p
                } else if (lastPivotPrice - p) / lastPivotPrice >= threshold {
                    // 反转下跌
                    out[lastPivotIdx] = Kernels.round8(lastPivotPrice)
                    dir = -1; lastPivotIdx = i; lastPivotPrice = p
                }
            } else { // dir == -1
                if p <= lastPivotPrice {
                    lastPivotIdx = i; lastPivotPrice = p
                } else if (p - lastPivotPrice) / lastPivotPrice >= threshold {
                    out[lastPivotIdx] = Kernels.round8(lastPivotPrice)
                    dir = 1; lastPivotIdx = i; lastPivotPrice = p
                }
            }
        }
        // 最后一个极端点也标记
        out[lastPivotIdx] = Kernels.round8(lastPivotPrice)
        return [IndicatorSeries(name: "ZIGZAG", values: out)]
    }
}

// MARK: - Ichimoku · 一目均衡表 5 线
// 参数：tenkan(9) / kijun(26) / senkou(52)；A/B 前移 kijun 根，Chikou 后移 kijun 根

public enum Ichimoku: Indicator {
    public static let identifier = "ICHIMOKU"
    public static let category: IndicatorCategory = .structure
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "tenkan", defaultValue: 9, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "kijun", defaultValue: 26, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "senkou", defaultValue: 52, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("Ichimoku 需要 3 参数")
        }
        let tN = intValue(params[0])
        let kN = intValue(params[1])
        let sN = intValue(params[2])
        let count = kline.count
        let tenkan = midBand(highs: kline.highs, lows: kline.lows, period: tN)
        let kijun = midBand(highs: kline.highs, lows: kline.lows, period: kN)
        let senkouBRaw = midBand(highs: kline.highs, lows: kline.lows, period: sN)

        // Senkou A = (Tenkan + Kijun) / 2，前移 kN 根
        var senkouARaw = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let t = tenkan[i], let k = kijun[i] {
                senkouARaw[i] = Kernels.round8((t + k) / Decimal(2))
            }
        }
        let senkouA = shiftForward(senkouARaw, by: kN, length: count)
        let senkouB = shiftForward(senkouBRaw, by: kN, length: count)
        // Chikou = close，后移 kN 根
        let chikou = shiftBackward(kline.closes.map { Optional($0) }, by: kN, length: count)
        return [
            IndicatorSeries(name: "TENKAN", values: tenkan),
            IndicatorSeries(name: "KIJUN", values: kijun),
            IndicatorSeries(name: "SENKOU-A", values: senkouA),
            IndicatorSeries(name: "SENKOU-B", values: senkouB),
            IndicatorSeries(name: "CHIKOU", values: chikou)
        ]
    }

    /// (HHV + LLV) / 2
    private static func midBand(highs: [Decimal], lows: [Decimal], period: Int) -> [Decimal?] {
        let hh = Kernels.hhv(highs, period: period)
        let ll = Kernels.llv(lows, period: period)
        return zip(hh, ll).map { h, l in
            guard let h, let l else { return nil }
            return Kernels.round8((h + l) / Decimal(2))
        }
    }

    /// 前移（向未来）：index i 的值来自 index i-n
    private static func shiftForward(_ xs: [Decimal?], by n: Int, length: Int) -> [Decimal?] {
        var out = [Decimal?](repeating: nil, count: length)
        for i in 0..<length where i - n >= 0 { out[i] = xs[i - n] }
        return out
    }

    /// 后移（向过去）：index i 的值来自 index i+n
    private static func shiftBackward(_ xs: [Decimal?], by n: Int, length: Int) -> [Decimal?] {
        var out = [Decimal?](repeating: nil, count: length)
        for i in 0..<length where i + n < length { out[i] = xs[i + n] }
        return out
    }
}

// MARK: - Fractal · Bill Williams 5 根 K 线分形

public enum Fractal: Indicator {
    public static let identifier = "FRACTAL"
    public static let category: IndicatorCategory = .structure
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var up = [Decimal?](repeating: nil, count: count)
        var down = [Decimal?](repeating: nil, count: count)
        // 分形需要中心 i 的前后各 2 根
        for i in 2..<(count - 2) {
            let h = kline.highs[i]
            if h > kline.highs[i - 1] && h > kline.highs[i - 2]
               && h > kline.highs[i + 1] && h > kline.highs[i + 2] {
                up[i] = h
            }
            let l = kline.lows[i]
            if l < kline.lows[i - 1] && l < kline.lows[i - 2]
               && l < kline.lows[i + 1] && l < kline.lows[i + 2] {
                down[i] = l
            }
        }
        return [
            IndicatorSeries(name: "FRACTAL-UP", values: up),
            IndicatorSeries(name: "FRACTAL-DOWN", values: down)
        ]
    }
}

// MARK: - WP-41 v3 第 14 批 · PivotPoints 增量 API（基于前一根 H/L/C 计算 · 同 PVT prevClose 模式扩展到 3 字段 · 7 列输出）

extension PivotPoints: IncrementalIndicator {

    /// state：prevH / prevL / prevC（3 个 Optional · 第 1 根 nil → 全 nil · 同 calculate `for i in 1..<count` 跳第 1 根）
    /// 输出 7 列：[P, R1, S1, R2, S2, R3, S3] · 与 calculate IndicatorSeries 顺序一致
    public struct IncrementalState: Sendable {
        public var prevH: Decimal?
        public var prevL: Decimal?
        public var prevC: Decimal?
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(prevH: nil, prevL: nil, prevC: nil)
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)
    }

    /// 第 1 根：state 都 nil → 输出全 nil（与 calculate 第 1 根不计算一致）· 之后 prev = (high, low, close)
    /// 第 2 根起：用 prev H/L/C 算 pivot · 输出 7 列 round8 · 之后 prev 更新为当前 (high, low, close)
    /// pivot = (h+l+c)/3 · R1 = 2P-l · S1 = 2P-h · R2 = P+(h-l) · S2 = P-(h-l) · R3 = h+2(P-l) · S3 = l-2(h-P)
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> [Decimal?] {
        defer {
            state.prevH = high
            state.prevL = low
            state.prevC = close
        }
        guard let h = state.prevH, let l = state.prevL, let c = state.prevC else {
            return [nil, nil, nil, nil, nil, nil, nil]
        }
        let pivot = (h + l + c) / Decimal(3)
        return [
            Kernels.round8(pivot),
            Kernels.round8(Decimal(2) * pivot - l),
            Kernels.round8(Decimal(2) * pivot - h),
            Kernels.round8(pivot + (h - l)),
            Kernels.round8(pivot - (h - l)),
            Kernels.round8(h + Decimal(2) * (pivot - l)),
            Kernels.round8(l - Decimal(2) * (h - pivot))
        ]
    }
}
