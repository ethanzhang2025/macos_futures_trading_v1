// 麦语言扩展 · 第 14 批（v15.25 batch21 · MACD/BOLL/KDJ 三件套独立函数）
//
// trader 必看三件套独立函数（之前需要用户自己写多语句 · 现在一行调用）：
//   1. MACDDIF(F, S)         — MACD DIF = EMA(C, F) - EMA(C, S)
//   2. MACDDEA(F, S, M)      — MACD DEA = EMA(DIF, M)
//   3. MACDBAR(F, S, M)      — MACD 柱 = 2*(DIF - DEA)
//   4. BOLLM(N)              — 布林带中线 = MA(C, N)
//   5. BOLLU(N, K)           — 布林带上轨 = MID + K*STD
//   6. BOLLL(N, K)           — 布林带下轨 = MID - K*STD
//   7. KDJK(N, M)            — KDJ K 线 = SMA(RSV, M, 1)

import Foundation

// MARK: - 1. MACDDIF

/// MACDDIF — DIFF = EMA(CLOSE, F) - EMA(CLOSE, S)
/// 默认 F=12, S=26（trader 标准）
struct MACDDIFFunction: BuiltinFunction {
    let name = "MACDDIF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MACDDIF需要2个参数（F, S）")
        }
        guard let fV = args[0].first, let f = fV,
              let sV = args[1].first, let s = sV else {
            throw InterpreterError(message: "MACDDIF的参数无效")
        }
        let pf = Int(truncating: f as NSDecimalNumber)
        let ps = Int(truncating: s as NSDecimalNumber)
        guard pf > 0, ps > 0 else {
            throw InterpreterError(message: "MACDDIF的周期必须为正整数")
        }

        let close = bars.map { Optional($0.close) }
        let emaF = MaiB14EMA.ema(close, period: pf)
        let emaS = MaiB14EMA.ema(close, period: ps)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let f = emaF[i], let s = emaS[i] else { continue }
            result[i] = f - s
        }
        return result
    }
}

// MARK: - 2. MACDDEA

/// MACDDEA — DEA = EMA(DIFF, M)
struct MACDDEAFunction: BuiltinFunction {
    let name = "MACDDEA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "MACDDEA需要3个参数（F, S, M）")
        }
        guard let fV = args[0].first, let f = fV,
              let sV = args[1].first, let s = sV,
              let mV = args[2].first, let m = mV else {
            throw InterpreterError(message: "MACDDEA的参数无效")
        }
        let pf = Int(truncating: f as NSDecimalNumber)
        let ps = Int(truncating: s as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pf > 0, ps > 0, pm > 0 else {
            throw InterpreterError(message: "MACDDEA的周期必须为正整数")
        }

        let close = bars.map { Optional($0.close) }
        let emaF = MaiB14EMA.ema(close, period: pf)
        let emaS = MaiB14EMA.ema(close, period: ps)
        let count = bars.count
        var dif = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let f = emaF[i], let s = emaS[i] else { continue }
            dif[i] = f - s
        }
        return MaiB14EMA.ema(dif, period: pm)
    }
}

// MARK: - 3. MACDBAR

/// MACDBAR — MACD 柱 = 2 * (DIFF - DEA)
struct MACDBARFunction: BuiltinFunction {
    let name = "MACDBAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "MACDBAR需要3个参数（F, S, M）")
        }
        guard let fV = args[0].first, let f = fV,
              let sV = args[1].first, let s = sV,
              let mV = args[2].first, let m = mV else {
            throw InterpreterError(message: "MACDBAR的参数无效")
        }
        let pf = Int(truncating: f as NSDecimalNumber)
        let ps = Int(truncating: s as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pf > 0, ps > 0, pm > 0 else {
            throw InterpreterError(message: "MACDBAR的周期必须为正整数")
        }

        let close = bars.map { Optional($0.close) }
        let emaF = MaiB14EMA.ema(close, period: pf)
        let emaS = MaiB14EMA.ema(close, period: ps)
        let count = bars.count
        var dif = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let fv = emaF[i], let sv = emaS[i] else { continue }
            dif[i] = fv - sv
        }
        let dea = MaiB14EMA.ema(dif, period: pm)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let d = dif[i], let e = dea[i] else { continue }
            result[i] = 2 * (d - e)
        }
        return result
    }
}

