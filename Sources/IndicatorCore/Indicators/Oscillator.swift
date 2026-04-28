// WP-41 第二批 · 震荡类 10 指标（除 RSI/MACD 已在独立文件）
// KDJ / Stochastic / CCI / W%R / ROC / TRIX / BIAS / PSY / DMI / CMO
//
// WP-41 v3 commit 1/4：KDJ 实现 IncrementalIndicator · O(n) per step（n=9 微秒级）
// WP-41 v3 commit 2/4：CCI 实现 IncrementalIndicator · ring buffer + sum + O(n) MD 重算
// WP-41 v3 第 2 批 commit 2/4：WilliamsR 实现 IncrementalIndicator · KDJ ring 简化版（无 SMA 平滑）

import Foundation
import Shared

// MARK: - KDJ · 9/3/3 经典参数

public enum KDJ: Indicator {
    public static let identifier = "KDJ"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 9, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "k", defaultValue: 3, minValue: 1, maxValue: 50),
        IndicatorParameter(name: "d", defaultValue: 3, minValue: 1, maxValue: 50)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let (n, kN, dN) = try Self.requireParams(params)
        let count = kline.count
        let hhv = Kernels.hhv(kline.highs, period: n)
        let llv = Kernels.llv(kline.lows, period: n)
        var rsv = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            if let h = hhv[i], let l = llv[i], h > l {
                rsv[i] = (kline.closes[i] - l) / (h - l) * Decimal(100)
            }
        }
        // K = SMA(RSV, kN, 1)：中国文华习惯的 (prev*(n-1)+x)/n 平滑（初值 50）
        var k = [Decimal?](repeating: nil, count: count)
        var d = [Decimal?](repeating: nil, count: count)
        var j = [Decimal?](repeating: nil, count: count)
        var prevK: Decimal = 50
        var prevD: Decimal = 50
        let kDec = Decimal(kN)
        let dDec = Decimal(dN)
        for i in 0..<count {
            guard hhv[i] != nil, llv[i] != nil else { continue }
            prevK = (prevK * Decimal(kN - 1) + rsv[i]) / kDec
            prevD = (prevD * Decimal(dN - 1) + prevK) / dDec
            let jv = Decimal(3) * prevK - Decimal(2) * prevD
            k[i] = Kernels.round8(prevK)
            d[i] = Kernels.round8(prevD)
            j[i] = Kernels.round8(jv)
        }
        return [
            IndicatorSeries(name: "K", values: k),
            IndicatorSeries(name: "D", values: d),
            IndicatorSeries(name: "J", values: j)
        ]
    }
}

// MARK: - Stochastic · %K / %D

public enum Stochastic: Indicator {
    public static let identifier = "STOCH"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "smooth", defaultValue: 3, minValue: 1, maxValue: 50)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Stochastic 需要 2 参数（period / smooth）")
        }
        let n = intValue(params[0])
        let s = intValue(params[1])
        let count = kline.count
        let hhv = Kernels.hhv(kline.highs, period: n)
        let llv = Kernels.llv(kline.lows, period: n)
        var kRaw = [Decimal](repeating: 0, count: count)
        var kValid = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let h = hhv[i], let l = llv[i], h > l {
                let v = (kline.closes[i] - l) / (h - l) * Decimal(100)
                kRaw[i] = v
                kValid[i] = Kernels.round8(v)
            }
        }
        let dSeries = Kernels.ma(kRaw, period: s)
        return [
            IndicatorSeries(name: "%K", values: kValid),
            IndicatorSeries(name: "%D", values: dSeries)
        ]
    }
}

// MARK: - CCI · 商品通道指数

