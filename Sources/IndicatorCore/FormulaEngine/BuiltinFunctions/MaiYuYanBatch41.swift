// 麦语言扩展 · 第 41 批（v15.25 batch48 · 资金管理 · trader 实战）
//
// 7 个函数（仓位 / 资金 / 风险 / 期望值核心）：
//   1. KELLY(winRate, avgWin, avgLoss)         — Kelly 最优仓位比例
//   2. OPTIMALF(returns, N)                    — Ralph Vince Optimal F（grid search）
//   3. POSITIONSIZE(equity, riskPct, riskUnit) — 头寸大小 = equity * riskPct / riskUnit
//   4. RISKPCT(entry, stopLoss)                — 单笔风险占比 |entry-stop|/entry
//   5. REWARDRATIO(target, entry, stopLoss)    — 盈亏比 (target-entry)/|entry-stop|
//   6. EQUITY(returns)                         — 累积权益曲线 ∏(1+r)
//   7. MARTINGALE(loseStreak, baseSize)        — 倍投仓位 baseSize * 2^loseStreak

import Foundation

// MARK: - 1. KELLY

/// KELLY(winRate, avgWin, avgLoss) — Kelly 最优仓位
/// 公式: f* = winRate - (1 - winRate) * avgLoss / avgWin
/// 假设 avgLoss > 0（绝对值）· avgWin > 0
struct KELLYFunction: BuiltinFunction {
    let name = "KELLY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "KELLY需要3个参数（胜率, 平均盈, 平均亏）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let w = args[0][i], let aw = args[1][i], let al = args[2][i] else { continue }
            guard aw > 0 else { continue }
            result[i] = w - (1 - w) * al / aw
        }
        return result
    }
}

// MARK: - 2. OPTIMALF

/// OPTIMALF(returns, N) — Ralph Vince Optimal F
/// 在最近 N 根 returns 上 grid search [0.01, 0.02, ..., 1.0]
/// 选 f 使 ∏(1 + f * r_i / |minLoss|) 最大
struct OPTIMALFFunction: BuiltinFunction {
    let name = "OPTIMALF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "OPTIMALF需要2个参数（收益序列, 周期N）") }
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "OPTIMALF的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "OPTIMALF的周期必须为正整数") }

        let r = args[0]
        let count = r.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i + 1 >= period else { continue }
            var window: [Double] = []
            for j in (i - period + 1)...i {
                if let v = r[j] { window.append(NSDecimalNumber(decimal: v).doubleValue) }
            }
            guard window.count == period else { continue }
            let minLoss = window.min() ?? 0
            guard minLoss < 0 else { result[i] = 0; continue }
            let absMinLoss = -minLoss
            var bestF = 0.0
            var bestTWR = 1.0
            var f = 0.01
            while f <= 1.0 {
                var twr = 1.0
                for v in window { twr *= (1.0 + f * v / absMinLoss) }
                if twr > bestTWR { bestTWR = twr; bestF = f }
                f += 0.01
            }
            result[i] = Decimal(bestF)
        }
        return result
    }
}

// MARK: - 3. POSITIONSIZE

/// POSITIONSIZE(equity, riskPct, riskUnit) — 头寸大小 = equity * riskPct / riskUnit
/// 例如 riskUnit = ATR 或 |entry - stopLoss|
struct POSITIONSIZEFunction: BuiltinFunction {
    let name = "POSITIONSIZE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "POSITIONSIZE需要3个参数（资金, 风险占比, 单位风险）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let eq = args[0][i], let rp = args[1][i], let ru = args[2][i] else { continue }
            guard ru > 0 else { continue }
            result[i] = eq * rp / ru
        }
        return result
    }
}

// MARK: - 4. RISKPCT

/// RISKPCT(entry, stopLoss) — 单笔风险占比 = |entry - stopLoss| / entry
struct RISKPCTFunction: BuiltinFunction {
    let name = "RISKPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "RISKPCT需要2个参数（入场价, 止损价）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let entry = args[0][i], let stop = args[1][i] else { continue }
            guard entry != 0 else { continue }
            result[i] = abs(entry - stop) / entry
        }
        return result
    }
}

// MARK: - 5. REWARDRATIO

/// REWARDRATIO(target, entry, stopLoss) — 盈亏比 = (target - entry) / |entry - stopLoss|
struct REWARDRATIOFunction: BuiltinFunction {
    let name = "REWARDRATIO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "REWARDRATIO需要3个参数（目标价, 入场价, 止损价）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let tgt = args[0][i], let entry = args[1][i], let stop = args[2][i] else { continue }
            let denom = abs(entry - stop)
            guard denom > 0 else { continue }
            result[i] = (tgt - entry) / denom
        }
        return result
    }
}

// MARK: - 6. EQUITY

/// EQUITY(returns) — 累积权益曲线 = ∏(1 + r_i)，初始 1
struct EQUITYFunction: BuiltinFunction {
    let name = "EQUITY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EQUITY需要1个参数（收益率序列）") }
        let r = args[0]
        let count = r.count
        var result = [Decimal?](repeating: nil, count: count)
        var cum: Decimal = 1
        for i in 0..<count {
            guard let v = r[i] else { result[i] = cum; continue }
            cum *= (1 + v)
            result[i] = cum
        }
        return result
    }
}

// MARK: - 7. MARTINGALE

/// MARTINGALE(loseStreak, baseSize) — 倍投仓位 = baseSize * 2^loseStreak
/// loseStreak=0 → baseSize · loseStreak=1 → 2*baseSize · loseStreak=3 → 8*baseSize
struct MARTINGALEFunction: BuiltinFunction {
    let name = "MARTINGALE"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "MARTINGALE需要2个参数（连亏数, 基础仓位）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let lsv = args[0][i], let base = args[1][i] else { continue }
            let ls = Int(truncating: lsv as NSDecimalNumber)
            guard ls >= 0 && ls <= 30 else { continue }
            var multiplier: Decimal = 1
            for _ in 0..<ls { multiplier *= 2 }
            result[i] = base * multiplier
        }
        return result
    }
}
