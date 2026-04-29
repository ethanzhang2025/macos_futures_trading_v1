// WP-41 第二批 · 波动率/通道类 6 指标（除 BOLL/ATR 已在独立文件）
// KC / Donchian / StdDev / HV / PriceChannel / Envelopes
//
// WP-41 v3 第 9 批：Donchian 实现 IncrementalIndicator · 双 ring HHV/LLV（同 KDJ ring 模式）
// WP-41 v3 第 10 批：KC + StdDev + Envelopes 增量 API（内嵌 EMA+ATR / BOLL 简化 / MA 复合 · 28 指标）
// WP-41 v3 第 11 批：PriceChannel + HV 增量 API（Donchian close 单 ring / log 收益 + ring StdDev + annual scaling · Volatility.swift 6/6 100% 收官 · 30 指标）

import Foundation
import Shared

// MARK: - KC · 肯特纳通道 EMA ± mult * ATR

public enum KC: Indicator {
    public static let identifier = "KC"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "emaPeriod", defaultValue: 20, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "atrPeriod", defaultValue: 10, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "multiplier", defaultValue: 2, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("KC 需要 3 参数（emaPeriod / atrPeriod / multiplier）")
        }
        let emaN = intValue(params[0])
        let atrN = intValue(params[1])
        let mult = params[2]
        guard emaN >= 1, atrN >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("KC 参数非法 ema=\(emaN) atr=\(atrN) mult=\(mult)")
        }
        let ema = Kernels.ema(kline.closes, period: emaN)
        let atr = try ATR.calculate(kline: kline, params: [Decimal(atrN)])[0].values
        let count = kline.count
        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = ema[i], let a = atr[i] {
                upper[i] = Kernels.round8(m + mult * a)
                lower[i] = Kernels.round8(m - mult * a)
            }
        }
        return [
            IndicatorSeries(name: "KC-MID", values: ema),
            IndicatorSeries(name: "KC-UPPER", values: upper),
            IndicatorSeries(name: "KC-LOWER", values: lower)
        ]
    }
}

// MARK: - Donchian · 唐奇安通道

public enum Donchian: Indicator {
    public static let identifier = "DONCHIAN"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "Donchian period")
        let hhv = Kernels.hhv(kline.highs, period: n)
        let llv = Kernels.llv(kline.lows, period: n)
        let count = kline.count
        var mid = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let h = hhv[i], let l = llv[i] {
                mid[i] = Kernels.round8((h + l) / Decimal(2))
            }
        }
        return [
            IndicatorSeries(name: "DC-UPPER", values: hhv),
            IndicatorSeries(name: "DC-MID", values: mid),
            IndicatorSeries(name: "DC-LOWER", values: llv)
        ]
    }
}

// MARK: - WP-41 v3 第 9 批 · Donchian 增量 API（HHV/LLV 双 ring · 同 KDJ ring 模式）

extension Donchian: IncrementalIndicator {

    /// state：n + (high/low) ring buffer · 输出 [upper, mid, lower]
    /// upper/lower 是 raw HHV/LLV（不 round8 · 与 calculate Kernels.hhv/llv 一致 · max/min 无精度损失）
    /// mid = round8((upper+lower)/2)（与 calculate mid[i] = round8 一致）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var highRing: [Decimal]
        public var lowRing: [Decimal]
        public var head: Int
        public var count: Int
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "Donchian period")
        var state = IncrementalState(
            period: n,
            highRing: [Decimal](repeating: 0, count: n),
            lowRing: [Decimal](repeating: 0, count: n),
            head: 0, count: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, high: newBar.high, low: newBar.low)
    }

    /// ring 写入 O(1) · count < period → 全 nil（warm-up）
    /// count == period 起：扫 ring 求 hhv/llv（O(n)）· 输出 [upper, mid, lower]
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal) -> [Decimal?] {
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
        let mid = Kernels.round8((hhv + llv) / Decimal(2))
        return [hhv, mid, llv]
    }
}

// MARK: - StdDev · 标准差（直接暴露 Kernel）

public enum StdDev: Indicator {
    public static let identifier = "STDDEV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, min: 2, label: "StdDev period")
        return [IndicatorSeries(name: "STDDEV(\(n))", values: Kernels.stddev(kline.closes, period: n))]
    }
}

// MARK: - HV · 历史波动率（log 收益年化，默认 252 交易日）