// MARK: - 4. BOLLM

/// BOLLM — 布林带中线 = MA(CLOSE, N)
struct BOLLMFunction: BuiltinFunction {
    let name = "BOLLM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "BOLLM需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "BOLLM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BOLLM的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            result[i] = sum / Decimal(i - start + 1)
        }
        return result
    }
}

// MARK: - 5. BOLLU

/// BOLLU — 布林带上轨 = MID + K * STD(CLOSE, N)
struct BOLLUFunction: BuiltinFunction {
    let name = "BOLLU"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "BOLLU需要2个参数（N, K倍数）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let kVal = args[1].first, let k = kVal else {
            throw InterpreterError(message: "BOLLU的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BOLLU的周期必须为正整数")
        }
        return MaiB14BOLL.compute(bars: bars, period: period, k: k, isUpper: true)
    }
}

// MARK: - 6. BOLLL

/// BOLLL — 布林带下轨 = MID - K * STD(CLOSE, N)
struct BOLLLFunction: BuiltinFunction {
    let name = "BOLLL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "BOLLL需要2个参数（N, K倍数）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let kVal = args[1].first, let k = kVal else {
            throw InterpreterError(message: "BOLLL的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BOLLL的周期必须为正整数")
        }
        return MaiB14BOLL.compute(bars: bars, period: period, k: k, isUpper: false)
    }
}

// MARK: - 7. KDJK

/// KDJK — KDJ K 线 = SMA(RSV, M, 1)
/// RSV = (CLOSE - LLV(LOW, N)) / (HHV(HIGH, N) - LLV(LOW, N)) * 100
/// SMA(X, N, 1) 等价 Wilder smoothing α=1/N
struct KDJKFunction: BuiltinFunction {
    let name = "KDJK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "KDJK需要2个参数（N RSV周期, M K平滑周期）")
        }
        guard let nV = args[0].first, let n = nV,
              let mV = args[1].first, let m = mV else {
            throw InterpreterError(message: "KDJK的参数无效")
        }
        let pn = Int(truncating: n as NSDecimalNumber)
        let pm = Int(truncating: m as NSDecimalNumber)
        guard pn > 0, pm > 0 else {
            throw InterpreterError(message: "KDJK的周期必须为正整数")
        }

        let count = bars.count
        // RSV
        var rsv = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - pn + 1)
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0 else { continue }
            rsv[i] = (bars[i].close - lo) / span * 100
        }
        // K = SMA(RSV, M, 1)
        return MaiB14SMA.smooth(rsv, period: pm, weight: 1)
    }
}

// MARK: - 内部 helpers

private enum MaiB14EMA {
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

private enum MaiB14SMA {
    /// SMA(X, N, M) = (M * X[i] + (N-M) * SMA[i-1]) / N
    static func smooth(_ src: [Decimal?], period: Int, weight: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, weight > 0, count > 0 else { return result }
        let nDec = Decimal(period)
        let mDec = Decimal(weight)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = (mDec * v + (nDec - mDec) * prev!) / nDec
            }
            result[i] = prev
        }
        return result
    }
}

private enum MaiB14BOLL {
    static func compute(bars: [BarData], period: Int, k: Decimal, isUpper: Bool) -> [Decimal?] {
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            let mean = sum / Decimal(i - start + 1)
            var sqSum: Decimal = 0
            for j in start...i {
                let diff = bars[j].close - mean
                sqSum += diff * diff
            }
            let variance = sqSum / Decimal(i - start + 1)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0 else { continue }
            let std = Decimal(sqrt(varD))
            result[i] = isUpper ? (mean + k * std) : (mean - k * std)
        }
        return result
    }
}
