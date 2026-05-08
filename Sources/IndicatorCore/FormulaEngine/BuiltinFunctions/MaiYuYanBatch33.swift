// 麦语言扩展 · 第 33 批（v15.25 batch40 · 综合信号 · 背离 + 评分）
//
// 7 个综合信号函数：
//   1. DIVERGENCE(X, Y, N)    — 背离判定（X 创高 Y 没创 = -1 / X 创低 Y 没创 = 1 / 无 = 0）
//   2. TRENDSCORE(N)          — 趋势评分（短长 MA 排列 + slope）
//   3. MOMENTUMSCORE(N)       — 动量评分（ROC + RSI - 50）
//   4. VOLATILITYRANK(N)      — 波动率百分位（基于 STD）
//   5. PRICELEVEL(N)          — 价格位置（在 N 内 [LLV, HHV] 的百分比）
//   6. CROSSCOUNT(X, Y, N)    — N 内 X 穿越 Y 的次数（金叉+死叉）
//   7. SIGNALSTRENGTH(X, N)   — 信号强度（X 偏离 0 的标准差倍数）

import Foundation

// MARK: - 1. DIVERGENCE

/// DIVERGENCE(X, Y, N) — 背离判定
/// 看跌背离（-1）：X 创 N 内新高 但 Y 没创新高
/// 看涨背离（1）：X 创 N 内新低 但 Y 没创新低
/// 无背离（0）
struct DIVERGENCEFunction: BuiltinFunction {
    let name = "DIVERGENCE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "DIVERGENCE需要3个参数（X, Y, N）")
        }
        let x = args[0]
        let y = args[1]
        guard let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "DIVERGENCE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "DIVERGENCE的周期必须为正整数")
        }
        guard x.count == y.count else {
            throw InterpreterError(message: "DIVERGENCE的X和Y长度必须一致")
        }

        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            guard start < i, let xCurr = x[i], let yCurr = y[i] else {
                result[i] = 0
                continue
            }
            // X 历史最高 / 最低（不含当前）
            var xPrevMax: Decimal?
            var xPrevMin: Decimal?
            var yPrevMax: Decimal?
            var yPrevMin: Decimal?
            for j in start..<i {
                if let xv = x[j] {
                    if xPrevMax == nil || xv > xPrevMax! { xPrevMax = xv }
                    if xPrevMin == nil || xv < xPrevMin! { xPrevMin = xv }
                }
                if let yv = y[j] {
                    if yPrevMax == nil || yv > yPrevMax! { yPrevMax = yv }
                    if yPrevMin == nil || yv < yPrevMin! { yPrevMin = yv }
                }
            }
            // 看跌背离：X 创新高 + Y 没创新高
            if let xPM = xPrevMax, let yPM = yPrevMax,
               xCurr > xPM && yCurr <= yPM {
                result[i] = -1
            }
            // 看涨背离：X 创新低 + Y 没创新低
            else if let xPMi = xPrevMin, let yPMi = yPrevMin,
                    xCurr < xPMi && yCurr >= yPMi {
                result[i] = 1
            } else {
                result[i] = 0
            }
        }
        return result
    }
}

// MARK: - 2. TRENDSCORE

/// TRENDSCORE(N) — 趋势评分
/// 综合：MA(C, N/2) > MA(C, N) ? +1 : -1
///       MA(C, N) 上升 ? +1 : -1
/// 总分 ∈ [-2, 2]
struct TRENDSCOREFunction: BuiltinFunction {
    let name = "TRENDSCORE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "TRENDSCORE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "TRENDSCORE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else {
            throw InterpreterError(message: "TRENDSCORE的周期必须 > 1")
        }
        let halfPeriod = max(2, period / 2)

        let count = bars.count
        // MA short / long
        let maShort = MaiB33MA.ma(bars: bars, period: halfPeriod)
        let maLong = MaiB33MA.ma(bars: bars, period: period)

        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let s = maShort[i], let l = maLong[i],
                  let lPrev = maLong[i - 1] else { continue }
            var score: Decimal = 0
            score += s > l ? 1 : -1
            score += l > lPrev ? 1 : -1
            result[i] = score
        }
        return result
    }
}

// MARK: - 3. MOMENTUMSCORE

/// MOMENTUMSCORE(N) — 动量评分
/// 公式：sign(ROC(N)) + sign(C - MA(C, N))
/// 范围 ∈ [-2, 2]
struct MOMENTUMSCOREFunction: BuiltinFunction {
    let name = "MOMENTUMSCORE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "MOMENTUMSCORE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "MOMENTUMSCORE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MOMENTUMSCORE的周期必须为正整数")
        }

        let count = bars.count
        let ma = MaiB33MA.ma(bars: bars, period: period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in period..<count {
            let prevC = bars[i - period].close
            guard prevC != 0, let m = ma[i] else { continue }
            var score: Decimal = 0
            // sign(ROC)
            if bars[i].close > prevC { score += 1 }
            else if bars[i].close < prevC { score -= 1 }
            // sign(C - MA)
            if bars[i].close > m { score += 1 }
            else if bars[i].close < m { score -= 1 }
            result[i] = score
        }
        return result
    }
}

