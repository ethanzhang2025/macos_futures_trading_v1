// WP-41 第二批 · 趋势类 8 指标（除 MA/EMA 已在 MA.swift）
// WMA / DEMA / TEMA / HMA / VWAP / SAR / Supertrend / ADX
//
// WP-41 v3 第 2 批 commit 3/4：ADX 实现 IncrementalIndicator · 4 路 Wilder 平滑 · DMI 复用 ADX state
// WP-41 v3 第 5 批：DEMA + TEMA 实现 IncrementalIndicator · 复合 EMA 线性组合（TRIX 模式简化 · 无差分）
// WP-41 v3 第 6 批：VWAP 实现 IncrementalIndicator · 累积 typical*volume / 累积 volume（同 OBV 模式无周期）
// WP-41 v3 第 8 批：WMA + HMA 实现 IncrementalIndicator · WMA O(1) Pascal triangle sliding · HMA 内嵌 3 WMA

import Foundation
import Shared

// MARK: - WMA · 加权移动平均

public enum WMA: Indicator {
    public static let identifier = "WMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "WMA period")
        return [IndicatorSeries(name: "WMA(\(n))", values: Kernels.wma(kline.closes, period: n))]
    }
}

// MARK: - WP-41 v3 第 8 批 · WMA 增量 API（O(1) Pascal triangle sliding · HMA 内嵌复用）

extension WMA: IncrementalIndicator {

    /// state：ring[n] + numerator + runningSum
    /// Pascal 公式：num[i+1] = num[i] + n*close[i+1] - runningSum[i]
    ///             runningSum[i+1] = runningSum[i] + close[i+1] - close[i-n+1]
    /// O(1) per step（warm-up 期 count==n 时一次性 seed 是 O(n) · 仅一次）
    public struct IncrementalState: Sendable {
        public let period: Int
        public let nDec: Decimal
        public let weightSum: Decimal
        public var ring: [Decimal]
        public var head: Int
        public var count: Int
        public var numerator: Decimal
        public var runningSum: Decimal

        /// 推进一个 close · 返回该步 WMA round8 值（warm-up 期返回 nil）
        /// 对外暴露给 HMA 等复合指标内嵌（与 EMA.advance 同模式）
        public mutating func advance(close: Decimal) -> Decimal? {
            if count < period {
                ring[head] = close
                head = (head + 1) % period
                count += 1
                guard count == period else { return nil }
                // count 刚达到 period · 一次性 seed numerator + runningSum
                // ring 当前布局：head == 0（第 n 步写完后 head 回环到起点）· ring[0..n-1] = close[0..n-1]
                // numerator = Σ k*close[k-1] for k=1..n（最旧 close[0] 权重 1 · 最新 close[n-1] 权重 n）
                numerator = 0
                runningSum = 0
                for k in 1...period {
                    let idx = (head + k - 1) % period
                    numerator += Decimal(k) * ring[idx]
                    runningSum += ring[idx]
                }
                return Kernels.round8(numerator / weightSum)
            }
            // Sliding 期 · ring[head] 是即将被覆盖 = close[i-n+1]（最旧）
            let oldClose = ring[head]
            // 注意顺序：先用 runningSum 算 numerator（关键 · runningSum 此时是覆盖前的）
            numerator = numerator + nDec * close - runningSum
            runningSum = runningSum + close - oldClose
            ring[head] = close
            head = (head + 1) % period
            count += 1
            return Kernels.round8(numerator / weightSum)
        }
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 1, label: "WMA period")
        let weightSum = Decimal(n * (n + 1) / 2)
        var state = IncrementalState(
            period: n, nDec: Decimal(n), weightSum: weightSum,
            ring: [Decimal](repeating: 0, count: n),
            head: 0, count: 0,
            numerator: 0, runningSum: 0
        )
        for close in kline.closes {
            _ = state.advance(close: close)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [state.advance(close: newBar.close)]
    }
}

// MARK: - WP-41 v3 第 8 批 · HMA 增量 API（内嵌 3 WMA · halfN/n/sqrtN · 同 TRIX 复合模式）

extension HMA: IncrementalIndicator {

