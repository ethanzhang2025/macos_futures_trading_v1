// WP-41 第二批 · 量价类 7 指标（除 OBV 已在独立文件）
// Volume / MFI / CMF / VR / PVT / ADL / VOSC
//
// WP-41 v3 第 9 批：PVT 实现 IncrementalIndicator · 累积式（同 OBV 模式 · 无周期）
// WP-41 v3 第 12 批：MFI + ADL + VOSC 增量 API（双 ring up/dn / 累积式 / 内嵌 2 EMA · 33 指标 58.9% 覆盖）

import Foundation
import Shared

// MARK: - Volume · 成交量柱（Int → Decimal 直通）

public enum Volume: Indicator {
    public static let identifier = "VOL"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let values: [Decimal?] = kline.volumes.map { Decimal($0) }
        return [IndicatorSeries(name: "VOL", values: values)]
    }
}

// MARK: - MFI · 资金流量指数

public enum MFI: Indicator {
    public static let identifier = "MFI"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 14, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "MFI period")
        let count = kline.count
        var tp = [Decimal](repeating: 0, count: count)
        var mf = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            tp[i] = (kline.highs[i] + kline.lows[i] + kline.closes[i]) / Decimal(3)
            mf[i] = tp[i] * Decimal(kline.volumes[i])
        }
        var posMF = [Decimal](repeating: 0, count: count)
        var negMF = [Decimal](repeating: 0, count: count)
        for i in 1..<count {
            if tp[i] > tp[i - 1] { posMF[i] = mf[i] }
            else if tp[i] < tp[i - 1] { negMF[i] = mf[i] }
        }
        let posSums = Kernels.slidingSum(posMF, period: n)
        let negSums = Kernels.slidingSum(negMF, period: n)
        var out = [Decimal?](repeating: nil, count: count)
        // 原实现从 i=n 起（种子窗口 [1...n]，跳过 i=n-1 的首窗口），保留此行为
        for i in n..<count {
            guard let sp = posSums[i], let sn = negSums[i] else { continue }
            if sn == 0 {
                out[i] = 100
            } else {
                let mr = sp / sn
                out[i] = Kernels.round8(Decimal(100) - Decimal(100) / (Decimal(1) + mr))
            }
        }
        return [IndicatorSeries(name: "MFI(\(n))", values: out)]
    }
}

// MARK: - CMF · 蔡金资金流

public enum CMF: Indicator {
    public static let identifier = "CMF"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 20, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "CMF period")
        let count = kline.count
        var mfv = [Decimal](repeating: 0, count: count)
        var volDec = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            volDec[i] = Decimal(kline.volumes[i])
            let hl = kline.highs[i] - kline.lows[i]
            if hl > 0 {
                let mfm = ((kline.closes[i] - kline.lows[i]) - (kline.highs[i] - kline.closes[i])) / hl
                mfv[i] = mfm * volDec[i]
            }
        }
        let mfvSums = Kernels.slidingSum(mfv, period: n)
        let volSums = Kernels.slidingSum(volDec, period: n)
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let sumMFV = mfvSums[i], let sumV = volSums[i], sumV > 0 {
                out[i] = Kernels.round8(sumMFV / sumV)
            }
        }
        return [IndicatorSeries(name: "CMF(\(n))", values: out)]
    }
}

// MARK: - VR · 成交量比

public enum VR: Indicator {
    public static let identifier = "VR"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "period", defaultValue: 26, minValue: 1, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let n = try requireIntParam(params, label: "VR period")
        let count = kline.count
        // 按三种日类型分桶（涨/跌/平）；index 0 无前值参考，保持 0 即可
        var upVol = [Decimal](repeating: 0, count: count)
        var downVol = [Decimal](repeating: 0, count: count)
        var flatVol = [Decimal](repeating: 0, count: count)
        for j in 1..<count {
            let v = Decimal(kline.volumes[j])
            if kline.closes[j] > kline.closes[j - 1] { upVol[j] = v }
            else if kline.closes[j] < kline.closes[j - 1] { downVol[j] = v }
            else { flatVol[j] = v }
        }
        let upSums = Kernels.slidingSum(upVol, period: n)
        let downSums = Kernels.slidingSum(downVol, period: n)
        let flatSums = Kernels.slidingSum(flatVol, period: n)
        var out = [Decimal?](repeating: nil, count: count)
        // 原实现从 i=n 起（种子窗口 [1...n]，跳过 i=n-1 的首窗口），保留此行为
        for i in n..<count {
            guard let av = upSums[i], let bv = downSums[i], let cv = flatSums[i] else { continue }
            let halfFlat = cv / Decimal(2)
            let denom = bv + halfFlat
            if denom > 0 {
                out[i] = Kernels.round8((av + halfFlat) / denom * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "VR(\(n))", values: out)]
    }
}

// MARK: - PVT · 价量趋势（累积型）