public enum HV: Indicator {
    public static let identifier = "HV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 2, maxValue: 500),
        IndicatorParameter(name: "annualDays", defaultValue: 252, minValue: 1, maxValue: 365)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 2, label: "HV period")
        let annual = params.count > 1 ? intValue(params[1]) : 252
        let count = kline.count
        var logRet = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            let prev = kline.closes[i - 1]
            if prev > 0 {
                let ratio = NSDecimalNumber(decimal: kline.closes[i] / prev).doubleValue
                logRet[i] = Decimal(Foundation.log(ratio))
            }
        }
        let sd = Kernels.stddev(logRet, period: n)
        let ann = Decimal(Double(annual).squareRoot())
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let v = sd[i] {
                out[i] = Kernels.round8(v * ann * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "HV(\(n))", values: out)]
    }
}

// MARK: - PriceChannel · 价格通道（基于 close 的 Donchian 变体）

public enum PriceChannel: Indicator {
    public static let identifier = "PC"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "PriceChannel period")
        let hhv = Kernels.hhv(kline.closes, period: n)
        let llv = Kernels.llv(kline.closes, period: n)
        return [
            IndicatorSeries(name: "PC-UPPER", values: hhv),
            IndicatorSeries(name: "PC-LOWER", values: llv)
        ]
    }
}

// MARK: - Envelopes · 包络线 MA ± k%

public enum Envelopes: Indicator {
    public static let identifier = "ENV"
    public static let category: IndicatorCategory = .volatility
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "percent", defaultValue: Decimal(string: "2.5")!, minValue: Decimal(string: "0.1")!, maxValue: 50)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Envelopes 需要 2 参数（period / percent）")
        }
        let n = intValue(params[0])
        let pct = params[1]
        let mid = Kernels.ma(kline.closes, period: n)
        let kFactor = pct / Decimal(100)
        let count = kline.count
        var upper = [Decimal?](repeating: nil, count: count)
        var lower = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let m = mid[i] {
                upper[i] = Kernels.round8(m * (Decimal(1) + kFactor))
                lower[i] = Kernels.round8(m * (Decimal(1) - kFactor))
            }
        }
        return [
            IndicatorSeries(name: "ENV-MID", values: mid),
            IndicatorSeries(name: "ENV-UPPER", values: upper),
            IndicatorSeries(name: "ENV-LOWER", values: lower)
        ]
    }
}

// MARK: - WP-41 v3 第 10 批 · KC 增量 API（内嵌 EMA + ATR · 同 MACD 内嵌 EMA 模式）

extension KC: IncrementalIndicator {

    /// state：multiplier + 内嵌 EMA.IncrementalState（mid 源）+ ATR.IncrementalState（带宽源）
    /// 输出 [mid, upper, lower]：mid = ema（已 round8）· upper/lower = round8(mid ± mult * atr)
    /// 与 calculate 等价：calculate 中 mid[i] = ema[i]（round8）· upper/lower = round8 用 round 后的 m * a
    public struct IncrementalState: Sendable {
        public let multiplier: Decimal
        public var emaState: EMA.IncrementalState
        public var atrState: ATR.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        guard params.count >= 3 else {
            throw IndicatorError.invalidParameter("KC 需要 3 参数（emaPeriod / atrPeriod / multiplier）")
        }
        let emaN = intValue(params[0])
        let atrN = intValue(params[1])
        let mult = params[2]
        guard emaN >= 1, atrN >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("KC 参数非法 ema=\(emaN) atr=\(atrN) mult=\(mult)")
        }
        let emaState = try EMA.makeIncrementalState(kline: kline, params: [Decimal(emaN)])
        let atrState = try ATR.makeIncrementalState(kline: kline, params: [Decimal(atrN)])
        return IncrementalState(multiplier: mult, emaState: emaState, atrState: atrState)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        let mid = EMA.stepIncremental(state: &state.emaState, newBar: newBar)[0]
        let atr = ATR.stepIncremental(state: &state.atrState, newBar: newBar)[0]
        // mid 可能先于 atr 输出（emaN < atrN 时）· 按 calculate 仅 mid 不 nil → upper/lower 仍 nil
        guard let m = mid, let a = atr else { return [mid, nil, nil] }
        let upper = Kernels.round8(m + state.multiplier * a)
        let lower = Kernels.round8(m - state.multiplier * a)
        return [mid, upper, lower]
    }
}

// MARK: - WP-41 v3 第 10 批 · StdDev 增量 API（BOLL 简化 · ring + sliding sum + ring.reduce variance · 单列 sd）

extension StdDev: IncrementalIndicator {