    /// state：3 个 WMA.IncrementalState · raw = 2*wHalf - wFull · final = wma(raw, sqrtN)
    /// 与 calculate 一致：raw 在 wHalf/wFull 都有值时 = 2h-f；否则 raw = 0（数组默认初值）
    /// 中间层 hmaWma 每步都 advance（用 raw=0 替换 nil · 与 calculate raw 数组每位都赋值一致）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var wHalf: WMA.IncrementalState
        public var wFull: WMA.IncrementalState
        public var hmaWma: WMA.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 4, label: "HMA period")
        let halfN = max(1, n / 2)
        let sqrtN = max(1, Int(Double(n).squareRoot()))
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            period: n,
            wHalf: try WMA.makeIncrementalState(kline: empty, params: [Decimal(halfN)]),
            wFull: try WMA.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            hmaWma: try WMA.makeIncrementalState(kline: empty, params: [Decimal(sqrtN)])
        )
        for close in kline.closes {
            _ = processStep(state: &state, close: close)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close)]
    }

    /// raw = 2*h - f（用 advance round8 值 · 与 calculate raw[i] 用 wHalf[i]/wFull[i] round8 值一致）
    /// hmaWma 每步无条件 advance（用 raw 即可 · h/f nil 时 raw=0）
    private static func processStep(state: inout IncrementalState, close: Decimal) -> Decimal? {
        let h = state.wHalf.advance(close: close)
        let f = state.wFull.advance(close: close)
        let raw: Decimal
        if let hh = h, let ff = f {
            raw = Decimal(2) * hh - ff
        } else {
            raw = 0
        }
        return state.hmaWma.advance(close: raw)
    }
}

// MARK: - DEMA · 双重 EMA = 2*EMA - EMA(EMA)

public enum DEMA: Indicator {
    public static let identifier = "DEMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "DEMA period")
        let e1 = Kernels.ema(kline.closes, period: n)
        let e2 = Kernels.nextEMA(e1, period: n)
        var out = [Decimal?](repeating: nil, count: kline.count)
        for i in 0..<kline.count {
            if let x1 = e1[i], let x2 = e2[i] {
                out[i] = Kernels.round8(Decimal(2) * x1 - x2)
            }
        }
        return [IndicatorSeries(name: "DEMA(\(n))", values: out)]
    }
}

// MARK: - WP-41 v3 第 5 批 · DEMA 增量 API（内嵌 2 EMA · 同 TRIX 复合模式 · 无差分）

extension DEMA: IncrementalIndicator {

    /// state：2 个 EMA.IncrementalState（e1 接 close · e2 接 e1 ?? 0 · 与 Kernels.nextEMA 一致）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var e1: EMA.IncrementalState
        public var e2: EMA.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 1, label: "DEMA period")
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            period: n,
            e1: try EMA.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            e2: try EMA.makeIncrementalState(kline: empty, params: [Decimal(n)])
        )
        for close in kline.closes {
            _ = processStep(state: &state, close: close)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close)]
    }

    /// DEMA = 2*e1 - e2 · 必须 e1 与 e2 都有值（与 calculate guard let x1, x2 一致）
    /// e1/e2 都用 advance round8 返回值（与 calculate 用 e1[i]/e2[i] 数组中 round8 值一致 · 精度对齐）
    private static func processStep(state: inout IncrementalState, close: Decimal) -> Decimal? {
        let e1Out = state.e1.advance(close: close)
        let e2Out = state.e2.advance(close: e1Out ?? 0)
        guard let x1 = e1Out, let x2 = e2Out else { return nil }
        return Kernels.round8(Decimal(2) * x1 - x2)
    }
}

// MARK: - TEMA · 三重 EMA = 3*EMA - 3*EMA(EMA) + EMA(EMA(EMA))

public enum TEMA: Indicator {
    public static let identifier = "TEMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 1, label: "TEMA period")
        let e1 = Kernels.ema(kline.closes, period: n)
        let e2 = Kernels.nextEMA(e1, period: n)
        let e3 = Kernels.nextEMA(e2, period: n)
        var out = [Decimal?](repeating: nil, count: kline.count)
        for i in 0..<kline.count {
            if let x1 = e1[i], let x2 = e2[i], let x3 = e3[i] {
                out[i] = Kernels.round8(Decimal(3) * x1 - Decimal(3) * x2 + x3)
            }
        }
        return [IndicatorSeries(name: "TEMA(\(n))", values: out)]
    }
}

// MARK: - WP-41 v3 第 5 批 · TEMA 增量 API（内嵌 3 EMA · 同 TRIX 复合模式 · 无差分）