public enum PVT: Indicator {
    public static let identifier = "PVT"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return [IndicatorSeries(name: "PVT", values: out)] }
        var acc: Decimal = 0
        out[0] = 0
        for i in 1..<count {
            let prev = kline.closes[i - 1]
            if prev != 0 {
                acc += (kline.closes[i] - prev) / prev * Decimal(kline.volumes[i])
            }
            out[i] = Kernels.round8(acc)
        }
        return [IndicatorSeries(name: "PVT", values: out)]
    }
}

// MARK: - WP-41 v3 第 9 批 · PVT 增量 API（累积式 · 同 OBV 模式 · 无周期 · 第 1 根 PVT=0）

extension PVT: IncrementalIndicator {

    /// state：prevClose（diff 计算）+ acc（流式累积 · 不 round · 输出 round8）
    public struct IncrementalState: Sendable {
        public var prevClose: Decimal?
        public var acc: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(prevClose: nil, acc: 0)
        let count = kline.closes.count
        for i in 0..<count {
            _ = processStep(state: &state, close: kline.closes[i], volume: kline.volumes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, close: newBar.close, volume: newBar.volume)]
    }

    /// 第 1 根：prevClose=nil → 不累加 · acc=0 · 输出 round8(0)=0（与 calculate out[0]=0 一致）
    /// 第 2 根起：close 与 prev 比 · prev != 0 时累加 (close-prev)/prev * volume · 否则 acc 不变
    private static func processStep(state: inout IncrementalState, close: Decimal, volume: Int) -> Decimal? {
        if let prev = state.prevClose, prev != 0 {
            state.acc += (close - prev) / prev * Decimal(volume)
        }
        state.prevClose = close
        return Kernels.round8(state.acc)
    }
}

// MARK: - ADL · 累积/派发线

public enum ADL: Indicator {
    public static let identifier = "ADL"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        var acc: Decimal = 0
        for i in 0..<count {
            let hl = kline.highs[i] - kline.lows[i]
            if hl > 0 {
                let mfm = ((kline.closes[i] - kline.lows[i]) - (kline.highs[i] - kline.closes[i])) / hl
                acc += mfm * Decimal(kline.volumes[i])
            }
            out[i] = Kernels.round8(acc)
        }
        return [IndicatorSeries(name: "ADL", values: out)]
    }
}

// MARK: - VOSC · 成交量振荡 %

public enum VOSC: Indicator {
    public static let identifier = "VOSC"
    public static let category: IndicatorCategory = .volume
    public static let parameters: [IndicatorParameter] = [
        IndicatorParameter(name: "short", defaultValue: 12, minValue: 1, maxValue: 200),
        IndicatorParameter(name: "long", defaultValue: 26, minValue: 2, maxValue: 200)
    ]

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("VOSC 需要 2 参数（short / long）")
        }
        let short = intValue(params[0])
        let long = intValue(params[1])
        guard short >= 1, long > short else {
            throw IndicatorError.invalidParameter("VOSC 参数非法 short=\(short) long=\(long)")
        }
        let volDec = kline.volumes.map { Decimal($0) }
        let eShort = Kernels.ema(volDec, period: short)
        let eLong = Kernels.ema(volDec, period: long)
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if let s = eShort[i], let l = eLong[i], l > 0 {
                out[i] = Kernels.round8((s - l) / l * Decimal(100))
            }
        }
        return [IndicatorSeries(name: "VOSC", values: out)]
    }
}

// MARK: - WP-41 v3 第 12 批 · MFI 增量 API（TP + 双 ring up/dn money flow · 同 CMO 双 ring 思路 + TP/volume 转换层）

extension MFI: IncrementalIndicator {

