// WP-41 第二批 · 结构类 4 真实指标 + 2 归属调整说明
// 真实：PivotPoints / ZigZag / Ichimoku / Fractal
// 归属调整：
//   · Andrew's Pitchfork → 归 WP-42 画线工具（本质是 3 点定义的画线叉，非纯算法指标）
//   · Elliott Wave → 不做（完整波浪识别是机器学习级别任务，TradingView 也仅提供画线辅助。Stage C 视用户呼声再评）
//
// WP-41 v3 第 14 批：PivotPoints 实现 IncrementalIndicator · 基于前一根 H/L/C 计算（无周期 · 7 列输出）
// WP-41 v3 第 16 批：Ichimoku 4/5 列部分增量 · 内嵌 3 Donchian + 2 延迟 ring · CHIKOU 永远 nil（用未来 close）· 41 指标 v3 系列收官

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

// MARK: - WP-41 v3 第 16 批 · Ichimoku 部分增量 API（内嵌 3 Donchian midBand + 2 延迟 ring · CHIKOU 永远 nil）

extension Ichimoku: IncrementalIndicator {

    /// state：内嵌 3 个 Donchian.IncrementalState（period tN/kN/sN · 取 row[1] mid 即 (HHV+LLV)/2 · 与 calculate midBand 等价）
    /// + 2 个延迟 ring（容量 kN · senkouARaw/senkouBRaw 前移 kN 根）+ kN 常量
    /// 输出 5 列 [TENKAN, KIJUN, SENKOU-A, SENKOU-B, CHIKOU]：
    ///   TENKAN = tenkanState 的 mid（同 Donchian mid）
    ///   KIJUN  = kijunState 的 mid
    ///   SENKOU-A = 延迟读取 ring · 写入 round8((tenkan+kijun)/2)（与 calculate senkouARaw[i] 一致）
    ///   SENKOU-B = 延迟读取 ring · 写入 senkouBState 的 mid
    ///   CHIKOU = 永远 nil（calculate chikou[i] = closes[i+kN] 用未来 close · 增量协议不支持）
    /// 验收说明：4/5 列与 calculate 精确一致 · CHIKOU 列在增量调用方需用其他途径补（或接受 nil）
    public struct IncrementalState: Sendable {
        public let kN: Int
        public var tenkanState: Donchian.IncrementalState
        public var kijunState: Donchian.IncrementalState
        public var senkouBState: Donchian.IncrementalState
        // 延迟 ring 容量 kN · Decimal? 因 senkouRaw 在 midBand warm-up 期可能 nil（与 calculate senkouARaw[i]=nil 一致）
        public var senkouADelayRing: [Decimal?]
        public var senkouADelayHead: Int
        public var senkouBDelayRing: [Decimal?]
        public var senkouBDelayHead: Int
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("Ichimoku 需要 3 参数（tenkan / kijun / senkou）")
        }
        let tN = intValue(params[0])
        let kN = intValue(params[1])
        let sN = intValue(params[2])
        guard tN >= 1, kN >= 1, sN >= 1 else {
            throw IndicatorError.invalidParameter("Ichimoku 参数非法 t=\(tN) k=\(kN) s=\(sN)")
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            kN: kN,
            tenkanState: try Donchian.makeIncrementalState(kline: empty, params: [Decimal(tN)]),
            kijunState: try Donchian.makeIncrementalState(kline: empty, params: [Decimal(kN)]),
            senkouBState: try Donchian.makeIncrementalState(kline: empty, params: [Decimal(sN)]),
            senkouADelayRing: [Decimal?](repeating: nil, count: kN),
            senkouADelayHead: 0,
            senkouBDelayRing: [Decimal?](repeating: nil, count: kN),
            senkouBDelayHead: 0
        )
        // history 循环：构造中转 KLine 调 processStep（Donchian.stepIncremental 接口要求 KLine · 仅 history 消化路径需构造 · stepIncremental 路径直接透传 newBar 零成本 · 同 Supertrend 模式）
        let countH = kline.highs.count
        for i in 0..<countH {
            let bar = KLine(
                instrumentID: "", period: .minute1,
                openTime: Date(timeIntervalSinceReferenceDate: 0),
                open: kline.opens[i], high: kline.highs[i], low: kline.lows[i], close: kline.closes[i],
                volume: kline.volumes[i], openInterest: 0, turnover: 0
            )
            _ = processStep(state: &state, bar: bar)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, bar: newBar)
    }

    /// 单步推进（makeIncrementalState 与 stepIncremental 共享）：
    /// 1. 推进 3 个 Donchian midBand · 取 row[1] mid 作 tenkan/kijun/senkouBRaw
    /// 2. senkouARaw = round8((tenkan+kijun)/2) · 仅 tenkan 和 kijun 都有值时有效（与 calculate 一致）
    /// 3. 延迟读取：先读 senkouADelayRing[head]（旧值 = senkouARaw[i-kN] · 即 senkouA[i]）· 再写入新 senkouARaw · head++
    ///    ring 满 kN 步前 ring[head] 是初始 nil（与 calculate `for i in 0..<kN: senkouA[i]=nil` 一致）
    /// 4. senkouB 同款延迟
    /// 5. CHIKOU 永远 nil（用未来 close · 增量协议不支持）
    private static func processStep(state: inout IncrementalState, bar: KLine) -> [Decimal?] {
        let tenkanRow = Donchian.stepIncremental(state: &state.tenkanState, newBar: bar)
        let kijunRow = Donchian.stepIncremental(state: &state.kijunState, newBar: bar)
        let senkouBRow = Donchian.stepIncremental(state: &state.senkouBState, newBar: bar)

        let tenkan = tenkanRow[1]   // mid（HHV+LLV)/2 · 已 round8）
        let kijun = kijunRow[1]
        let senkouBRaw = senkouBRow[1]

        let senkouARaw: Decimal?
        if let t = tenkan, let k = kijun {
            senkouARaw = Kernels.round8((t + k) / Decimal(2))
        } else {
            senkouARaw = nil
        }

        // 延迟 ring 读旧写新：先读 ring[head]（即将覆盖 = kN 步前的 raw）· 然后写入新 raw · head++
        let senkouA = state.senkouADelayRing[state.senkouADelayHead]
        state.senkouADelayRing[state.senkouADelayHead] = senkouARaw
        state.senkouADelayHead = (state.senkouADelayHead + 1) % state.kN

        let senkouB = state.senkouBDelayRing[state.senkouBDelayHead]
        state.senkouBDelayRing[state.senkouBDelayHead] = senkouBRaw
        state.senkouBDelayHead = (state.senkouBDelayHead + 1) % state.kN

        return [tenkan, kijun, senkouA, senkouB, nil]
    }
}