extension TEMA: IncrementalIndicator {

    /// state：3 个 EMA.IncrementalState（同 TRIX 内嵌模式 · 但输出是 3*x1-3*x2+x3 而非差分）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var e1: EMA.IncrementalState
        public var e2: EMA.IncrementalState
        public var e3: EMA.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 1, label: "TEMA period")
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            period: n,
            e1: try EMA.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            e2: try EMA.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            e3: try EMA.makeIncrementalState(kline: empty, params: [Decimal(n)])
        )
        for close in kline.closes {
            _ = processStep(state: &state, close: close)
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close)]
    }

    /// TEMA = 3*e1 - 3*e2 + e3 · 必须 3 EMA 都有值
    private static func processStep(state: inout IncrementalState, close: Decimal) -> Decimal? {
        let e1Out = state.e1.advance(close: close)
        let e2Out = state.e2.advance(close: e1Out ?? 0)
        let e3Out = state.e3.advance(close: e2Out ?? 0)
        guard let x1 = e1Out, let x2 = e2Out, let x3 = e3Out else { return nil }
        return Kernels.round8(Decimal(3) * x1 - Decimal(3) * x2 + x3)
    }
}

// MARK: - HMA · Hull 移动平均 = WMA(2*WMA(n/2) - WMA(n), √n)

public enum HMA: Indicator {
    public static let identifier = "HMA"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 16, minValue: 4, maxValue: 500)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 4, label: "HMA period")
        let halfN = max(1, n / 2)
        let sqrtN = max(1, Int(Double(n).squareRoot()))
        let wHalf = Kernels.wma(kline.closes, period: halfN)
        let wFull = Kernels.wma(kline.closes, period: n)
        var raw = [Decimal](repeating: 0, count: kline.count)
        for i in 0..<kline.count {
            if let h = wHalf[i], let f = wFull[i] {
                raw[i] = Decimal(2) * h - f
            }
        }
        let hma = Kernels.wma(raw, period: sqrtN)
        return [IndicatorSeries(name: "HMA(\(n))", values: hma)]
    }
}

// MARK: - VWAP · 成交量加权均价（日内累积）
// 无周期参数；从序列起始点累积 Σ(price * volume) / Σvolume

public enum VWAP: Indicator {
    public static let identifier = "VWAP"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        var cumPV: Decimal = 0
        var cumV: Decimal = 0
        for i in 0..<count {
            let typical = (kline.highs[i] + kline.lows[i] + kline.closes[i]) / Decimal(3)
            cumPV += typical * Decimal(kline.volumes[i])
            cumV += Decimal(kline.volumes[i])
            out[i] = cumV == 0 ? nil : Kernels.round8(cumPV / cumV)
        }
        return [IndicatorSeries(name: "VWAP", values: out)]
    }
}

// MARK: - WP-41 v3 第 6 批 · VWAP 增量 API（累积式 · 同 OBV 模式 · 无周期 · 无 warm-up）

extension VWAP: IncrementalIndicator {

    /// state：cumPV + cumV · 流式累加 · cumV == 0 时输出 nil（与 calculate 一致）
    public struct IncrementalState: Sendable {
        public var cumPV: Decimal
        public var cumV: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(cumPV: 0, cumV: 0)
        let count = kline.highs.count
        for i in 0..<count {
            _ = processStep(state: &state,
                            high: kline.highs[i], low: kline.lows[i],
                            close: kline.closes[i], volume: kline.volumes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close, volume: newBar.volume)]
    }

    /// typical = (H+L+C)/3 · cumPV += typical*volume · cumV += volume
    /// 输出 round8(cumPV/cumV) · cumV==0 → nil（极端：开盘前所有 volume=0 等）
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal, volume: Int) -> Decimal? {
        let typical = (high + low + close) / Decimal(3)
        let volDec = Decimal(volume)
        state.cumPV += typical * volDec
        state.cumV += volDec
        guard state.cumV != 0 else { return nil }
        return Kernels.round8(state.cumPV / state.cumV)
    }
}

// MARK: - SAR · 抛物线转向（Welles Wilder）
// 参数：加速因子初值 0.02 / 最大值 0.2