    /// state：period + ring + head + count + sum（与 BOLL 同模式 · 不带 k · 仅输出 sd 一列）
    /// 算法与 Kernels.stddev 一致：raw mean + ring reduce variance + sqrt + round8
    public struct IncrementalState: Sendable {
        public let period: Int
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, min: 2, label: "StdDev period")
        let closes = kline.closes
        // 取 history 末尾 ≤ n 个 close 装入 ring · 重建 sum 与 calculate() 末值一致（与 BOLL/MA 同模式）
        let startIdx = max(0, closes.count - n)
        var ring = [Decimal](repeating: 0, count: n)
        var head = 0
        var count = 0
        var sum = Decimal(0)
        for v in closes[startIdx...] {
            ring[head] = v
            head = (head + 1) % n
            count = min(count + 1, n)
            sum += v
        }
        return IncrementalState(period: n, ring: ring, head: head, count: count, sum: sum)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // ring 满 → 减旧值；未满 → count++（与 BOLL 同模式）
        if state.count == state.period {
            state.sum -= state.ring[state.head]
        } else {
            state.count += 1
        }
        state.ring[state.head] = newBar.close
        state.head = (state.head + 1) % state.period
        state.sum += newBar.close

        guard state.count == state.period else { return [nil] }

        // 算法与 Kernels.stddev 一致：raw mean + ring reduce variance + sqrt + round8
        let nDec = Decimal(state.period)
        let mean = state.sum / nDec
        let variance = state.ring.reduce(Decimal(0)) { acc, x in
            let d = x - mean
            return acc + d * d
        } / nDec
        let sdRaw = Decimal(NSDecimalNumber(decimal: variance).doubleValue.squareRoot())
        return [Kernels.round8(sdRaw)]
    }
}

// MARK: - WP-41 v3 第 10 批 · Envelopes 增量 API（MA 复合 · ring + sliding sum · mid ± 百分比偏移）

extension Envelopes: IncrementalIndicator {

    /// state：period + kFactor（pct/100 预计算 · 不动）+ ring + head + count + sum
    /// 输出 [mid, upper, lower]：mid = round8(sum/n) · upper/lower = round8(mid * (1 ± kFactor))
    /// 与 calculate 等价：calculate 中 m = mid[i] = round8(ma) · upper/lower 用 round 后 m
    public struct IncrementalState: Sendable {
        public let period: Int
        public let kFactor: Decimal
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Envelopes 需要 2 参数（period / percent）")
        }
        let n = intValue(params[0])
        let pct = params[1]
        guard n >= 1, pct > 0 else {
            throw IndicatorError.invalidParameter("Envelopes 参数非法 period=\(n) percent=\(pct)")
        }
        let kFactor = pct / Decimal(100)
        let closes = kline.closes
        // 取 history 末尾 ≤ n 个 close 装入 ring · 重建 sum 与 calculate() 末值一致（与 BOLL/MA 同模式）
        let startIdx = max(0, closes.count - n)
        var ring = [Decimal](repeating: 0, count: n)
        var head = 0
        var count = 0
        var sum = Decimal(0)
        for v in closes[startIdx...] {
            ring[head] = v
            head = (head + 1) % n
            count = min(count + 1, n)
            sum += v
        }
        return IncrementalState(period: n, kFactor: kFactor, ring: ring, head: head, count: count, sum: sum)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        // ring 满 → 减旧值；未满 → count++（与 MA 同模式）
        if state.count == state.period {
            state.sum -= state.ring[state.head]
        } else {
            state.count += 1
        }
        state.ring[state.head] = newBar.close
        state.head = (state.head + 1) % state.period
        state.sum += newBar.close

        guard state.count == state.period else { return [nil, nil, nil] }

        // mid 先 round8（与 calculate mid[i] = round8(ma) 对齐）· upper/lower 用 round 后的 mid 算
        let mid = Kernels.round8(state.sum / Decimal(state.period))
        let upper = Kernels.round8(mid * (Decimal(1) + state.kFactor))
        let lower = Kernels.round8(mid * (Decimal(1) - state.kFactor))
        return [mid, upper, lower]
    }
}

// MARK: - WP-41 v3 第 11 批 · PriceChannel 增量 API（基于 close 的 Donchian 变体 · 单 ring · 同 Donchian ring 模式简化）

extension PriceChannel: IncrementalIndicator {

