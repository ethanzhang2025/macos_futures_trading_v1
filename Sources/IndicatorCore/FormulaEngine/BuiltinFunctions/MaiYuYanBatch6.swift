// 麦语言扩展 · 第 6 批（v15.25 batch13 · ~99.8% → ~99.9% 兼容度）
//
// 7 个 trader 实用函数（情绪 / 乖离 / 量能 / 均线变种）：
//   1. PSY(N)    — Psychological Line · 心理线（中国市场情绪指标）
//   2. BIAS(N)   — 乖离率 = (C - MA(C,N))/MA(C,N) * 100（远离均线超买超卖）
//   3. VR(N)     — Volume Ratio · 量比（量能强度）
//   4. DPO(N)    — Detrended Price Oscillator（去趋势价格振荡）
//   5. HMA(N)    — Hull Moving Average（极快平滑 · trader 进阶）
//   6. DEMA(X,N) — Double EMA = 2*E1 - E2（比 TEMA 滞后多）
//   7. OSC(N,M)  — Price Oscillator = (MA(C,N) - MA(C,M))/MA(C,M)*100

import Foundation

// MARK: - 1. PSY

/// PSY — 心理线
/// 公式：PSY(N) = COUNT(CLOSE > REF(CLOSE, 1), N) / N * 100
/// 范围 [0, 100] · 经验：> 75 超买 / < 25 超卖
struct PSYFunction: BuiltinFunction {
    let name = "PSY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PSY需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PSY的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PSY的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var ups = 0
            for j in start...i {
                if bars[j].close > bars[j - 1].close { ups += 1 }
            }
            let len = i - start + 1
            result[i] = Decimal(ups) / Decimal(len) * 100
        }
        return result
    }
}

// MARK: - 2. BIAS

/// BIAS — 乖离率
/// 公式：BIAS(N) = (CLOSE - MA(CLOSE, N)) / MA(CLOSE, N) * 100
/// 经验：BIAS6 > 6 短期超买 / BIAS6 < -6 短期超卖（不同周期阈值不同）
struct BIASFunction: BuiltinFunction {
    let name = "BIAS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "BIAS需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "BIAS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BIAS的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            let ma = sum / Decimal(i - start + 1)
            guard ma != 0 else { continue }
            result[i] = (bars[i].close - ma) / ma * 100
        }
        return result
    }
}

// MARK: - 3. VR

/// VR — Volume Ratio · 量比
/// 公式：VR(N) = (上涨成交量之和 + 平盘成交量之和/2) / (下跌成交量之和 + 平盘成交量之和/2) * 100
/// 经验：> 160 多头强 / < 40 空头强 / 70-100 弱平衡
struct VRFunction: BuiltinFunction {
    let name = "VR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "VR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "VR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "VR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var upVol: Decimal = 0
            var downVol: Decimal = 0
            var flatVol: Decimal = 0
            for j in start...i {
                let v = Decimal(bars[j].volume)
                if bars[j].close > bars[j - 1].close { upVol += v }
                else if bars[j].close < bars[j - 1].close { downVol += v }
                else { flatVol += v }
            }
            let half = flatVol / 2
            let denom = downVol + half
            guard denom > 0 else {
                result[i] = upVol > 0 ? Decimal(string: "999")! : 0
                continue
            }
            result[i] = (upVol + half) / denom * 100
        }
        return result
    }
}

// MARK: - 4. DPO

/// DPO — Detrended Price Oscillator · 去趋势价格振荡
/// 公式：DPO(N) = CLOSE - REF(MA(CLOSE, N), N/2 + 1)
/// 用途：消除长趋势 · 突出短期循环
struct DPOFunction: BuiltinFunction {
    let name = "DPO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "DPO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "DPO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DPO的周期必须为正整数")
        }
        let shift = period / 2 + 1

        let count = bars.count
        // MA
        var ma = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            ma[i] = sum / Decimal(i - start + 1)
        }

        // DPO = CLOSE - REF(MA, shift)
        var result = [Decimal?](repeating: nil, count: count)
        for i in shift..<count {
            guard let prevMA = ma[i - shift] else { continue }
            result[i] = bars[i].close - prevMA
        }
        return result
    }
}