public enum SAR: Indicator {
    public static let identifier = "SAR"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "step", defaultValue: Decimal(string: "0.02")!, minValue: Decimal(string: "0.001")!, maxValue: 1),
        IndicatorParameter(name: "max", defaultValue: Decimal(string: "0.2")!, minValue: Decimal(string: "0.01")!, maxValue: 1)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("SAR 需要 2 参数（step / max）")
        }
        let step = params[0]
        let maxAF = params[1]
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        guard count >= 2 else { return [IndicatorSeries(name: "SAR", values: out)] }

        // 初始方向：首 2 根 close 比较
        var isLong = kline.closes[1] >= kline.closes[0]
        var ep = isLong ? kline.highs[0] : kline.lows[0]   // 极端点
        var af = step
        var sar = isLong ? kline.lows[0] : kline.highs[0]
        out[0] = Kernels.round8(sar)

        for i in 1..<count {
            sar = sar + af * (ep - sar)
            // 多头 SAR 不能超当前两根最低；空头反之
            if isLong {
                sar = min(sar, kline.lows[i - 1])
                if i >= 2 { sar = min(sar, kline.lows[i - 2]) }
                if kline.highs[i] > ep { ep = kline.highs[i]; af = min(af + step, maxAF) }
                if kline.lows[i] < sar {  // 反转
                    isLong = false
                    sar = ep
                    ep = kline.lows[i]
                    af = step
                }
            } else {
                sar = max(sar, kline.highs[i - 1])
                if i >= 2 { sar = max(sar, kline.highs[i - 2]) }
                if kline.lows[i] < ep { ep = kline.lows[i]; af = min(af + step, maxAF) }
                if kline.highs[i] > sar {
                    isLong = true
                    sar = ep
                    ep = kline.highs[i]
                    af = step
                }
            }
            out[i] = Kernels.round8(sar)
        }
        return [IndicatorSeries(name: "SAR", values: out)]
    }
}

// MARK: - Supertrend · 基于 ATR 的超级趋势
// 参数：period（10）/ multiplier（3）

public enum Supertrend: Indicator {
    public static let identifier = "Supertrend"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 10, minValue: 1, maxValue: 500),
        IndicatorParameter(name: "multiplier", defaultValue: 3, minValue: 1, maxValue: 10)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Supertrend 需要 2 参数（period / multiplier）")
        }
        let n = intValue(params[0])
        let mult = params[1]
        guard n >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("Supertrend 参数非法 period=\(n) mult=\(mult)")
        }
        let atr = try ATR.calculate(kline: kline, params: [Decimal(n)])[0].values
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        var upperBand: Decimal? = nil
        var lowerBand: Decimal? = nil
        var isUp = true
        for i in 0..<count {
            guard let a = atr[i] else { continue }
            let mid = (kline.highs[i] + kline.lows[i]) / Decimal(2)
            let rawUp = mid + mult * a
            let rawLow = mid - mult * a
            // 带状约束：上轨只降不升（除非上一根收盘击穿），保持趋势跟踪稳定性
            // 种子时（prev == nil）直接采用 raw；后续迭代下 i >= 1，closes[i-1] 合法
            let newUpper: Decimal
            if let prev = upperBand {
                newUpper = (rawUp < prev || kline.closes[i - 1] > prev) ? rawUp : prev
            } else {
                newUpper = rawUp
            }
            let newLower: Decimal
            if let prev = lowerBand {
                newLower = (rawLow > prev || kline.closes[i - 1] < prev) ? rawLow : prev
            } else {
                newLower = rawLow
            }
            upperBand = newUpper
            lowerBand = newLower
            if isUp, kline.closes[i] < newLower {
                isUp = false
            } else if !isUp, kline.closes[i] > newUpper {
                isUp = true
            }
            out[i] = Kernels.round8(isUp ? newLower : newUpper)
        }
        return [IndicatorSeries(name: "Supertrend", values: out)]
    }
}

// MARK: - ADX · 平均趋向指数（Wilder 方法，配 +DI/-DI）

