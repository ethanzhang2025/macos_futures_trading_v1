// 麦语言扩展 · 第 24 批（v15.25 batch31 · 灵活 Pivot + 连续判定）
//
// 7 个 trader 灵活信号函数：
//   1. PIVOTHIGH(N)            — N-bar 局部峰（灵活 fractal · N 可变）
//   2. PIVOTLOW(N)             — N-bar 局部谷
//   3. STREAK(X)               — 连续 X 非零的 bar 数
//   4. VOLATILITYRATIO(N1, N2) — 短期波动 / 长期波动 = STD(C,N1)/STD(C,N2)
//   5. TRENDDIR(N)             — 1=MA 上升 / -1=下降 / 0=平
//   6. CONSECUP(N)             — 连续 N 根上涨（C > REF(C,1)）
//   7. CONSECDOWN(N)           — 连续 N 根下跌

import Foundation

// MARK: - 1. PIVOTHIGH

/// PIVOTHIGH(N) — N-bar 局部峰（H[i-N] > H[i-2N..i-N-1] 和 H[i-N+1..i] 全部）
/// 注：需要 i >= 2N 才能判定 · 命中时 result[i] = H[i-N] · 否则保持前值
/// N=2 等价 FRACTALH（5-bar）
struct PIVOTHIGHFunction: BuiltinFunction {
    let name = "PIVOTHIGH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PIVOTHIGH需要1个参数（半窗 N · 总 2N+1 bar）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PIVOTHIGH的N参数无效")
        }
        let half = Int(truncating: n as NSDecimalNumber)
        guard half > 0 else {
            throw InterpreterError(message: "PIVOTHIGH的N必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastPivot: Decimal?
        for i in (2 * half)..<count {
            let center = bars[i - half].high
            var isPivot = true
            for k in (i - 2 * half)..<i where k != (i - half) {
                if bars[k].high >= center { isPivot = false; break }
            }
            if isPivot { lastPivot = center }
            result[i] = lastPivot
        }
        return result
    }
}

// MARK: - 2. PIVOTLOW

/// PIVOTLOW(N) — N-bar 局部谷
struct PIVOTLOWFunction: BuiltinFunction {
    let name = "PIVOTLOW"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PIVOTLOW需要1个参数（半窗 N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PIVOTLOW的N参数无效")
        }
        let half = Int(truncating: n as NSDecimalNumber)
        guard half > 0 else {
            throw InterpreterError(message: "PIVOTLOW的N必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastPivot: Decimal?
        for i in (2 * half)..<count {
            let center = bars[i - half].low
            var isPivot = true
            for k in (i - 2 * half)..<i where k != (i - half) {
                if bars[k].low <= center { isPivot = false; break }
            }
            if isPivot { lastPivot = center }
            result[i] = lastPivot
        }
        return result
    }
}

// MARK: - 3. STREAK

/// STREAK(X) — 连续 X 非零的 bar 数
/// 例：CLOSE > REF(CLOSE,1) 序列 → STREAK 给出连续上涨根数
struct STREAKFunction: BuiltinFunction {
    let name = "STREAK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "STREAK需要1个参数（X）")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var streak = 0
        for i in 0..<count {
            if let v = source[i], v != 0 {
                streak += 1
            } else {
                streak = 0
            }
            result[i] = Decimal(streak)
        }
        return result
    }
}

// MARK: - 4. VOLATILITYRATIO

/// VOLATILITYRATIO(N1, N2) — 短期波动 / 长期波动 = STD(C, N1) / STD(C, N2)
/// > 1 短期更剧烈（异动）/ < 1 长期更剧烈（异动消退）
struct VOLATILITYRATIOFunction: BuiltinFunction {
    let name = "VOLATILITYRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "VOLATILITYRATIO需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "VOLATILITYRATIO的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "VOLATILITYRATIO的周期必须为正整数")
        }

        let count = bars.count
        let s1 = MaiB24STD.std(bars: bars, period: p1)
        let s2 = MaiB24STD.std(bars: bars, period: p2)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let a = s1[i], let b = s2[i], b > 0 else { continue }
            result[i] = a / b
        }
        return result
    }
}

// MARK: - 5. TRENDDIR

/// TRENDDIR(N) — 1=MA 上升 / -1=下降 / 0=平
/// 公式：sign(MA(C, N) - REF(MA(C, N), 1))
struct TRENDDIRFunction: BuiltinFunction {
    let name = "TRENDDIR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "TRENDDIR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "TRENDDIR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TRENDDIR的周期必须为正整数")
        }

        let count = bars.count
        // MA
        var ma = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            ma[i] = sum / Decimal(i - start + 1)
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = ma[i], let prev = ma[i - 1] else { continue }
            if curr > prev { result[i] = 1 }
            else if curr < prev { result[i] = -1 }
            else { result[i] = 0 }
        }
        return result
    }
}

// MARK: - 6. CONSECUP

/// CONSECUP(N) — 连续 N 根上涨（C > REF(C, 1) 连续 N 次）· 命中返 1
struct CONSECUPFunction: BuiltinFunction {
    let name = "CONSECUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CONSECUP需要1个参数（连续根数N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CONSECUP的N参数无效")
        }
        let target = Int(truncating: n as NSDecimalNumber)
        guard target > 0 else {
            throw InterpreterError(message: "CONSECUP的N必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var streak = 0
        for i in 0..<count {
            if i == 0 {
                result[i] = 0
                continue
            }
            if bars[i].close > bars[i - 1].close { streak += 1 }
            else { streak = 0 }
            result[i] = streak >= target ? 1 : 0
        }
        return result
    }
}

// MARK: - 7. CONSECDOWN

/// CONSECDOWN(N) — 连续 N 根下跌
struct CONSECDOWNFunction: BuiltinFunction {
    let name = "CONSECDOWN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CONSECDOWN需要1个参数（连续根数N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CONSECDOWN的N参数无效")
        }
        let target = Int(truncating: n as NSDecimalNumber)
        guard target > 0 else {
            throw InterpreterError(message: "CONSECDOWN的N必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var streak = 0
        for i in 0..<count {
            if i == 0 {
                result[i] = 0
                continue
            }
            if bars[i].close < bars[i - 1].close { streak += 1 }
            else { streak = 0 }
            result[i] = streak >= target ? 1 : 0
        }
        return result
    }
}

// MARK: - 内部 STD helper

private enum MaiB24STD {
    static func std(bars: [BarData], period: Int) -> [Decimal?] {
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += bars[j].close }
            let mean = sum / Decimal(i - start + 1)
            var sqSum: Decimal = 0
            for j in start...i {
                let d = bars[j].close - mean
                sqSum += d * d
            }
            let variance = sqSum / Decimal(i - start + 1)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0 else { continue }
            result[i] = Decimal(sqrt(varD))
        }
        return result
    }
}
