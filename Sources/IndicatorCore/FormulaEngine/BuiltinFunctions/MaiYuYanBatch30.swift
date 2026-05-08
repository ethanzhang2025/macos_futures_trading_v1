// 麦语言扩展 · 第 30 批（v15.25 batch37 · 距离统计 + 健壮算法）
//
// 7 个分析辅助函数：
//   1. HHVDIST(N)             — 距 HHV(H, N) 的距离 = HHV - CLOSE
//   2. LLVDIST(N)             — 距 LLV(L, N) 的距离 = CLOSE - LLV
//   3. FREQRATIO(X, lvl, N)   — N 内 X > lvl 的根数 / N
//   4. MEDIANSLOPE(X, N)      — 中位数斜率（健壮 SLOPE）
//   5. TRIMMEAN(X, N, pct)    — 截尾均值（去掉 pct% 极端）
//   6. MAXSTREAK(X, N)        — N 内最长连续 X 非零的根数
//   7. TIMEINRANGE(X, lo, hi, N) — N 内 X ∈ [lo, hi] 的根数

import Foundation

// MARK: - 1. HHVDIST

/// HHVDIST(N) — 距 N 周期最高的距离 = HHV(H, N) - CLOSE
/// 0 = 创新高时 · 越大表示偏离最高越远
struct HHVDISTFunction: BuiltinFunction {
    let name = "HHVDIST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "HHVDIST需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "HHVDIST的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "HHVDIST的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
            }
            result[i] = hi - bars[i].close
        }
        return result
    }
}

// MARK: - 2. LLVDIST

/// LLVDIST(N) — 距 N 周期最低的距离 = CLOSE - LLV(L, N)
struct LLVDISTFunction: BuiltinFunction {
    let name = "LLVDIST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "LLVDIST需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "LLVDIST的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LLVDIST的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var lo = bars[start].low
            for j in start...i {
                if bars[j].low < lo { lo = bars[j].low }
            }
            result[i] = bars[i].close - lo
        }
        return result
    }
}

// MARK: - 3. FREQRATIO

/// FREQRATIO(X, level, N) — N 内 X > level 的根数 / N
/// 范围 [0, 1] · trader 用：N 内 RSI 高于 70 的比率（超买频率）
struct FREQRATIOFunction: BuiltinFunction {
    let name = "FREQRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "FREQRATIO需要3个参数（X, level, N）")
        }
        let source = args[0]
        guard let lvlV = args[1].first, let level = lvlV,
              let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "FREQRATIO的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "FREQRATIO的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hits = 0
            var total = 0
            for j in start...i {
                guard let v = source[j] else { continue }
                total += 1
                if v > level { hits += 1 }
            }
            guard total > 0 else { continue }
            result[i] = Decimal(hits) / Decimal(total)
        }
        return result
    }
}

// MARK: - 4. MEDIANSLOPE

/// MEDIANSLOPE(X, N) — 中位数斜率（健壮版 SLOPE · 不受异常值影响）
/// 公式：MEDIAN(X[i] - X[i-1] for i in window)
struct MEDIANSLOPEFunction: BuiltinFunction {
    let name = "MEDIANSLOPE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MEDIANSLOPE需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "MEDIANSLOPE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MEDIANSLOPE的周期必须为正整数")
        }

        let count = source.count
        var diffs = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1] else { continue }
            diffs[i] = curr - prev
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(1, i - period + 1)
            guard start <= i else { continue }
            var values: [Decimal] = []
            for j in start...i {
                if let v = diffs[j] { values.append(v) }
            }
            guard !values.isEmpty else { continue }
            result[i] = MaiB30Stats.median(values)
        }
        return result
    }
}

// MARK: - 5. TRIMMEAN

/// TRIMMEAN(X, N, pct) — 截尾均值（去掉 pct% 最大和最小后求平均）
/// 例：pct=10 表示去掉最大 10% 和最小 10% 后求平均
struct TRIMMEANFunction: BuiltinFunction {
    let name = "TRIMMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "TRIMMEAN需要3个参数（X, N, pct%）")
        }
        let source = args[0]
        guard let nV = args[1].first, let n = nV,
              let pctV = args[2].first, let pct = pctV else {
            throw InterpreterError(message: "TRIMMEAN的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TRIMMEAN的周期必须为正整数")
        }
        let pctD = NSDecimalNumber(decimal: pct).doubleValue
        guard pctD >= 0, pctD < 50 else {
            throw InterpreterError(message: "TRIMMEAN的 pct 必须 ∈ [0, 50)")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var values: [Decimal] = []
            for j in start...i {
                if let v = source[j] { values.append(v) }
            }
            guard !values.isEmpty else { continue }
            let sorted = values.sorted()
            let trim = Int(Double(sorted.count) * pctD / 100)
            let safeStart = trim
            let safeEnd = sorted.count - trim
            guard safeEnd > safeStart else { continue }
            let trimmed = sorted[safeStart..<safeEnd]
            let sum = trimmed.reduce(Decimal(0), +)
            result[i] = sum / Decimal(trimmed.count)
        }
        return result
    }
}

// MARK: - 6. MAXSTREAK

/// MAXSTREAK(X, N) — N 内最长连续 X 非零的根数
struct MAXSTREAKFunction: BuiltinFunction {
    let name = "MAXSTREAK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAXSTREAK需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "MAXSTREAK的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MAXSTREAK的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var maxStreak = 0
            var current = 0
            for j in start...i {
                if let v = source[j], v != 0 {
                    current += 1
                    if current > maxStreak { maxStreak = current }
                } else {
                    current = 0
                }
            }
            result[i] = Decimal(maxStreak)
        }
        return result
    }
}

// MARK: - 7. TIMEINRANGE

/// TIMEINRANGE(X, lo, hi, N) — N 内 X ∈ [lo, hi] 的根数
struct TIMEINRANGEFunction: BuiltinFunction {
    let name = "TIMEINRANGE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 4 else {
            throw InterpreterError(message: "TIMEINRANGE需要4个参数（X, lo, hi, N）")
        }
        let source = args[0]
        guard let loV = args[1].first, let lo = loV,
              let hiV = args[2].first, let hi = hiV,
              let nV = args[3].first, let n = nV else {
            throw InterpreterError(message: "TIMEINRANGE的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TIMEINRANGE的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hits = 0
            for j in start...i {
                guard let v = source[j] else { continue }
                if v >= lo && v <= hi { hits += 1 }
            }
            result[i] = Decimal(hits)
        }
        return result
    }
}

// MARK: - 内部 helpers

private enum MaiB30Stats {
    static func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        let n = sorted.count
        guard n > 0 else { return 0 }
        if n % 2 == 1 {
            return sorted[n / 2]
        } else {
            return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        }
    }
}
