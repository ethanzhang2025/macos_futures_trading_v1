import Foundation

/// REF — 引用N周期前的值
/// 用法: REF(X, N) 引用X在N周期前的值
struct REFFunction: BuiltinFunction {
    let name = "REF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "REF需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "REF的周期参数无效")
        }
        let offset = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in offset..<count {
            result[i] = source[i - offset]
        }
        return result
    }
}

/// HHV — N周期内最高值
/// 用法: HHV(X, N) 求X在N周期内的最高值
struct HHVFunction: BuiltinFunction {
    let name = "HHV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "HHV需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "HHV的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var highest: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if highest == nil || v > highest! { highest = v }
            }
            result[i] = highest
        }
        return result
    }
}

/// LLV — N周期内最低值
/// 用法: LLV(X, N) 求X在N周期内的最低值
struct LLVFunction: BuiltinFunction {
    let name = "LLV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "LLV需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LLV的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var lowest: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if lowest == nil || v < lowest! { lowest = v }
            }
            result[i] = lowest
        }
        return result
    }
}

/// COUNT — 统计N周期内满足条件的次数
/// 用法: COUNT(X, N) 统计N周期内X不为0的次数
struct COUNTFunction: BuiltinFunction {
    let name = "COUNT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "COUNT需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "COUNT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var cnt = 0
            for j in start...i {
                if let v = source[j], v != 0 { cnt += 1 }
            }
            result[i] = Decimal(cnt)
        }
        return result
    }
}

/// SUM — N周期内求和
/// 用法: SUM(X, N) 求X的N周期累计和
struct SUMFunction: BuiltinFunction {
    let name = "SUM"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SUM需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "SUM的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                if let v = source[j] { sum += v }
            }
            result[i] = sum
        }
        return result
    }
}

/// BARSLAST — 上一次条件成立到现在的周期数
/// 用法: BARSLAST(X) 上一次X不为0到现在的周期数
struct BARSLASTFunction: BuiltinFunction {
    let name = "BARSLAST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "BARSLAST需要1个参数")
        }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastTrue: Int?
        for i in 0..<count {
            if let v = source[i], v != 0 {
                lastTrue = i
            }
            if let lt = lastTrue {
                result[i] = Decimal(i - lt)
            }
        }
        return result
    }
}

/// PEAKBARS — 距离最近波峰的 bar 数
/// 用法: PEAKBARS(X) 返回 X 距离最近波峰的 bar 数；尚无波峰前 nil
/// 波峰定义：X[i-1] > X[i-2] 且 X[i-1] > X[i]（i-1 为局部最大）
/// 当前 bar 无右邻不能判断 → 当前 bar 不会成为新波峰
struct PEAKBARSFunction: BuiltinFunction {
    let name = "PEAKBARS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PEAKBARS需要1个参数")
        }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastPeak: Int?
        for i in 0..<count {
            if i >= 2,
               let prev = x[i - 1], let prev2 = x[i - 2], let curr = x[i],
               prev > prev2 && prev > curr {
                lastPeak = i - 1
            }
            if let lp = lastPeak {
                result[i] = Decimal(i - lp)
            }
        }
        return result
    }
}

/// TROUGHBARS — 距离最近波谷的 bar 数
/// 用法: TROUGHBARS(X) 返回 X 距离最近波谷的 bar 数；尚无波谷前 nil
/// 波谷定义：X[i-1] < X[i-2] 且 X[i-1] < X[i]（i-1 为局部最小）
struct TROUGHBARSFunction: BuiltinFunction {
    let name = "TROUGHBARS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "TROUGHBARS需要1个参数")
        }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastTrough: Int?
        for i in 0..<count {
            if i >= 2,
               let prev = x[i - 1], let prev2 = x[i - 2], let curr = x[i],
               prev < prev2 && prev < curr {
                lastTrough = i - 1
            }
            if let lt = lastTrough {
                result[i] = Decimal(i - lt)
            }
        }
        return result
    }
}
