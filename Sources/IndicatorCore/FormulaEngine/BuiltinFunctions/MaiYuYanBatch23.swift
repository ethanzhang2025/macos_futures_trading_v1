// 麦语言扩展 · 第 23 批（v15.25 batch30 · 趋势信号 · 金死叉/支撑阻力/新高新低/回调）
//
// 7 个 trader 趋势信号便捷函数：
//   1. GOLDENCROSS(N1, N2)    — 金叉 = CROSS(MA(N1), MA(N2))
//   2. DEADCROSS(N1, N2)      — 死叉 = CROSS(MA(N2), MA(N1))
//   3. SUPPORT(N)             — 支撑线 = LLV(LOW, N)
//   4. RESISTANCE(N)          — 阻力线 = HHV(HIGH, N)
//   5. NEWHIGH(N)             — 创 N 期新高（CLOSE 等于 HHV(CLOSE, N)）
//   6. NEWLOW(N)              — 创 N 期新低
//   7. PULLBACK(N, pct)       — 回调（HHV 回落 pct%）

import Foundation

// MARK: - 1. GOLDENCROSS

/// GOLDENCROSS(N1, N2) — 短均线上穿长均线
/// 条件：MA(N1)[i-1] < MA(N2)[i-1] && MA(N1)[i] >= MA(N2)[i]
struct GOLDENCROSSFunction: BuiltinFunction {
    let name = "GOLDENCROSS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "GOLDENCROSS需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "GOLDENCROSS的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "GOLDENCROSS的周期必须为正整数")
        }

        let ma1 = MaiB23MA.ma(bars: bars, period: p1)
        let ma2 = MaiB23MA.ma(bars: bars, period: p2)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let m1 = ma1[i], let m2 = ma2[i],
                  let p1Prev = ma1[i - 1], let p2Prev = ma2[i - 1] else { continue }
            result[i] = (p1Prev < p2Prev && m1 >= m2) ? 1 : 0
        }
        return result
    }
}

// MARK: - 2. DEADCROSS

/// DEADCROSS(N1, N2) — 短均线下穿长均线
struct DEADCROSSFunction: BuiltinFunction {
    let name = "DEADCROSS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "DEADCROSS需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "DEADCROSS的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "DEADCROSS的周期必须为正整数")
        }

        let ma1 = MaiB23MA.ma(bars: bars, period: p1)
        let ma2 = MaiB23MA.ma(bars: bars, period: p2)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let m1 = ma1[i], let m2 = ma2[i],
                  let p1Prev = ma1[i - 1], let p2Prev = ma2[i - 1] else { continue }
            result[i] = (p1Prev > p2Prev && m1 <= m2) ? 1 : 0
        }
        return result
    }
}

// MARK: - 3. SUPPORT

/// SUPPORT(N) — 支撑线 = LLV(LOW, N)
struct SUPPORTFunction: BuiltinFunction {
    let name = "SUPPORT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "SUPPORT需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "SUPPORT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "SUPPORT的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var lo = bars[start].low
            for j in start...i {
                if bars[j].low < lo { lo = bars[j].low }
            }
            result[i] = lo
        }
        return result
    }
}

// MARK: - 4. RESISTANCE

/// RESISTANCE(N) — 阻力线 = HHV(HIGH, N)
struct RESISTANCEFunction: BuiltinFunction {
    let name = "RESISTANCE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RESISTANCE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "RESISTANCE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "RESISTANCE的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
            }
            result[i] = hi
        }
        return result
    }
}

// MARK: - 5. NEWHIGH

/// NEWHIGH(N) — 创 N 期新高（CLOSE >= HHV(CLOSE, N) 严格大于历史值）
struct NEWHIGHFunction: BuiltinFunction {
    let name = "NEWHIGH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "NEWHIGH需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "NEWHIGH的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "NEWHIGH的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            // 历史窗口（不含当前根）的最高
            var prevHi: Decimal?
            for j in start..<i {
                if prevHi == nil || bars[j].close > prevHi! { prevHi = bars[j].close }
            }
            if let p = prevHi {
                result[i] = bars[i].close > p ? 1 : 0
            } else {
                result[i] = 0
            }
        }
        return result
    }
}

// MARK: - 6. NEWLOW

/// NEWLOW(N) — 创 N 期新低
struct NEWLOWFunction: BuiltinFunction {
    let name = "NEWLOW"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "NEWLOW需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "NEWLOW的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "NEWLOW的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var prevLo: Decimal?
            for j in start..<i {
                if prevLo == nil || bars[j].close < prevLo! { prevLo = bars[j].close }
            }
            if let p = prevLo {
                result[i] = bars[i].close < p ? 1 : 0
            } else {
                result[i] = 0
            }
        }
        return result
    }
}

// MARK: - 7. PULLBACK

/// PULLBACK(N, pct) — 回调判定
/// 条件：(HHV(HIGH, N) - CLOSE) / HHV(HIGH, N) >= pct/100
struct PULLBACKFunction: BuiltinFunction {
    let name = "PULLBACK"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "PULLBACK需要2个参数（周期N, 回调百分比pct）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let pVal = args[1].first, let pct = pVal else {
            throw InterpreterError(message: "PULLBACK的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PULLBACK的周期必须为正整数")
        }

        let count = bars.count
        let threshold = pct / 100
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
            }
            guard hi > 0 else { continue }
            let drop = (hi - bars[i].close) / hi
            result[i] = drop >= threshold ? 1 : 0
        }
        return result
    }
}

// MARK: - 内部 MA helper

private enum MaiB23MA {
    static func ma(bars: [BarData], period: Int) -> [Decimal?] {
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
