// 麦语言扩展 · 第 21 批（v15.25 batch28 · K 线形态识别）
//
// 7 个 K 线形态函数（trader 形态交易必备）：
//   1. ISDOJI(thresh)        — 十字星 · |C-O|/(H-L) < thresh（默认 0.1）
//   2. ISHAMMER()            — 锤子线（下影 > 2*实体 · 上影 < 实体）
//   3. ISINVHAMMER()         — 倒锤（上影 > 2*实体 · 下影 < 实体）
//   4. ISBULLENG()           — 看涨吞没（前阴当前阳 + 实体包覆）
//   5. ISBEARENG()           — 看跌吞没（前阳当前阴 + 实体包覆）
//   6. ISGAPUP()             — 向上跳空（low[i] > high[i-1]）
//   7. ISLONGBODY(thresh)    — 长实体 · |C-O|/(H-L) > thresh（默认 0.7）
//
// 返回值：1=形态命中 / 0=未命中

import Foundation

// MARK: - 1. ISDOJI

/// ISDOJI(threshold) — 十字星
/// 实体 |C-O| / 振幅 (H-L) < threshold（默认 0.1 即 10%）
struct ISDOJIFunction: BuiltinFunction {
    let name = "ISDOJI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ISDOJI需要1个参数（阈值 · 默认 0.1）")
        }
        guard let thV = args[0].first, let thresh = thV else {
            throw InterpreterError(message: "ISDOJI的阈值参数无效")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let body = abs(bars[i].close - bars[i].open)
            let span = bars[i].high - bars[i].low
            guard span > 0 else {
                result[i] = 1  // 振幅 0 → 极端十字
                continue
            }
            result[i] = (body / span) < thresh ? 1 : 0
        }
        return result
    }
}

// MARK: - 2. ISHAMMER

/// ISHAMMER — 锤子线
/// 下影 > 2 * 实体 + 上影 < 实体 + 实体非零
struct ISHAMMERFunction: BuiltinFunction {
    let name = "ISHAMMER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISHAMMER不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let bar = bars[i]
            let body = abs(bar.close - bar.open)
            let bodyHigh = max(bar.close, bar.open)
            let bodyLow = min(bar.close, bar.open)
            let upperShadow = bar.high - bodyHigh
            let lowerShadow = bodyLow - bar.low
            guard body > 0 else {
                result[i] = 0
                continue
            }
            let isHammer = lowerShadow > 2 * body && upperShadow < body
            result[i] = isHammer ? 1 : 0
        }
        return result
    }
}

// MARK: - 3. ISINVHAMMER

/// ISINVHAMMER — 倒锤
/// 上影 > 2 * 实体 + 下影 < 实体
struct ISINVHAMMERFunction: BuiltinFunction {
    let name = "ISINVHAMMER"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISINVHAMMER不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let bar = bars[i]
            let body = abs(bar.close - bar.open)
            let bodyHigh = max(bar.close, bar.open)
            let bodyLow = min(bar.close, bar.open)
            let upperShadow = bar.high - bodyHigh
            let lowerShadow = bodyLow - bar.low
            guard body > 0 else {
                result[i] = 0
                continue
            }
            let isInv = upperShadow > 2 * body && lowerShadow < body
            result[i] = isInv ? 1 : 0
        }
        return result
    }
}

// MARK: - 4. ISBULLENG

/// ISBULLENG — 看涨吞没（Bullish Engulfing）
/// 前根阴线（C[i-1] < O[i-1]）+ 当前阳线（C > O）+ 当前实体包覆前根（O <= C[i-1] && C >= O[i-1]）
struct ISBULLENGFunction: BuiltinFunction {
    let name = "ISBULLENG"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISBULLENG不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1]
            let curr = bars[i]
            let prevBear = prev.close < prev.open
            let currBull = curr.close > curr.open
            let engulf = curr.open <= prev.close && curr.close >= prev.open
            result[i] = (prevBear && currBull && engulf) ? 1 : 0
        }
        return result
    }
}

// MARK: - 5. ISBEARENG

/// ISBEARENG — 看跌吞没（Bearish Engulfing）
struct ISBEARENGFunction: BuiltinFunction {
    let name = "ISBEARENG"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISBEARENG不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1]
            let curr = bars[i]
            let prevBull = prev.close > prev.open
            let currBear = curr.close < curr.open
            let engulf = curr.open >= prev.close && curr.close <= prev.open
            result[i] = (prevBull && currBear && engulf) ? 1 : 0
        }
        return result
    }
}

// MARK: - 6. ISGAPUP

/// ISGAPUP — 向上跳空（low[i] > high[i-1]）
struct ISGAPUPFunction: BuiltinFunction {
    let name = "ISGAPUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISGAPUP不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = bars[i].low > bars[i - 1].high ? 1 : 0
        }
        return result
    }
}

// MARK: - 7. ISLONGBODY

/// ISLONGBODY(threshold) — 长实体
/// |C-O| / (H-L) > threshold（默认 0.7 即实体占振幅 70%+）
struct ISLONGBODYFunction: BuiltinFunction {
    let name = "ISLONGBODY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ISLONGBODY需要1个参数（阈值 · 默认 0.7）")
        }
        guard let thV = args[0].first, let thresh = thV else {
            throw InterpreterError(message: "ISLONGBODY的阈值参数无效")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let body = abs(bars[i].close - bars[i].open)
            let span = bars[i].high - bars[i].low
            guard span > 0 else {
                result[i] = 0
                continue
            }
            result[i] = (body / span) > thresh ? 1 : 0
        }
        return result
    }
}