public enum ADX: Indicator {
    public static let identifier = "ADX"
    public static let category: IndicatorCategory = .trend
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, index: 0, min: 2, label: "ADX period")
        let count = kline.count
        guard count >= 2 else { return emptyADX(count) }

        var plusDM = [Decimal](repeating: 0, count: count)
        var minusDM = [Decimal](repeating: 0, count: count)
        var tr = [Decimal](repeating: 0, count: count)
        tr[0] = kline.highs[0] - kline.lows[0]
        for i in 1..<count {
            let up = kline.highs[i] - kline.highs[i - 1]
            let dn = kline.lows[i - 1] - kline.lows[i]
            plusDM[i] = (up > dn && up > 0) ? up : 0
            minusDM[i] = (dn > up && dn > 0) ? dn : 0
            let hl = kline.highs[i] - kline.lows[i]
            let hc = abs(kline.highs[i] - kline.closes[i - 1])
            let lc = abs(kline.lows[i] - kline.closes[i - 1])
            tr[i] = max(hl, max(hc, lc))
        }
        let atr = Kernels.wilder(tr, period: n)
        let smPlusDM = Kernels.wilder(plusDM, period: n)
        let smMinusDM = Kernels.wilder(minusDM, period: n)
        var plusDI = [Decimal?](repeating: nil, count: count)
        var minusDI = [Decimal?](repeating: nil, count: count)
        var dx = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            if let a = atr[i], let pdm = smPlusDM[i], let mdm = smMinusDM[i], a > 0 {
                let pdi = Decimal(100) * pdm / a
                let mdi = Decimal(100) * mdm / a
                plusDI[i] = Kernels.round8(pdi)
                minusDI[i] = Kernels.round8(mdi)
                let sum = pdi + mdi
                dx[i] = sum == 0 ? 0 : Decimal(100) * abs(pdi - mdi) / sum
            }
        }
        let adx = Kernels.wilder(dx, period: n)
        return [
            IndicatorSeries(name: "ADX", values: adx),
            IndicatorSeries(name: "+DI", values: plusDI),
            IndicatorSeries(name: "-DI", values: minusDI)
        ]
    }

    private static func emptyADX(_ count: Int) -> [IndicatorSeries] {
        let empty = [Decimal?](repeating: nil, count: count)
        return [
            IndicatorSeries(name: "ADX", values: empty),
            IndicatorSeries(name: "+DI", values: empty),
            IndicatorSeries(name: "-DI", values: empty)
        ]
    }
}

// MARK: - WP-41 v3 第 2 批 commit 3/4 · ADX 增量 API（4 路 Wilder + DMI 复用）

extension ADX: IncrementalIndicator {

    /// state：4 路 Wilder 流式状态（atr / smPDM / smMDM / adx）+ prevHigh/Low/Close（DM/TR 计算用）
    /// 一级 Wilder：tr / plusDM / minusDM 各自 Wilder 平滑
    /// 二级 Wilder：dx 由 +DI/-DI 计算 → 再 Wilder 得 ADX
    /// 首个 ADX/+DI/-DI 输出在 count == period（与 calculate 第 n 根 K 一致 · seed 等价于 wilder prefix(n).sum/n）
    /// 之所以一级 + 二级合一：calculate 内部数据流也是先平滑 atr/smPDM/smMDM → 算 +DI/-DI/dx → 平滑 ADX
    public struct IncrementalState: Sendable {
        public let period: Int
        public let nDec: Decimal
        public let nMinus1: Decimal

        public var prevHigh: Decimal?
        public var prevLow: Decimal?
        public var prevClose: Decimal?
        public var count: Int

        // 一级 Wilder（tr / plusDM / minusDM）
        public var trWarmUp: Decimal
        public var atr: Decimal
        public var pdmWarmUp: Decimal
        public var smPDM: Decimal
        public var mdmWarmUp: Decimal
        public var smMDM: Decimal