    /// state：n + close ring buffer（单 ring · 比 Donchian 双 ring 简化）· 输出 [upper, lower]
    /// upper/lower 是 raw HHV/LLV（不 round8 · 与 calculate Kernels.hhv/llv 一致 · max/min 无精度损失）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "PriceChannel period")
        var state = IncrementalState(
            period: n,
            ring: [Decimal](repeating: 0, count: n),
            head: 0, count: 0
        )
        // 取 history 全量装入 ring · ring 满后会自动循环覆盖最旧（与 BOLL/MA 同模式）
        for v in kline.closes {
            _ = processStep(state: &state, close: v)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, close: newBar.close)
    }

    /// ring 写入 O(1) · count < period → 全 nil（warm-up）
    /// count == period 起：扫 ring 求 hhv/llv（O(n)）· 输出 [upper, lower]
    private static func processStep(state: inout IncrementalState, close: Decimal) -> [Decimal?] {
        state.ring[state.head] = close
        state.head = (state.head + 1) % state.period
        state.count = min(state.count + 1, state.period)

        guard state.count == state.period else { return [nil, nil] }

        var hhv = state.ring[0]
        var llv = state.ring[0]
        for i in 1..<state.period {
            if state.ring[i] > hhv { hhv = state.ring[i] }
            if state.ring[i] < llv { llv = state.ring[i] }
        }
        return [hhv, llv]
    }
}

// MARK: - WP-41 v3 第 11 批 · HV 增量 API（log 收益 + ring StdDev + annual scaling · 同 BOLL/StdDev ring 模式 + log 转换层）

extension HV: IncrementalIndicator {

    /// state：period + annualScale 预计算（sqrt(annualDays) * 100 · 不变量）+ prevClose（log 收益用 · nil 时返回 0）
    /// + ring(logRet) + head + count + sum
    /// 与 calculate 关键对齐：第 1 根 logRet=0（与 calculate logRet[0]=0 一致 · 入 ring 参与 stddev）
    /// sd 用 round8 snapshot（与 Kernels.stddev 一致）后乘 annualScale 再 round8（与 calculate out[i]=round8 链一致）
    public struct IncrementalState: Sendable {
        public let period: Int
        public let annualScale: Decimal
        public var prevClose: Decimal?
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var sum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 2, label: "HV period")
        let annual = params.count > 1 ? intValue(params[1]) : 252
        guard annual >= 1 else {
            throw IndicatorError.invalidParameter("HV annualDays 非法 \(annual)")
        }
        let annualScale = Decimal(Double(annual).squareRoot()) * Decimal(100)
        var state = IncrementalState(
            period: n,
            annualScale: annualScale,
            prevClose: nil,
            ring: [Decimal](repeating: 0, count: n),
            head: 0, count: 0, sum: 0
        )
        // 取 history 全量装入 ring · 通过 processStep 累加 logRet（与 calculate logRet 数组对齐）
        for v in kline.closes {
            _ = processStep(state: &state, close: v)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close)]
    }

    /// makeIncrementalState 与 stepIncremental 共享：
    /// - 第 1 根 prevClose=nil → logRet=0（与 calculate logRet[0]=0 一致）· 写入 ring + sum · 之后 prevClose=close
    /// - 第 2 根起：prevClose>0 时 logRet = log(close/prev) · 否则 0（与 calculate if prev>0 一致）
    /// - ring 满 → sum 增量更新（减旧加新）· 未满 → count++
    /// - count == period 起算 sd（raw mean + ring reduce variance + sqrt + round8）· hv = round8(sd_round8 * annualScale)
    private static func processStep(state: inout IncrementalState, close: Decimal) -> Decimal? {
        let logRet: Decimal
        if let pc = state.prevClose, pc > 0 {
            let ratio = NSDecimalNumber(decimal: close / pc).doubleValue
            logRet = Decimal(Foundation.log(ratio))
        } else {
            logRet = 0
        }
        state.prevClose = close

        // ring 满 → 减旧值；未满 → count++（与 BOLL 同模式）
        if state.count == state.period {
            state.sum -= state.ring[state.head]
        } else {
            state.count += 1
        }
        state.ring[state.head] = logRet
        state.head = (state.head + 1) % state.period
        state.sum += logRet

        guard state.count == state.period else { return nil }

        // 算法与 Kernels.stddev 一致：raw mean + ring reduce variance + sqrt + round8
        let nDec = Decimal(state.period)
        let mean = state.sum / nDec
        let variance = state.ring.reduce(Decimal(0)) { acc, x in
            let d = x - mean
            return acc + d * d
        } / nDec
        let sdRaw = Decimal(NSDecimalNumber(decimal: variance).doubleValue.squareRoot())
        // sd 先 round8 snapshot（与 Kernels.stddev 输出一致）· 再乘 annualScale 再 round8（与 calculate out[i] 链一致）
        let sd = Kernels.round8(sdRaw)
        return Kernels.round8(sd * state.annualScale)
    }
}
