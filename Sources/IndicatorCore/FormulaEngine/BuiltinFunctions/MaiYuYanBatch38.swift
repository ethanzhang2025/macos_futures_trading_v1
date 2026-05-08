// 麦语言扩展 · 第 38 批（v15.25 batch45 · 计数统计）
//
// 7 个事件计数函数：
//   1. NCROSSUP(X, lvl, N)   — N 内 X 上穿 lvl 的次数
//   2. NCROSSDN(X, lvl, N)   — N 内 X 下穿 lvl 的次数
//   3. POSCOUNT(X, N)        — N 内 X > 0 的根数
//   4. NEGCOUNT(X, N)        — N 内 X < 0 的根数
//   5. ZEROCOUNT(X, N)       — N 内 X = 0 的根数
//   6. CHANGECOUNT(X, N)     — N 内 X 与前根不等的次数
//   7. SAMECOUNT(X, N)       — N 内 X 与前根相等的次数

import Foundation

// MARK: - 1. NCROSSUP

/// NCROSSUP(X, lvl, N) — N 内 X 上穿 lvl 的次数
struct NCROSSUPFunction: BuiltinFunction {
    let name = "NCROSSUP"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "NCROSSUP需要3个参数（X, lvl, N）") }
        let source = args[0]
        guard let lvlV = args[1].first, let lvl = lvlV,
              let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "NCROSSUP的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "NCROSSUP的周期必须为正整数") }

        let count = source.count
        var hits = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1] else { hits[i] = 0; continue }
            hits[i] = (prev < lvl && curr >= lvl) ? 1 : 0
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i { if let v = hits[j] { sum += v } }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 2. NCROSSDN

struct NCROSSDNFunction: BuiltinFunction {
    let name = "NCROSSDN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "NCROSSDN需要3个参数（X, lvl, N）") }
        let source = args[0]
        guard let lvlV = args[1].first, let lvl = lvlV,
              let nV = args[2].first, let n = nV else {
            throw InterpreterError(message: "NCROSSDN的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "NCROSSDN的周期必须为正整数") }

        let count = source.count
        var hits = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1] else { hits[i] = 0; continue }
            hits[i] = (prev > lvl && curr <= lvl) ? 1 : 0
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i { if let v = hits[j] { sum += v } }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 3. POSCOUNT

struct POSCOUNTFunction: BuiltinFunction {
    let name = "POSCOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "POSCOUNT需要2个参数（X, N）") }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "POSCOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "POSCOUNT的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var cnt = 0
            for j in s...i { if let v = source[j], v > 0 { cnt += 1 } }
            result[i] = Decimal(cnt)
        }
        return result
    }
}

// MARK: - 4. NEGCOUNT

struct NEGCOUNTFunction: BuiltinFunction {
    let name = "NEGCOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "NEGCOUNT需要2个参数（X, N）") }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "NEGCOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "NEGCOUNT的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var cnt = 0
            for j in s...i { if let v = source[j], v < 0 { cnt += 1 } }
            result[i] = Decimal(cnt)
        }
        return result
    }
}

// MARK: - 5. ZEROCOUNT

struct ZEROCOUNTFunction: BuiltinFunction {
    let name = "ZEROCOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "ZEROCOUNT需要2个参数（X, N）") }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "ZEROCOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "ZEROCOUNT的周期必须为正整数") }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var cnt = 0
            for j in s...i { if let v = source[j], v == 0 { cnt += 1 } }
            result[i] = Decimal(cnt)
        }
        return result
    }
}

// MARK: - 6. CHANGECOUNT

struct CHANGECOUNTFunction: BuiltinFunction {
    let name = "CHANGECOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "CHANGECOUNT需要2个参数（X, N）") }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "CHANGECOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "CHANGECOUNT的周期必须为正整数") }

        let count = source.count
        var changes = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1] else { changes[i] = 0; continue }
            changes[i] = curr != prev ? 1 : 0
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i { if let v = changes[j] { sum += v } }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 7. SAMECOUNT

struct SAMECOUNTFunction: BuiltinFunction {
    let name = "SAMECOUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "SAMECOUNT需要2个参数（X, N）") }
        let source = args[0]
        guard let nV = args[1].first, let n = nV else {
            throw InterpreterError(message: "SAMECOUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "SAMECOUNT的周期必须为正整数") }

        let count = source.count
        var sames = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = source[i], let prev = source[i - 1] else { sames[i] = 0; continue }
            sames[i] = curr == prev ? 1 : 0
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i { if let v = sames[j] { sum += v } }
            result[i] = sum
        }
        return result
    }
}
