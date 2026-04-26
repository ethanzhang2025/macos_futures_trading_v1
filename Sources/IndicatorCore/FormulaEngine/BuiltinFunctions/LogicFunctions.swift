import Foundation

/// IF — 条件函数
/// 用法: IF(条件, A, B) 条件为真返回A，否则返回B
struct IFFunction: BuiltinFunction {
    let name = "IF"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "IF需要3个参数")
        }
        let cond = args[0], trueVal = args[1], falseVal = args[2]
        let count = cond.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let c = cond[i] else { continue }
            result[i] = c != 0 ? trueVal[i] : falseVal[i]
        }
        return result
    }
}

/// CROSS — 上穿
/// 用法: CROSS(A, B) 当A从下方穿越B时返回1
struct CROSSFunction: BuiltinFunction {
    let name = "CROSS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CROSS需要2个参数")
        }
        let a = args[0], b = args[1]
        let count = a.count
        var result = [Decimal?](repeating: Decimal(0), count: count)
        for i in 1..<count {
            guard let currA = a[i], let currB = b[i],
                  let prevA = a[i - 1], let prevB = b[i - 1] else { continue }
            if prevA <= prevB && currA > currB {
                result[i] = 1
            }
        }
        return result
    }
}

/// EVERY — 一直满足
/// 用法: EVERY(X, N) N周期内X一直不为0则返回1
struct EVERYFunction: BuiltinFunction {
    let name = "EVERY"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "EVERY需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "EVERY的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if i < period - 1 { result[i] = 0; continue }
            let start = i - period + 1
            var allTrue = true
            for j in start...i {
                if let v = source[j], v != 0 { continue }
                allTrue = false; break
            }
            result[i] = allTrue ? 1 : 0
        }
        return result
    }
}

/// EXIST — 存在满足
/// 用法: EXIST(X, N) N周期内至少有一次X不为0则返回1
struct EXISTFunction: BuiltinFunction {
    let name = "EXIST"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "EXIST需要2个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "EXIST的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var found = false
            for j in start...i {
                if let v = source[j], v != 0 { found = true; break }
            }
            result[i] = found ? 1 : 0
        }
        return result
    }
}

/// ABS — 绝对值
struct ABSFunction: BuiltinFunction {
    let name = "ABS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ABS需要1个参数")
        }
        return args[0].map { v in
            guard let v else { return nil }
            return abs(v)
        }
    }
}

/// MAX — 取较大值
/// 用法: MAX(A, B) 返回A和B中的较大值
struct MAXFunction: BuiltinFunction {
    let name = "MAX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MAX需要2个参数")
        }
        let a = args[0], b = args[1]
        let count = max(a.count, b.count)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let va = i < a.count ? a[i] : nil,
                  let vb = i < b.count ? b[i] : nil else { continue }
            result[i] = Swift.max(va, vb)
        }
        return result
    }
}

/// MIN — 取较小值
/// 用法: MIN(A, B) 返回A和B中的较小值
struct MINFunction: BuiltinFunction {
    let name = "MIN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MIN需要2个参数")
        }
        let a = args[0], b = args[1]
        let count = max(a.count, b.count)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let va = i < a.count ? a[i] : nil,
                  let vb = i < b.count ? b[i] : nil else { continue }
            result[i] = Swift.min(va, vb)
        }
        return result
    }
}

/// NOT — 逻辑非
/// 用法: NOT(X) X 为 0 返回 1；非 0 返回 0；nil 透传
struct NOTFunction: BuiltinFunction {
    let name = "NOT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "NOT需要1个参数")
        }
        return args[0].map { v in
            guard let v else { return nil }
            return v == 0 ? 1 : 0
        }
    }
}

/// CROSSDOWN — 下穿（与 CROSS 对称 · CROSS 是上穿）
/// 用法: CROSSDOWN(A, B) 当 A 从上方穿越 B 时返回 1
struct CROSSDOWNFunction: BuiltinFunction {
    let name = "CROSSDOWN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CROSSDOWN需要2个参数")
        }
        let a = args[0], b = args[1]
        let count = a.count
        var result = [Decimal?](repeating: Decimal(0), count: count)
        for i in 1..<count {
            guard let currA = a[i], let currB = b[i],
                  let prevA = a[i - 1], let prevB = b[i - 1] else { continue }
            if prevA >= prevB && currA < currB {
                result[i] = 1
            }
        }
        return result
    }
}
