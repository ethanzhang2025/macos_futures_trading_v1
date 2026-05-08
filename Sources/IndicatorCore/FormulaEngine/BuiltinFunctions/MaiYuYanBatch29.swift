// 麦语言扩展 · 第 29 批（v15.25 batch36 · 健壮统计 + 风险指标 + 综合信号）
//
// 7 个进阶分析函数：
//   1. MAD(X, N)              — Median Absolute Deviation 中位数绝对偏差
//   2. SORTINO(X, N)          — Sortino Ratio = mean / down std
//   3. CALMAR(X, N)           — Calmar Ratio = mean / MAXDDPCT
//   4. RUNUP(X)               — 累计最大上涨（low 到 high）
//   5. RECOVERY(X)            — 从最低点反弹幅度
//   6. TRENDSTRENGTH(N)       — 趋势强度 = abs(C[i] - C[i-N]) / N
//   7. MACROSS(N1, N2)        — MA 交叉综合信号（1=金叉 -1=死叉 0=无）

import Foundation

// MARK: - 1. MAD

/// MAD(X, N) — Median Absolute Deviation
/// 公式：MEDIAN(|X[j] - MEDIAN(X[start..i])|, N)
/// 健壮版离散度（不受极端值影响）
struct MADFunction: BuiltinFunction {
    let name = "MAD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAD需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "MAD的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MAD的周期必须为正整数")
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
            let median = MaiB29Stats.median(values)
            var deviations: [Decimal] = []
            for v in values { deviations.append(abs(v - median)) }
            result[i] = MaiB29Stats.median(deviations)
        }
        return result
    }
}

// MARK: - 2. SORTINO

/// SORTINO(X, N) — Sortino Ratio = mean(returns) / std(downside returns)
/// 与 SHARPE 的差别：只考虑负收益的标准差（不惩罚上涨波动）
struct SORTINOFunction: BuiltinFunction {
    let name = "SORTINO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SORTINO需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "SORTINO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "SORTINO的周期必须为正整数")
        }

        let count = source.count
        // returns
        var ret = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1], prev != 0 else { continue }
            ret[i] = (curr - prev) / prev
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(1, i - period + 1)
            guard start <= i else { continue }
            var all: [Decimal] = []
            var down: [Decimal] = []
            for j in start...i {
                if let v = ret[j] {
                    all.append(v)
                    if v < 0 { down.append(v) }
                }
            }
            guard !all.isEmpty else { continue }
            let mean = all.reduce(Decimal(0), +) / Decimal(all.count)
            // Downside std
            guard !down.isEmpty else { continue }
            var sq: Decimal = 0
            for v in down { sq += v * v }  // 0 为基线
            let variance = sq / Decimal(down.count)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD > 0 else { continue }
            let downStd = Decimal(sqrt(varD))
            guard downStd > 0 else { continue }
            result[i] = mean / downStd
        }
        return result
    }
}

// MARK: - 3. CALMAR

/// CALMAR(X, N) — Calmar Ratio = mean(returns) * 100 / MAXDDPCT
/// 用途：回撤调整后收益（越大越好）
struct CALMARFunction: BuiltinFunction {
    let name = "CALMAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CALMAR需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "CALMAR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CALMAR的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            // mean returns（i < start+1 时跳过，避免 ClosedRange trap）
            var rets: [Decimal] = []
            if start + 1 <= i {
                for j in (start + 1)...i {
                    guard let curr = source[j], let prev = source[j - 1], prev != 0 else { continue }
                    rets.append((curr - prev) / prev)
                }
            }
            guard !rets.isEmpty else { continue }
            let mean = rets.reduce(Decimal(0), +) / Decimal(rets.count)

            // MAXDDPCT
            var maxDDPct: Decimal = 0
            var runningMax: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if runningMax == nil || v > runningMax! { runningMax = v }
                if let m = runningMax, m > 0 {
                    let ddPct = (m - v) / m
                    if ddPct > maxDDPct { maxDDPct = ddPct }
                }
            }
            guard maxDDPct > 0 else { continue }
            result[i] = mean / maxDDPct
        }
        return result
    }
}

// MARK: - 4. RUNUP

/// RUNUP(X) — 累计最大上涨（low 到 high）
/// 公式：max over j <= i 的 X[i] - min(X[k] for k <= j)
struct RUNUPFunction: BuiltinFunction {
    let name = "RUNUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RUNUP需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var runningMin: Decimal?
        var maxRunUp: Decimal = 0
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if runningMin == nil || v < runningMin! { runningMin = v }
            if let m = runningMin {
                let runUp = v - m
                if runUp > maxRunUp { maxRunUp = runUp }
            }
            result[i] = maxRunUp
        }
        return result
    }
}

// MARK: - 5. RECOVERY

/// RECOVERY(X) — 从历史最低点反弹幅度 = X[i] - LLV(X, i)
struct RECOVERYFunction: BuiltinFunction {
    let name = "RECOVERY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RECOVERY需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var runningMin: Decimal?
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if runningMin == nil || v < runningMin! { runningMin = v }
            if let m = runningMin {
                result[i] = v - m
            }
        }
        return result
    }
}

// MARK: - 6. TRENDSTRENGTH

/// TRENDSTRENGTH(N) — 趋势强度 = abs(C[i] - C[i-N]) / N
/// 单位：每根 bar 平均价格变化幅度（绝对值）
struct TRENDSTRENGTHFunction: BuiltinFunction {
    let name = "TRENDSTRENGTH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "TRENDSTRENGTH需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "TRENDSTRENGTH的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TRENDSTRENGTH的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            let diff = bars[i].close - bars[i - period].close
            result[i] = abs(diff) / Decimal(period)
        }
        return result
    }
}

// MARK: - 7. MACROSS

/// MACROSS(N1, N2) — MA 双线综合信号
/// 1 = 金叉（短上穿长）/ -1 = 死叉（短下穿长）/ 0 = 无变化
struct MACROSSFunction: BuiltinFunction {
    let name = "MACROSS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MACROSS需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "MACROSS的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "MACROSS的周期必须为正整数")
        }

        let count = bars.count
        // MAs
        var ma1 = [Decimal?](repeating: nil, count: count)
        var ma2 = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s1 = max(0, i - p1 + 1)
            let s2 = max(0, i - p2 + 1)
            var sum1: Decimal = 0
            var sum2: Decimal = 0
            for j in s1...i { sum1 += bars[j].close }
            for j in s2...i { sum2 += bars[j].close }
            ma1[i] = sum1 / Decimal(i - s1 + 1)
            ma2[i] = sum2 / Decimal(i - s2 + 1)
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let m1 = ma1[i], let m2 = ma2[i],
                  let p1Prev = ma1[i - 1], let p2Prev = ma2[i - 1] else { continue }
            if p1Prev < p2Prev && m1 >= m2 {
                result[i] = 1  // 金叉
            } else if p1Prev > p2Prev && m1 <= m2 {
                result[i] = -1 // 死叉
            } else {
                result[i] = 0
            }
        }
        return result
    }
}

// MARK: - 内部 helpers

private enum MaiB29Stats {
    /// 取中位数（数组拷贝排序 · O(N log N)）
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