public enum CCI: Indicator {
    public static let identifier = "CCI"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "CCI period")
        let count = kline.count
        var tp = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            tp[i] = (kline.highs[i] + kline.lows[i] + kline.closes[i]) / Decimal(3)
        }
        let tpMA = Kernels.ma(tp, period: n)
        let factor = Decimal(string: "0.015")!
        let nDec = Decimal(n)
        var out = [Decimal?](repeating: nil, count: count)
        for i in (n - 1)..<count {
            guard let ma = tpMA[i] else { continue }
            var md: Decimal = 0
            for j in (i - n + 1)...i { md += abs(tp[j] - ma) }
            md = md / nDec
            if md > 0 {
                out[i] = Kernels.round8((tp[i] - ma) / (factor * md))
            }
        }
        return [IndicatorSeries(name: "CCI(\(n))", values: out)]
    }
}

// MARK: - W%R · 威廉指标（范围 [-100, 0]）

public enum WilliamsR: Indicator {
    public static let identifier = "WR"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "WR period")
        let count = kline.count
        let hhv = Kernels.hhv(kline.highs, period: n)
        let llv = Kernels.llv(kline.lows, period: n)
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let h = hhv[i], let l = llv[i], h > l {
                out[i] = Kernels.round8((h - kline.closes[i]) / (h - l) * Decimal(-100))
            }
        }
        return [IndicatorSeries(name: "WR(\(n))", values: out)]
    }
}

// MARK: - ROC · 变动率 %

public enum ROC: Indicator {
    public static let identifier = "ROC"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 12, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "ROC period")
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        for i in n..<count {
            let past = kline.closes[i - n]
            if past != 0 {
                out[i] = Kernels.round8((kline.closes[i] - past) / past * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "ROC(\(n))", values: out)]
    }
}

// MARK: - TRIX · 三重平滑异同

public enum TRIX: Indicator {
    public static let identifier = "TRIX"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 12, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "TRIX period")
        let e1 = Kernels.ema(kline.closes, period: n)
        let e2 = Kernels.nextEMA(e1, period: n)
        let e3 = Kernels.nextEMA(e2, period: n)
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            if let cur = e3[i], let prev = e3[i - 1], prev != 0 {
                out[i] = Kernels.round8((cur - prev) / prev * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "TRIX(\(n))", values: out)]
    }
}

// MARK: - BIAS · 乖离率 %

public enum BIAS: Indicator {
    public static let identifier = "BIAS"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 6, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "BIAS period")
        let ma = Kernels.ma(kline.closes, period: n)
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = ma[i], m != 0 {
                out[i] = Kernels.round8((kline.closes[i] - m) / m * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "BIAS(\(n))", values: out)]
    }
}

// MARK: - PSY · 心理线 %（N 周期上涨根数占比）

public enum PSY: Indicator {
    public static let identifier = "PSY"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 12, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "PSY period")
        let count = kline.count
        var ups = [Decimal](repeating: 0, count: count)
        for i in 1..<count where kline.closes[i] > kline.closes[i - 1] {
            ups[i] = 1
        }
        let sums = Kernels.slidingSum(ups, period: n)
        let nDec = Decimal(n)
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let s = sums[i] {
                out[i] = Kernels.round8(s / nDec * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "PSY(\(n))", values: out)]
    }
}

// MARK: - DMI · +DI / -DI（复用 ADX 内部，输出 2 线；ADX 额外有独立指标）

public enum DMI: Indicator {
    public static let identifier = "DMI"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let adxSeries = try ADX.calculate(kline: kline, params: params)
        // ADX 输出 [ADX, +DI, -DI]；DMI 只取后两条
        return [adxSeries[1], adxSeries[2]]
    }
}

// MARK: - CMO · Chande 动量振荡器

public enum CMO: Indicator {
    public static let identifier = "CMO"
    public static let category: IndicatorCategory = .oscillator
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "CMO period")
        let count = kline.count
        var up = [Decimal](repeating: 0, count: count)
        var dn = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            let d = kline.closes[i] - kline.closes[i - 1]
            if d > 0 { up[i] = d }
            else if d < 0 { dn[i] = -d }
        }
        // CMO 原始要求第一条差分（i=1）不计入起始窗口，故从 i=n 开始（= 种子窗口 [1...n]）
        let upSums = Kernels.slidingSum(up, period: n)
        let dnSums = Kernels.slidingSum(dn, period: n)
        var out = [Decimal?](repeating: nil, count: count)
        for i in n..<count {
            guard let su = upSums[i], let sd = dnSums[i] else { continue }
            let total = su + sd
            if total > 0 {
                out[i] = Kernels.round8((su - sd) / total * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "CMO(\(n))", values: out)]
    }
}

