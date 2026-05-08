// 麦语言扩展 · 第 28 批（v15.25 batch35 · 线性缩放 + K 线统计比率）
//
// 7 个 trader 实用辅助 + K 线统计：
//   1. SCALE(X, oldMin, oldMax, newMin, newMax) — 线性缩放
//   2. LERP(A, B, t)         — 线性插值 = A + (B-A)*t
//   3. GREENRATIO(N)         — N 内阳线比率
//   4. REDRATIO(N)           — N 内阴线比率
//   5. AVGBODY(N)            — N 内平均实体大小 = MA(|C-O|, N)
//   6. AVGRANGE(N)           — N 内平均振幅 = MA(H-L, N)
//   7. BODYRATIO(N)          — N 内 平均实体 / 平均振幅

import Foundation

// MARK: - 1. SCALE

/// SCALE(X, oldMin, oldMax, newMin, newMax) — 线性缩放
/// 公式：(X - oldMin) / (oldMax - oldMin) * (newMax - newMin) + newMin
struct SCALEFunction: BuiltinFunction {
    let name = "SCALE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 5 else {
            throw InterpreterError(message: "SCALE需要5个参数（X, oldMin, oldMax, newMin, newMax）")
        }
        let source = args[0]
        guard let omV = args[1].first, let oldMin = omV,
              let oxV = args[2].first, let oldMax = oxV,
              let nmV = args[3].first, let newMin = nmV,
              let nxV = args[4].first, let newMax = nxV else {
            throw InterpreterError(message: "SCALE的参数无效")
        }
        let oldSpan = oldMax - oldMin
        let newSpan = newMax - newMin
        guard oldSpan != 0 else {
            throw InterpreterError(message: "SCALE的 oldMax 必须 != oldMin")
        }

        return source.map { v in
            guard let v else { return nil }
            return (v - oldMin) / oldSpan * newSpan + newMin
        }
    }
}

// MARK: - 2. LERP

/// LERP(A, B, t) — 线性插值 = A + (B-A) * t
/// t ∈ [0, 1]：0 → A · 1 → B · 0.5 → 中点
struct LERPFunction: BuiltinFunction {
    let name = "LERP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "LERP需要3个参数（A, B, t）")
        }
        let a = args[0]
        let b = args[1]
        let t = args[2]
        guard a.count == b.count, b.count == t.count else {
            throw InterpreterError(message: "LERP的A/B/t长度必须一致")
        }

        let count = a.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let av = a[i], let bv = b[i], let tv = t[i] else { continue }
            result[i] = av + (bv - av) * tv
        }
        return result
    }
}

// MARK: - 3. GREENRATIO

/// GREENRATIO(N) — N 内阳线比率（C > O 的根数 / N）
struct GREENRATIOFunction: BuiltinFunction {
    let name = "GREENRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "GREENRATIO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "GREENRATIO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "GREENRATIO的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var greens = 0
            let total = i - start + 1
            for j in start...i {
                if bars[j].close > bars[j].open { greens += 1 }
            }
            result[i] = Decimal(greens) / Decimal(total)
        }
        return result
    }
}

// MARK: - 4. REDRATIO

/// REDRATIO(N) — N 内阴线比率
struct REDRATIOFunction: BuiltinFunction {
    let name = "REDRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "REDRATIO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "REDRATIO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "REDRATIO的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var reds = 0
            let total = i - start + 1
            for j in start...i {
                if bars[j].close < bars[j].open { reds += 1 }
            }
            result[i] = Decimal(reds) / Decimal(total)
        }
        return result
    }
}

// MARK: - 5. AVGBODY

/// AVGBODY(N) — N 内平均实体大小 = MA(|C-O|, N)
struct AVGBODYFunction: BuiltinFunction {
    let name = "AVGBODY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AVGBODY需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AVGBODY的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AVGBODY的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                sum += abs(bars[j].close - bars[j].open)
            }
            result[i] = sum / Decimal(i - start + 1)
        }
        return result
    }
}

// MARK: - 6. AVGRANGE

/// AVGRANGE(N) — N 内平均振幅 = MA(H-L, N)
struct AVGRANGEFunction: BuiltinFunction {
    let name = "AVGRANGE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AVGRANGE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AVGRANGE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AVGRANGE的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                sum += bars[j].high - bars[j].low
            }
            result[i] = sum / Decimal(i - start + 1)
        }
        return result
    }
}

// MARK: - 7. BODYRATIO

/// BODYRATIO(N) — 实体/振幅比 = AVGBODY / AVGRANGE
/// 范围 [0, 1] · 接近 1 = 强势趋势 · 接近 0 = 横盘震荡
struct BODYRATIOFunction: BuiltinFunction {
    let name = "BODYRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "BODYRATIO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "BODYRATIO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "BODYRATIO的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var bodySum: Decimal = 0
            var rangeSum: Decimal = 0
            for j in start...i {
                bodySum += abs(bars[j].close - bars[j].open)
                rangeSum += bars[j].high - bars[j].low
            }
            guard rangeSum > 0 else { continue }
            result[i] = bodySum / rangeSum
        }
        return result
    }
}
