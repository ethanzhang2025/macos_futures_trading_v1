// 麦语言扩展 · 第 26 批（v15.25 batch33 · 盈亏统计 · 组合管理 trader 必备）
//
// 7 个盈亏统计函数（基于 close 序列 · trader 评估策略）：
//   1. GAINS(N)         — N 周期内盈利根的总收益
//   2. LOSSES(N)        — N 周期内亏损根的总损失
//   3. WINRATE(N)       — N 周期内赢率（盈利根数 / 总根数）
//   4. AVGUP(N)         — 平均上涨幅度（GAINS / 盈利根数）
//   5. AVGDOWN(N)       — 平均下跌幅度（LOSSES / 亏损根数）
//   6. PROFITRATIO(N)   — 平均赢 / 平均亏
//   7. EXPECTANCY(N)    — 期望收益 = winrate*avgup - lossrate*avgdown

import Foundation

// MARK: - 1. GAINS

/// GAINS(N) — N 周期内盈利根的总收益（C[j] > C[j-1] 时累加 diff）
struct GAINSFunction: BuiltinFunction {
    let name = "GAINS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "GAINS需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "GAINS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "GAINS的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { sum += diff }
            }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 2. LOSSES

/// LOSSES(N) — N 周期内亏损根的总损失（绝对值）
struct LOSSESFunction: BuiltinFunction {
    let name = "LOSSES"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "LOSSES需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "LOSSES的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "LOSSES的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff < 0 { sum += abs(diff) }
            }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 3. WINRATE

/// WINRATE(N) — N 周期内赢率（盈利根数 / 总变化根数）
/// 平盘根不计入分母（trader 标准做法）
struct WINRATEFunction: BuiltinFunction {
    let name = "WINRATE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "WINRATE需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "WINRATE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "WINRATE的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var ups = 0
            var moves = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { ups += 1; moves += 1 }
                else if diff < 0 { moves += 1 }
            }
            guard moves > 0 else { continue }
            result[i] = Decimal(ups) / Decimal(moves)
        }
        return result
    }
}

// MARK: - 4. AVGUP

/// AVGUP(N) — 平均上涨幅度 = GAINS / 盈利根数
struct AVGUPFunction: BuiltinFunction {
    let name = "AVGUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AVGUP需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AVGUP的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AVGUP的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var sum: Decimal = 0
            var ups = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { sum += diff; ups += 1 }
            }
            guard ups > 0 else { continue }
            result[i] = sum / Decimal(ups)
        }
        return result
    }
}

// MARK: - 5. AVGDOWN

/// AVGDOWN(N) — 平均下跌幅度 = LOSSES / 亏损根数
struct AVGDOWNFunction: BuiltinFunction {
    let name = "AVGDOWN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AVGDOWN需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AVGDOWN的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AVGDOWN的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var sum: Decimal = 0
            var downs = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff < 0 { sum += abs(diff); downs += 1 }
            }
            guard downs > 0 else { continue }
            result[i] = sum / Decimal(downs)
        }
        return result
    }
}

// MARK: - 6. PROFITRATIO

/// PROFITRATIO(N) — 平均赢 / 平均亏 = AVGUP / AVGDOWN
/// 经验：> 2 优秀策略 / < 1 不可持续
struct PROFITRATIOFunction: BuiltinFunction {
    let name = "PROFITRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PROFITRATIO需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PROFITRATIO的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PROFITRATIO的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var upSum: Decimal = 0
            var downSum: Decimal = 0
            var ups = 0
            var downs = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { upSum += diff; ups += 1 }
                else if diff < 0 { downSum += abs(diff); downs += 1 }
            }
            guard ups > 0, downs > 0 else { continue }
            let avgUp = upSum / Decimal(ups)
            let avgDown = downSum / Decimal(downs)
            guard avgDown > 0 else { continue }
            result[i] = avgUp / avgDown
        }
        return result
    }
}

// MARK: - 7. EXPECTANCY

/// EXPECTANCY(N) — 期望收益 = winrate * avgup - lossrate * avgdown
/// > 0 长期盈利 / < 0 长期亏损
struct EXPECTANCYFunction: BuiltinFunction {
    let name = "EXPECTANCY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "EXPECTANCY需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "EXPECTANCY的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "EXPECTANCY的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var upSum: Decimal = 0
            var downSum: Decimal = 0
            var ups = 0
            var downs = 0
            for j in start...i {
                let diff = bars[j].close - bars[j - 1].close
                if diff > 0 { upSum += diff; ups += 1 }
                else if diff < 0 { downSum += abs(diff); downs += 1 }
            }
            let total = ups + downs
            guard total > 0 else { continue }
            let winrate = Decimal(ups) / Decimal(total)
            let lossrate = Decimal(downs) / Decimal(total)
            let avgUp = ups > 0 ? upSum / Decimal(ups) : Decimal(0)
            let avgDown = downs > 0 ? downSum / Decimal(downs) : Decimal(0)
            result[i] = winrate * avgUp - lossrate * avgDown
        }
        return result
    }
}