    /// state：period + prevTP（分桶用 · 第 1 根 nil）+ posRing/negRing + head + count + posSum/negSum
    /// 与 calculate 关键对齐：第 1 根 posMF=0/negMF=0（与 calculate posMF[0]=0 一致 · 入 ring 参与 sum）
    /// 输出守卫：count > period（与 calculate `for i in n..<count` 跳过 i=n-1 首窗口一致）
    public struct IncrementalState: Sendable {
        public let period: Int
        public var prevTP: Decimal?
        public var posRing: [Decimal]
        public var negRing: [Decimal]
        public var head: Int
        public var count: Int
        public var posSum: Decimal
        public var negSum: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        let n = try requireIntParam(params, label: "MFI period")
        var state = IncrementalState(
            period: n,
            prevTP: nil,
            posRing: [Decimal](repeating: 0, count: n),
            negRing: [Decimal](repeating: 0, count: n),
            head: 0, count: 0, posSum: 0, negSum: 0
        )
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i],
                            close: kline.closes[i], volume: kline.volumes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low,
                     close: newBar.close, volume: newBar.volume)]
    }

    /// 第 1 根：prevTP=nil → posMF=negMF=0（与 calculate posMF[0]=0/negMF[0]=0 一致）
    /// 第 2 根起：tp > prevTP → posMF=tp*vol, negMF=0；tp < prevTP → posMF=0, negMF=tp*vol；tp == prevTP → 都 0
    /// ring 满 → sum 增量更新（减旧加新）· 未满 → 旧位置是 0 · 减 0 等价不减 · 仅累加新值
    /// count 单调递增（不封顶 · 与 BOLL/StdDev 不同）· count > period 守卫等价 calculate `for i in n..<count`
    /// （跳过 i=n-1 首窗口 · 种子窗口 [1..n] · 实际起算 i=n 即 count=period+1）
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal, volume: Int) -> Decimal? {
        let tp = (high + low + close) / Decimal(3)
        var posMF: Decimal = 0
        var negMF: Decimal = 0
        if let prev = state.prevTP {
            let mf = tp * Decimal(volume)
            if tp > prev { posMF = mf }
            else if tp < prev { negMF = mf }
        }
        state.prevTP = tp

        // ring 已满（覆盖前先减旧）· 未满时旧位置初值 0 · 不需扣
        if state.count >= state.period {
            state.posSum -= state.posRing[state.head]
            state.negSum -= state.negRing[state.head]
        }
        state.posRing[state.head] = posMF
        state.negRing[state.head] = negMF
        state.head = (state.head + 1) % state.period
        state.posSum += posMF
        state.negSum += negMF
        state.count += 1   // 不封顶 · 用 count > period 守卫跳首窗口

        guard state.count > state.period else { return nil }

        if state.negSum == 0 {
            return 100
        }
        let mr = state.posSum / state.negSum
        return Kernels.round8(Decimal(100) - Decimal(100) / (Decimal(1) + mr))
    }
}

// MARK: - WP-41 v3 第 12 批 · ADL 增量 API（累积/派发 · 同 OBV/PVT 累积式模式 · 无周期 · 无 warm-up）

extension ADL: IncrementalIndicator {

    /// state：acc（流式累积 · 不 round · 输出 round8 · 与 calculate 一致）
    /// 第 1 根直接输出（hl > 0 时也累加 · 与 calculate `for i in 0..<count` 从 i=0 开始一致）
    public struct IncrementalState: Sendable {
        public var acc: Decimal
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(acc: 0)
        let countH = kline.highs.count
        for i in 0..<countH {
            _ = processStep(state: &state, high: kline.highs[i], low: kline.lows[i],
                            close: kline.closes[i], volume: kline.volumes[i])
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, high: newBar.high, low: newBar.low,
                     close: newBar.close, volume: newBar.volume)]
    }

    /// hl == 0（H==L · 一字板）→ acc 不变（与 calculate if hl > 0 守卫一致）
    /// hl > 0 → mfm = ((C-L)-(H-C))/hl · acc += mfm * volume
    private static func processStep(state: inout IncrementalState, high: Decimal, low: Decimal, close: Decimal, volume: Int) -> Decimal? {
        let hl = high - low
        if hl > 0 {
            let mfm = ((close - low) - (high - close)) / hl
            state.acc += mfm * Decimal(volume)
        }
        return Kernels.round8(state.acc)
    }
}

// MARK: - WP-41 v3 第 12 批 · VOSC 增量 API（内嵌 2 EMA · 同 DEMA/TEMA 复合 EMA 模式 · 处理 volume 而非 close）

extension VOSC: IncrementalIndicator {

    /// state：内嵌 2 EMA.IncrementalState（短/长周期 · 处理 volume · 用 advance(close:) 接口）
    /// 输出守卫：short/long 都有值且 long > 0（与 calculate if l > 0 守卫一致）
    public struct IncrementalState: Sendable {
        public var shortEMA: EMA.IncrementalState
        public var longEMA: EMA.IncrementalState
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        guard params.count >= 2 else {
            throw IndicatorError.invalidParameter("VOSC 需要 2 参数（short / long）")
        }
        let short = intValue(params[0])
        let long = intValue(params[1])
        guard short >= 1, long > short else {
            throw IndicatorError.invalidParameter("VOSC 参数非法 short=\(short) long=\(long)")
        }
        // 用空 KLineSeries 构造 2 EMA state 的初值 · 然后手动迭代 volume 历史调 advance（不能直传 EMA.makeIncrementalState · EMA 用 closes）
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var shortState = try EMA.makeIncrementalState(kline: empty, params: [Decimal(short)])
        var longState = try EMA.makeIncrementalState(kline: empty, params: [Decimal(long)])
        for vol in kline.volumes {
            _ = shortState.advance(close: Decimal(vol))
            _ = longState.advance(close: Decimal(vol))
        }
        return IncrementalState(shortEMA: shortState, longEMA: longState)
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        let vol = Decimal(newBar.volume)
        let s = state.shortEMA.advance(close: vol)
        let l = state.longEMA.advance(close: vol)
        // EMA.advance 已 round8 · 与 calculate Kernels.ema 输出一致 · 直接用作 (s-l)/l 即可
        guard let sv = s, let lv = l, lv > 0 else { return [nil] }
        return [Kernels.round8((sv - lv) / lv * Decimal(100))]
    }
}