        // 二级 Wilder（dx → ADX · 流式 · seed 在 count == period 时 = 当前 dx / n）
        // 注：calculate 里 dx[0..n-2] 默认初始化 0 · wilder seed = prefix(n).sum / n 等价于 dx_current/n
        public var adx: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, index: 0, min: 2, label: "ADX period")
        var state = IncrementalState(
            period: n, nDec: Decimal(n), nMinus1: Decimal(n - 1),
            prevHigh: nil, prevLow: nil, prevClose: nil,
            count: 0,
            trWarmUp: 0, atr: 0,
            pdmWarmUp: 0, smPDM: 0,
            mdmWarmUp: 0, smMDM: 0,
            adx: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i], close: kline.closes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        processStep(state: &state, high: newBar.high, low: newBar.low, close: newBar.close)
    }

    /// makeIncrementalState 与 stepIncremental 共享：
    /// - 第 1 根：TR = high - low（无 prevClose）· plusDM/minusDM = 0（无 prevHigh/Low）
    /// - 第 2..n-1 根：累加 warmUp · 返回全 nil
    /// - 第 n 根：seed atr/smPDM/smMDM = warmUp/n · 第一次算 +DI/-DI/dx · adx = dx/n（wilder 二级 seed）
    /// - 第 n+1 根起：一级 Wilder 平滑各自值 · 同步算 +DI/-DI/dx · 二级 Wilder 平滑 adx
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal) -> [Decimal?] {
        state.count += 1

        // TR / plusDM / minusDM
        let tr: Decimal
        if let pc = state.prevClose {
            let hl = high - low
            let hc = abs(high - pc)
            let lc = abs(low - pc)
            tr = max(hl, max(hc, lc))
        } else {
            tr = high - low
        }

        let plusDM: Decimal
        let minusDM: Decimal
        if let ph = state.prevHigh, let pl = state.prevLow {
            let up = high - ph
            let dn = pl - low
            plusDM = (up > dn && up > 0) ? up : 0
            minusDM = (dn > up && dn > 0) ? dn : 0
        } else {
            plusDM = 0
            minusDM = 0
        }

        state.prevHigh = high
        state.prevLow = low
        state.prevClose = close

        // 一级 Wilder（tr / plusDM / minusDM 同步）
        if state.count < state.period {
            state.trWarmUp += tr
            state.pdmWarmUp += plusDM
            state.mdmWarmUp += minusDM
            return [nil, nil, nil]
        }
        if state.count == state.period {
            state.trWarmUp += tr
            state.pdmWarmUp += plusDM
            state.mdmWarmUp += minusDM
            state.atr = state.trWarmUp / state.nDec
            state.smPDM = state.pdmWarmUp / state.nDec
            state.smMDM = state.mdmWarmUp / state.nDec
        } else {
            state.atr = (state.atr * state.nMinus1 + tr) / state.nDec
            state.smPDM = (state.smPDM * state.nMinus1 + plusDM) / state.nDec
            state.smMDM = (state.smMDM * state.nMinus1 + minusDM) / state.nDec
        }

        // +DI / -DI / DX（atr <= 0 → 全 nil + dx=0）
        // 关键精度对齐：calculate 用 wilder 输出（= round8(prev)）作 +DI 输入 · 增量也必须 round8 snapshot
        // 否则与全量末位精度差 1-2 位（同 RSI commit 2/4 的发现）
        let atrSnap = Kernels.round8(state.atr)
        let plusDIOut: Decimal?
        let minusDIOut: Decimal?
        let dx: Decimal
        if atrSnap > 0 {
            let pdmSnap = Kernels.round8(state.smPDM)
            let mdmSnap = Kernels.round8(state.smMDM)
            let pdi = Decimal(100) * pdmSnap / atrSnap
            let mdi = Decimal(100) * mdmSnap / atrSnap
            plusDIOut = Kernels.round8(pdi)
            minusDIOut = Kernels.round8(mdi)
            let sum = pdi + mdi
            dx = sum == 0 ? 0 : Decimal(100) * abs(pdi - mdi) / sum
        } else {
            plusDIOut = nil
            minusDIOut = nil
            dx = 0
        }

        // 二级 Wilder（dx → ADX · seed 用当前 dx · 等价 wilder prefix(n).sum/n where 前 n-1 个 dx 全 0）
        if state.count == state.period {
            state.adx = dx / state.nDec
        } else {
            state.adx = (state.adx * state.nMinus1 + dx) / state.nDec
        }

        return [Kernels.round8(state.adx), plusDIOut, minusDIOut]
    }
}

// MARK: - DMI 增量 API · 直接复用 ADX state · 仅截取 +DI/-DI 两列

extension DMI: IncrementalIndicator {

    /// DMI 是 ADX 的 [+DI, -DI] 子集 · state 与算法完全复用 ADX
    public typealias IncrementalState = ADX.IncrementalState

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        try ADX.makeIncrementalState(kline: kline, params: params)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        let row = ADX.stepIncremental(state: &state, newBar: newBar)
        // ADX 输出 [ADX, +DI, -DI] · DMI 取后两列（与 DMI.calculate 一致）
        return [row[1], row[2]]
    }
}

// MARK: - WP-41 v3 第 15 批 · Supertrend 增量 API（内嵌 ATR + 状态机 upperBand/lowerBand/isUp/prevClose）