// MARK: - WP-41 v3 commit 1/4 · KDJ 增量 API

extension KDJ: IncrementalIndicator {

    /// state：n/k/d 三参数 + (high/low) ring buffer · prevK/prevD 流式 SMA 平滑（不 round8 状态 · 输出 round8）
    /// HHV/LLV 用环形 buffer + 每步 O(n) 重新扫描 max/min（n=9 实际 < 1µs · 远低于全量 O(N×n)）
    /// 之所以不用 monotonic deque：n 太小（典型 9）· 实测 ring 扫描比 deque 簿记开销低 · 简单优于复杂
    public struct IncrementalState: Sendable {
        public let period: Int
        public let kN: Int
        public let dN: Int
        public let kNDec: Decimal
        public let dNDec: Decimal
        public let kNMinus1: Decimal
        public let dNMinus1: Decimal
        public var highRing: [Decimal]
        public var lowRing: [Decimal]
        public var head: Int
        public var count: Int
        public var prevK: Decimal
        public var prevD: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let (n, kN, dN) = try Self.requireParams(params)
        var state = IncrementalState(
            period: n, kN: kN, dN: dN,
            kNDec: Decimal(kN), dNDec: Decimal(dN),
            kNMinus1: Decimal(kN - 1), dNMinus1: Decimal(dN - 1),
            highRing: [Decimal](repeating: 0, count: n),
            lowRing: [Decimal](repeating: 0, count: n),
            head: 0, count: 0,
            prevK: 50, prevD: 50
        )
        // 模拟 step 扫描 history（包括 ring 写入与平滑 · 与 calculate 算法一致）
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)
    }

    /// makeIncrementalState 与 stepIncremental 共享的核心：
    /// - ring 写入（满则覆盖最旧 · O(1)）
    /// - count < period：返回全 nil（warm-up · 与 calculate 中 hhv/llv == nil 阶段一致 · prev*K/D 保持 50）
    /// - count >= period：扫描 ring 求 hhv/llv（O(n)）→ RSV → SMA 平滑 prevK/prevD → J = 3K - 2D
    /// - hhv == llv 时 rsv = 0（与 calculate 中 rsv[i] 默认初值 0 语义一致）
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> [Decimal?] {
        state.highRing[state.head] = high
        state.lowRing[state.head] = low
        state.head = (state.head + 1) % state.period
        state.count = min(state.count + 1, state.period)

        guard state.count == state.period else { return [nil, nil, nil] }

        var hhv = state.highRing[0]
        var llv = state.lowRing[0]
        for i in 1..<state.period {
            if state.highRing[i] > hhv { hhv = state.highRing[i] }
            if state.lowRing[i] < llv { llv = state.lowRing[i] }
        }

        let rsv: Decimal = hhv > llv
            ? (close - llv) / (hhv - llv) * Decimal(100)
            : 0
        state.prevK = (state.prevK * state.kNMinus1 + rsv) / state.kNDec
        state.prevD = (state.prevD * state.dNMinus1 + state.prevK) / state.dNDec
        let jv = Decimal(3) * state.prevK - Decimal(2) * state.prevD
        return [
            Kernels.round8(state.prevK),
            Kernels.round8(state.prevD),
            Kernels.round8(jv)
        ]
    }

    /// 共享参数校验（calculate / makeIncrementalState 都用）
    fileprivate static func requireParams(_ params: [Decimal]) throws -> (n: Int, kN: Int, dN: Int) {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("KDJ 需要 3 参数（period / k / d）")
        }
        let n = intValue(params[0])
        let kN = intValue(params[1])
        let dN = intValue(params[2])
        guard n >= 1, kN >= 1, dN >= 1 else {
            throw IndicatorError.invalidParameter("KDJ 参数非法 n=\(n) k=\(kN) d=\(dN)")
        }
        return (n, kN, dN)
    }
}

