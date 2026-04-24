import Foundation

/// POW — 幂运算
/// 用法: POW(A, B) 求A的B次方
struct POWFunction: BuiltinFunction {
    let name = "POW"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "POW需要2个参数") }
        let a = args[0], b = args[1]
        let count = a.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let va = a[i], let vb = b[i] else { continue }
            let da = NSDecimalNumber(decimal: va).doubleValue
            let db = NSDecimalNumber(decimal: vb).doubleValue
            result[i] = Decimal(pow(da, db))
        }
        return result
    }
}

/// SQRT — 平方根
struct SQRTFunction: BuiltinFunction {
    let name = "SQRT"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "SQRT需要1个参数") }
        return args[0].map { v in
            guard let v, v >= 0 else { return nil }
            return Decimal(sqrt(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

/// LOG — 自然对数
struct LOGFunction: BuiltinFunction {
    let name = "LOG"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "LOG需要1个参数") }
        return args[0].map { v in
            guard let v, v > 0 else { return nil }
            return Decimal(log(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

/// EXP — e的N次方
struct EXPFunction: BuiltinFunction {
    let name = "EXP"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "EXP需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return Decimal(exp(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

/// CEILING — 向上取整
struct CEILINGFunction: BuiltinFunction {
    let name = "CEILING"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "CEILING需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            var result = Decimal()
            var mutable = v
            NSDecimalRound(&result, &mutable, 0, .up)
            return result
        }
    }
}

/// FLOOR — 向下取整
struct FLOORFunction: BuiltinFunction {
    let name = "FLOOR"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "FLOOR需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            var result = Decimal()
            var mutable = v
            NSDecimalRound(&result, &mutable, 0, .down)
            return result
        }
    }
}

/// INTPART — 取整数部分
struct INTPARTFunction: BuiltinFunction {
    let name = "INTPART"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "INTPART需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return Decimal(Int(truncating: v as NSDecimalNumber))
        }
    }
}

/// STD — 标准差
/// 用法: STD(X, N) 求X的N周期标准差
struct STDFunction: BuiltinFunction {
    let name = "STD"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "STD需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "STD的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "STD的周期必须大于0") }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if i < period - 1 { continue }
            let start = i - period + 1
            var sum: Decimal = 0
            var validCount = 0
            for j in start...i {
                guard let v = source[j] else { continue }
                sum += v
                validCount += 1
            }
            guard validCount == period else { continue }
            let avg = sum / Decimal(period)
            var variance: Decimal = 0
            for j in start...i {
                let diff = (source[j] ?? 0) - avg
                variance += diff * diff
            }
            variance = variance / Decimal(period)
            let stdVal = sqrt(NSDecimalNumber(decimal: variance).doubleValue)
            result[i] = Decimal(stdVal)
        }
        return result
    }
}

/// AVEDEV — 平均绝对偏差
/// 用法: AVEDEV(X, N)
struct AVEDEVFunction: BuiltinFunction {
    let name = "AVEDEV"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "AVEDEV需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "AVEDEV的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "AVEDEV的周期必须大于0") }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if i < period - 1 { continue }
            let start = i - period + 1
            var sum: Decimal = 0
            var validCount = 0
            for j in start...i {
                guard let v = source[j] else { continue }
                sum += v
                validCount += 1
            }
            guard validCount == period else { continue }
            let avg = sum / Decimal(period)
            var devSum: Decimal = 0
            for j in start...i {
                devSum += abs((source[j] ?? 0) - avg)
            }
            result[i] = devSum / Decimal(period)
        }
        return result
    }
}
