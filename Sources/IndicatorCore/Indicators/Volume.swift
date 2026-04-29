// WP-41 第二批 · 量价类 7 指标（除 OBV 已在独立文件）
// Volume / MFI / CMF / VR / PVT / ADL / VOSC
//
// WP-41 v3 第 9 批：PVT 实现 IncrementalIndicator · 累积式（同 OBV 模式 · 无周期）

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