extension Supertrend: IncrementalIndicator {

    /// state：multiplier + 内嵌 ATR.IncrementalState + upperBand/lowerBand/isUp + prevClose
    /// 与 calculate 关键对齐：
    /// - warm-up（atr nil）→ 输出 nil · 不更新 band/isUp · 仅由 defer 推进 prevClose（替代 calculate 中 closes[i-1] 的隐式索引）
    /// - 带状收紧：prev 存在时用 prevClose 决定保持/重置（calculate 用 closes[i-1]，等价）· prev nil 时直接采用 raw（种子根）
    /// - isUp 默认 true（与 calculate `var isUp = true` 一致）· 翻转条件：isUp && close < newLower → 转空 · !isUp && close > newUpper → 转多
    /// - 输出 round8(isUp ? newLower : newUpper)
    public struct IncrementalState: Sendable {
        public let multiplier: Decimal
        public var atrState: ATR.IncrementalState
        public var upperBand: Decimal?
        public var lowerBand: Decimal?
        public var isUp: Bool
        public var prevClose: Decimal?
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("Supertrend 需要 2 参数（period / multiplier）")
        }
        let n = intValue(params[0])
        let mult = params[1]
        guard n >= 1, mult > 0 else {
            throw IndicatorError.invalidParameter("Supertrend 参数非法 period=\(n) mult=\(mult)")
        }
        // ATR 用空 series 起 seed（不在此处一次性消化 history）· 因为 Supertrend 自身 band/isUp/prevClose 也要逐步推进 · 必须与 ATR 共享同一个 history 循环
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = IncrementalState(
            multiplier: mult,
            atrState: try ATR.makeIncrementalState(kline: empty, params: [Decimal(n)]),
            upperBand: nil, lowerBand: nil,
            isUp: true,
            prevClose: nil
        )
        // history 循环：构造中转 KLine 调 processStep（ATR.stepIncremental 接口要求 KLine · 仅 history 消化路径需构造 · stepIncremental 路径直接透传 newBar 零成本）
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
        [processStep(state: &state, bar: newBar)]
    }

    /// 单步推进（makeIncrementalState 与 stepIncremental 共享）：
    /// - 先 ATR.stepIncremental 推进 atrState · 用 defer 把 prevClose 更新挪到出口（warm-up 早 return 也覆盖 · 与 calculate 中 closes 数组每步可读语义对齐）
    /// - atr 有值时按 calculate 同款公式：mid = (h+l)/2 · rawUp/rawLow = mid ± mult * atr
    /// - 带状收紧：prev 存在 → 用 prevClose 决定保持/重置 · prev nil（种子根）→ 直接采用 raw
    /// - 翻转后输出 round8(isUp ? newLower : newUpper)
    private static func processStep(state: inout IncrementalState, bar: KLine) -> Decimal? {
        let atrRow = ATR.stepIncremental(state: &state.atrState, newBar: bar)
        let close = bar.close
        defer { state.prevClose = close }

        guard let a = atrRow[0] else {
            // warm-up：atr nil → 不更新 band/isUp · 输出 nil（与 calculate `guard let a = atr[i] else { continue }` 一致）
            return nil
        }
        let mid = (bar.high + bar.low) / Decimal(2)
        let rawUp = mid + state.multiplier * a
        let rawLow = mid - state.multiplier * a

        // 带状收紧（与 calculate 同公式）：prev != nil 蕴含 prevClose != nil（前一步 defer 设过）· 双 unwrap 仅是 Swift 类型保险
        let newUpper: Decimal
        if let prev = state.upperBand, let pc = state.prevClose {
            newUpper = (rawUp < prev || pc > prev) ? rawUp : prev
        } else {
            newUpper = rawUp
        }
        let newLower: Decimal
        if let prev = state.lowerBand, let pc = state.prevClose {
            newLower = (rawLow > prev || pc < prev) ? rawLow : prev
        } else {
            newLower = rawLow
        }
        state.upperBand = newUpper
        state.lowerBand = newLower
        if state.isUp, close < newLower {
            state.isUp = false
        } else if !state.isUp, close > newUpper {
            state.isUp = true
        }
        return Kernels.round8(state.isUp ? newLower : newUpper)
    }
}

// 共用 requireIntParam 已在 Indicator.swift 定义