// MARK: - 5. HMA

/// HMA — Hull Moving Average · Alan Hull 极快平滑
/// 公式：HMA(N) = WMA(2*WMA(C, N/2) - WMA(C, N), sqrt(N))
/// 用途：trader 减少滞后 · 比 EMA 快很多
struct HMAFunction: BuiltinFunction {
    let name = "HMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "HMA需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "HMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "HMA的周期必须为正整数")
        }

        let halfPeriod = max(1, period / 2)
        let sqrtPeriod = max(1, Int(sqrt(Double(period)).rounded()))

        let close = bars.map { Optional($0.close) }
        let wmaHalf = WMACompute.wma(close, period: halfPeriod)
        let wmaFull = WMACompute.wma(close, period: period)

        // diff = 2*WMA(N/2) - WMA(N)
        let count = bars.count
        var diff = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let h = wmaHalf[i], let f = wmaFull[i] else { continue }
            diff[i] = 2 * h - f
        }

        // HMA = WMA(diff, sqrt(N))
        return WMACompute.wma(diff, period: sqrtPeriod)
    }
}

// MARK: - 6. DEMA

/// DEMA — Double EMA = 2*E1 - E2
/// 比 TEMA 简单 · 比 EMA 滞后小但比 TEMA 多
struct DEMAFunction: BuiltinFunction {
    let name = "DEMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "DEMA需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "DEMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DEMA的周期必须为正整数")
        }

        let e1 = DEMAEMA.ema(source, period: period)
        let e2 = DEMAEMA.ema(e1, period: period)

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let v1 = e1[i], let v2 = e2[i] else { continue }
            result[i] = 2 * v1 - v2
        }
        return result
    }
}

// MARK: - 7. OSC

/// OSC — Price Oscillator
/// 公式：OSC(N, M) = (MA(CLOSE, N) - MA(CLOSE, M)) / MA(CLOSE, M) * 100
/// 即短期均线相对长期均线的偏离百分比 · 与 MACD 思想类似
/// 经验：上穿 0 入场 / 下穿 0 离场
struct OSCFunction: BuiltinFunction {
    let name = "OSC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "OSC需要2个参数（短周期N, 长周期M）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let mVal = args[1].first, let m = mVal else {
            throw InterpreterError(message: "OSC的周期参数无效")
        }
        let pn = Int(truncating: n as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pn > 0, pm > 0 else {
            throw InterpreterError(message: "OSC的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let startN = max(0, i - pn + 1)
            let startM = max(0, i - pm + 1)
            var sumN: Decimal = 0
            var sumM: Decimal = 0
            for j in startN...i { sumN += bars[j].close }
            for j in startM...i { sumM += bars[j].close }
            let maN = sumN / Decimal(i - startN + 1)
            let maM = sumM / Decimal(i - startM + 1)
            guard maM != 0 else { continue }
            result[i] = (maN - maM) / maM * 100
        }
        return result
    }
}

// MARK: - 内部 helpers（与之前批次隔离 · 避免命名冲突）

private enum WMACompute {
    /// 加权移动平均：weights = 1, 2, ..., N
    static func wma(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var weightSum: Decimal = 0
            var w: Decimal = 1
            for j in start...i {
                guard let v = src[j] else { continue }
                sum += v * w
                weightSum += w
                w += 1
            }
            if weightSum > 0 {
                result[i] = sum / weightSum
            }
        }
        return result
    }
}

private enum DEMAEMA {
    static func ema(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        let multiplier = Decimal(2) / Decimal(period + 1)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = multiplier * v + (1 - multiplier) * prev!
            }
            result[i] = prev
        }
        return result
    }
}
