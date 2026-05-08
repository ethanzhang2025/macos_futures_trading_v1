// 麦语言扩展 · 第 22 批（v15.25 batch29 · K 线形态识别扩展）
//
// 7 个 K 线形态扩展（多根组合 + 经典反转）：
//   1. ISMORNINGSTAR()    — 早晨之星（3 根 · 看涨反转）
//   2. ISEVENINGSTAR()    — 黄昏之星（3 根 · 看跌反转）
//   3. ISHARAMI()         — 孕线（2 根 · 前大实体 + 当小实体内嵌）
//   4. ISDARKCLOUD()      — 乌云盖顶（前阳 + 当阴跳高 + 收过中点 · 看跌）
//   5. ISPIERCING()       — 穿刺（前阴 + 当阳跳低 + 收过中点 · 看涨）
//   6. ISGAPDOWN()        — 向下跳空 high[i] < low[i-1]
//   7. ISSHAVENTOP()      — 光头线（无上影 H = max(O,C)）

import Foundation

// MARK: - 1. ISMORNINGSTAR

/// ISMORNINGSTAR — 早晨之星（看涨反转 · 3 根）
/// i-2 阴 + i-1 小实体跳低 + i 阳 + i 收盘 > i-2 中点
struct ISMORNINGSTARFunction: BuiltinFunction {
    let name = "ISMORNINGSTAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISMORNINGSTAR不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 2..<count {
            let b0 = bars[i - 2]
            let b1 = bars[i - 1]
            let b2 = bars[i]

            let b0Bear = b0.close < b0.open
            let b0Body = abs(b0.close - b0.open)
            let b1Body = abs(b1.close - b1.open)
            let b1Small = b1Body < b0Body / 3
            let b2Bull = b2.close > b2.open
            let b0Mid = (b0.open + b0.close) / 2
            let b2Above = b2.close > b0Mid

            result[i] = (b0Bear && b1Small && b2Bull && b2Above) ? 1 : 0
        }
        return result
    }
}

// MARK: - 2. ISEVENINGSTAR

/// ISEVENINGSTAR — 黄昏之星（看跌反转 · 3 根）
struct ISEVENINGSTARFunction: BuiltinFunction {
    let name = "ISEVENINGSTAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISEVENINGSTAR不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 2..<count {
            let b0 = bars[i - 2]
            let b1 = bars[i - 1]
            let b2 = bars[i]

            let b0Bull = b0.close > b0.open
            let b0Body = abs(b0.close - b0.open)
            let b1Body = abs(b1.close - b1.open)
            let b1Small = b1Body < b0Body / 3
            let b2Bear = b2.close < b2.open
            let b0Mid = (b0.open + b0.close) / 2
            let b2Below = b2.close < b0Mid

            result[i] = (b0Bull && b1Small && b2Bear && b2Below) ? 1 : 0
        }
        return result
    }
}

// MARK: - 3. ISHARAMI

/// ISHARAMI — 孕线（2 根）
/// 前根大实体 + 当根小实体在前根实体内（H/L 都在）
struct ISHARAMIFunction: BuiltinFunction {
    let name = "ISHARAMI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISHARAMI不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1]
            let curr = bars[i]
            let prevBody = abs(prev.close - prev.open)
            let currBody = abs(curr.close - curr.open)
            let prevHigh = max(prev.open, prev.close)
            let prevLow = min(prev.open, prev.close)
            let currHigh = max(curr.open, curr.close)
            let currLow = min(curr.open, curr.close)
            // 当前实体完全在前根实体内 + 当前实体明显小
            let inside = currHigh < prevHigh && currLow > prevLow
            let small = currBody * 2 < prevBody
            result[i] = (inside && small) ? 1 : 0
        }
        return result
    }
}

// MARK: - 4. ISDARKCLOUD

/// ISDARKCLOUD — 乌云盖顶（看跌 · 2 根）
/// 前阳 + 当阴 + 当 open > 前 high + 当 close < 前根中点（且当 close > 前 open）
struct ISDARKCLOUDFunction: BuiltinFunction {
    let name = "ISDARKCLOUD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISDARKCLOUD不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1]
            let curr = bars[i]
            let prevBull = prev.close > prev.open
            let currBear = curr.close < curr.open
            let openAbove = curr.open > prev.high
            let prevMid = (prev.open + prev.close) / 2
            let closePassMid = curr.close < prevMid && curr.close > prev.open
            result[i] = (prevBull && currBear && openAbove && closePassMid) ? 1 : 0
        }
        return result
    }
}

// MARK: - 5. ISPIERCING

/// ISPIERCING — 穿刺（看涨 · 2 根）
/// 前阴 + 当阳 + 当 open < 前 low + 当 close > 前根中点（且当 close < 前 open）
struct ISPIERCINGFunction: BuiltinFunction {
    let name = "ISPIERCING"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISPIERCING不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1]
            let curr = bars[i]
            let prevBear = prev.close < prev.open
            let currBull = curr.close > curr.open
            let openBelow = curr.open < prev.low
            let prevMid = (prev.open + prev.close) / 2
            let closePassMid = curr.close > prevMid && curr.close < prev.open
            result[i] = (prevBear && currBull && openBelow && closePassMid) ? 1 : 0
        }
        return result
    }
}

// MARK: - 6. ISGAPDOWN

/// ISGAPDOWN — 向下跳空 high[i] < low[i-1]
struct ISGAPDOWNFunction: BuiltinFunction {
    let name = "ISGAPDOWN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISGAPDOWN不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = bars[i].high < bars[i - 1].low ? 1 : 0
        }
        return result
    }
}

// MARK: - 7. ISSHAVENTOP

/// ISSHAVENTOP — 光头线（无上影 H = max(O, C)）
/// 容差：H - max(O, C) < (H - L) * 0.05
struct ISSHAVENTOPFunction: BuiltinFunction {
    let name = "ISSHAVENTOP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "ISSHAVENTOP不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        let tolFactor = Decimal(string: "0.05")!
        for i in 0..<count {
            let bar = bars[i]
            let span = bar.high - bar.low
            guard span > 0 else {
                result[i] = 1
                continue
            }
            let bodyTop = max(bar.open, bar.close)
            let upperShadow = bar.high - bodyTop
            result[i] = upperShadow < span * tolFactor ? 1 : 0
        }
        return result
    }
}