// MARK: - 4. VOLATILITYRANK

/// VOLATILITYRANK(N) — 波动率百分位
/// 公式：当前 STD 在 N 内的百分位 / 100
/// 范围 [0, 1]
struct VOLATILITYRANKFunction: BuiltinFunction {
    let name = "VOLATILITYRANK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "VOLATILITYRANK需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "VOLATILITYRANK的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else {
            throw InterpreterError(message: "VOLATILITYRANK的周期必须 > 1")
        }

        let count = bars.count
        // STD on close per bar (over short window 5)
        let shortWindow = max(2, period / 4)
        var std = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - shortWindow + 1)
            var sum: Decimal = 0
            for j in s...i { sum += bars[j].close }
            let mean = sum / Decimal(i - s + 1)
            var sq: Decimal = 0
            for j in s...i {
                let d = bars[j].close - mean
                sq += d * d
            }
            let varD = NSDecimalNumber(decimal: sq / Decimal(i - s + 1)).doubleValue
            guard varD >= 0 else { continue }
            std[i] = Decimal(sqrt(varD))
        }

        // PercentRank of std over N
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let curr = std[i] else { continue }
            let s = max(0, i - period + 1)
            var leOrEq = 0
            var total = 0
            for j in s...i {
                guard let v = std[j] else { continue }
                total += 1
                if v <= curr { leOrEq += 1 }
            }
            guard total > 0 else { continue }
            result[i] = Decimal(leOrEq) / Decimal(total)
        }
        return result
    }
}

// MARK: - 5. PRICELEVEL

/// PRICELEVEL(N) — 价格在 N 内 [LLV, HHV] 的位置
/// 公式：(C - LLV(L, N)) / (HHV(H, N) - LLV(L, N))
/// 范围 [0, 1]
struct PRICELEVELFunction: BuiltinFunction {
    let name = "PRICELEVEL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PRICELEVEL需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PRICELEVEL的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PRICELEVEL的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var hi = bars[s].high
            var lo = bars[s].low
            for j in s...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0 else { continue }
            result[i] = (bars[i].close - lo) / span
        }
        return result
    }
}

// MARK: - 6. CROSSCOUNT

/// CROSSCOUNT(X, Y, N) — N 内 X 穿越 Y 的次数（金叉+死叉总和）
struct CROSSCOUNTFunction: BuiltinFunction {
    let name = "CROSSCOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "CROSSCOUNT需要3个参数（X, Y, N）")
        }
        let x = args[0]
        let y = args[1]
        guard let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "CROSSCOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CROSSCOUNT的周期必须为正整数")
        }
        guard x.count == y.count else {
            throw InterpreterError(message: "CROSSCOUNT的X和Y长度必须一致")
        }

        let count = x.count
        var crosses = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let xc = x[i], let yc = y[i],
                  let xp = x[i - 1], let yp = y[i - 1] else {
                crosses[i] = 0
                continue
            }
            let goldenCross = xp < yp && xc >= yc
            let deadCross = xp > yp && xc <= yc
            crosses[i] = (goldenCross || deadCross) ? 1 : 0
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i {
                if let v = crosses[j] { sum += v }
            }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 7. SIGNALSTRENGTH

/// SIGNALSTRENGTH(X, N) — 信号强度
/// 公式：(X[i] - mean(X, N)) / std(X, N) （Z-score 但取绝对值）
struct SIGNALSTRENGTHFunction: BuiltinFunction {
    let name = "SIGNALSTRENGTH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SIGNALSTRENGTH需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "SIGNALSTRENGTH的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 1 else {
            throw InterpreterError(message: "SIGNALSTRENGTH的周期必须 > 1")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let curr = source[i] else { continue }
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in s...i {
                if let v = source[j] { sum += v; cnt += 1 }
            }
            guard cnt >= 2 else { continue }
            let mean = sum / Decimal(cnt)
            var sq: Decimal = 0
            for j in s...i {
                if let v = source[j] { sq += (v - mean) * (v - mean) }
            }
            let varD = NSDecimalNumber(decimal: sq / Decimal(cnt)).doubleValue
            guard varD > 0 else { continue }
            let std = Decimal(sqrt(varD))
            guard std > 0 else { continue }
            result[i] = abs((curr - mean) / std)
        }
        return result
    }
}

// MARK: - 内部 MA helper

private enum MaiB33MA {
    static func ma(bars: [BarData], period: Int) -> [Decimal?] {
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i { sum += bars[j].close }
            result[i] = sum / Decimal(i - s + 1)
        }
        return result
    }
}
