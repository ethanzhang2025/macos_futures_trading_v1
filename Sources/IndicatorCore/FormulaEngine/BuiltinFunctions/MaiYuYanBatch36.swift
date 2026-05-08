// 麦语言扩展 · 第 36 批（v15.25 batch43 · 累积统计 EXPANDING + 有效值）
//
// 7 个累积/全程统计函数：
//   1. EXPANDINGMEAN(X)   — 累积均值（不限窗口 · 自第 0 根起）
//   2. EXPANDINGMAX(X)    — 累积最大值
//   3. EXPANDINGMIN(X)    — 累积最小值
//   4. EXPANDINGSTD(X)    — 累积标准差
//   5. EXPANDINGSUM(X)    — 累积和（与 CUMSUM 等价 · 别名）
//   6. FIRSTVALID(X)      — 第一个有效值（持续返同一个）
//   7. LASTVALID(X)       — 最近一个有效值（处理 nil 跳过）

import Foundation

// MARK: - 1. EXPANDINGMEAN

struct EXPANDINGMEANFunction: BuiltinFunction {
    let name = "EXPANDINGMEAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXPANDINGMEAN需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var sum: Decimal = 0
        var cnt = 0
        for i in 0..<count {
            if let v = source[i] {
                sum += v
                cnt += 1
            }
            if cnt > 0 {
                result[i] = sum / Decimal(cnt)
            }
        }
        return result
    }
}

// MARK: - 2. EXPANDINGMAX

struct EXPANDINGMAXFunction: BuiltinFunction {
    let name = "EXPANDINGMAX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXPANDINGMAX需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var maxVal: Decimal?
        for i in 0..<count {
            if let v = source[i] {
                if maxVal == nil || v > maxVal! { maxVal = v }
            }
            result[i] = maxVal
        }
        return result
    }
}

// MARK: - 3. EXPANDINGMIN

struct EXPANDINGMINFunction: BuiltinFunction {
    let name = "EXPANDINGMIN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXPANDINGMIN需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var minVal: Decimal?
        for i in 0..<count {
            if let v = source[i] {
                if minVal == nil || v < minVal! { minVal = v }
            }
            result[i] = minVal
        }
        return result
    }
}

// MARK: - 4. EXPANDINGSTD

struct EXPANDINGSTDFunction: BuiltinFunction {
    let name = "EXPANDINGSTD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXPANDINGSTD需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var values: [Decimal] = []
        values.reserveCapacity(count)
        for i in 0..<count {
            if let v = source[i] { values.append(v) }
            guard values.count >= 2 else { continue }
            let nDec = Decimal(values.count)
            let mean = values.reduce(Decimal(0), +) / nDec
            var sq: Decimal = 0
            for v in values { sq += (v - mean) * (v - mean) }
            let varD = NSDecimalNumber(decimal: sq / nDec).doubleValue
            guard varD >= 0 else { continue }
            result[i] = Decimal(sqrt(varD))
        }
        return result
    }
}

// MARK: - 5. EXPANDINGSUM

struct EXPANDINGSUMFunction: BuiltinFunction {
    let name = "EXPANDINGSUM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXPANDINGSUM需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var sum: Decimal = 0
        for i in 0..<count {
            if let v = source[i] { sum += v }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 6. FIRSTVALID

/// FIRSTVALID(X) — 第一个有效值（持续返同一个 · 适合"开盘价"等）
struct FIRSTVALIDFunction: BuiltinFunction {
    let name = "FIRSTVALID"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "FIRSTVALID需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var firstVal: Decimal?
        for i in 0..<count {
            if firstVal == nil, let v = source[i] {
                firstVal = v
            }
            result[i] = firstVal
        }
        return result
    }
}

// MARK: - 7. LASTVALID

/// LASTVALID(X) — 最近一个有效值（nil 时持续上次有效值）
struct LASTVALIDFunction: BuiltinFunction {
    let name = "LASTVALID"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "LASTVALID需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastVal: Decimal?
        for i in 0..<count {
            if let v = source[i] { lastVal = v }
            result[i] = lastVal
        }
        return result
    }
}