// MARK: - WP-41 v3 commit 2/4 · CCI 增量 API

extension CCI: IncrementalIndicator {

    /// state：period + factor 0.015 + TP ring buffer + sum（滑窗均值用）
    /// MD（mean absolute deviation）每步 O(n) 重算 · 因为 TP_MA 每步变 · |TP[j] - TP_MA| 项也变
    /// 不预存 |TP - MA| 累加（增量更新代价 ≈ O(n) 不省）· 直接遍历 ring 算 mdSum 最直接
    public struct IncrementalState: Sendable {
        public let period: Int
        public let nDec: Decimal
        public let factor: Decimal   // 0.015 · 与 calculate 同
        public var tpRing: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "CCI period")
        var state = IncrementalState(
            period: n, nDec: Decimal(n),
            factor: Decimal(string: "0.015")!,
            tpRing: [Decimal](repeating: 0, count: n),
            head: 0, count: 0, sum: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)]
    }

    /// makeIncrementalState 与 stepIncremental 共享的核心：
    /// - 计算 TP = (H+L+C)/3 · 写入 ring 滑窗（同 MA 模式 · 满则 sum -= 旧值）
    /// - count < period：返回 nil（warm-up · 与 calculate 中 i < n-1 阶段一致）
    /// - count >= period：ma = sum/n · mdSum = Σ|tp_ring - ma|（O(n)）· md = mdSum/n
    /// - md == 0 时返回 nil（与 calculate 中 md > 0 才输出 一致 · 全平时 nil）
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> Decimal? {
        let tp = (high + low + close) / Decimal(3)
        if state.count == state.period {
            state.sum -= state.tpRing[state.head]
        } else {
            state.count += 1
        }
        state.tpRing[state.head] = tp
        state.head = (state.head + 1) % state.period
        state.sum += tp

        guard state.count == state.period else { return nil }

        let ma = state.sum / state.nDec
        var mdSum: Decimal = 0
        for v in state.tpRing { mdSum += abs(v - ma) }
        let md = mdSum / state.nDec
        guard md > 0 else { return nil }
        return Kernels.round8((tp - ma) / (state.factor * md))
    }
}

// MARK: - WP-41 v3 第 2 批 commit 2/4 · WilliamsR 增量 API（KDJ ring 简化版 · 无平滑）

extension WilliamsR: IncrementalIndicator {

    /// state：period + (high/low) ring buffer · 无平滑（与 KDJ 共用 ring 模式 · 但少 prevK/prevD 流式状态）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var highRing: [Decimal]
        public var lowRing: [Decimal]
        public var head: Int
        public var count: Int
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "WR period")
        var state = IncrementalState(
            period: n,
            highRing: [Decimal](repeating: 0, count: n),
            lowRing: [Decimal](repeating: 0, count: n),
            head: 0, count: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)]
    }

    /// makeIncrementalState 与 stepIncremental 共享：
    /// - ring 写入 O(1) · count < period → nil（warm-up）
    /// - count == period：扫 ring 求 hhv/llv（O(n)）· hhv > llv 时 WR = (hhv - close)/(hhv - llv) * -100
    /// - hhv == llv 时返回 nil（与 calculate 中 h > l 守卫一致 · 全平 high/low 时无意义）
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> Decimal? {
        state.highRing[state.head] = high
        state.lowRing[state.head] = low
        state.head = (state.head + 1) % state.period
        state.count = min(state.count + 1, state.period)

        guard state.count == state.period else { return nil }

        var hhv = state.highRing[0]
        var llv = state.lowRing[0]
        for i in 1..<state.period {
            if state.highRing[i] > hhv { hhv = state.highRing[i] }
            if state.lowRing[i] < llv { llv = state.lowRing[i] }
        }

        guard hhv > llv else { return nil }
        return Kernels.round8((hhv - close) / (hhv - llv) * Decimal(-100))
    }
}
