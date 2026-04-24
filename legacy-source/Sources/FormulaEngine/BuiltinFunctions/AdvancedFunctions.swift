import Foundation

/// SLOPE — 线性回归斜率
/// 用法: SLOPE(X, N) 求X的N周期线性回归斜率
struct SLOPEFunction: BuiltinFunction {
    let name = "SLOPE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "SLOPE需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "SLOPE的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period >= 2 else { throw InterpreterError(message: "SLOPE的周期必须>=2") }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in (period - 1)..<count {
            let start = i - period + 1
            var sumX: Decimal = 0, sumY: Decimal = 0, sumXY: Decimal = 0, sumXX: Decimal = 0
            var valid = true
            for j in 0..<period {
                guard let y = source[start + j] else { valid = false; break }
                let x = Decimal(j)
                sumX += x; sumY += y; sumXY += x * y; sumXX += x * x
            }
            guard valid else { continue }
            let nd = Decimal(period)
            let denom = nd * sumXX - sumX * sumX
            guard denom != 0 else { continue }
            result[i] = (nd * sumXY - sumX * sumY) / denom
        }
        return result
    }
}

/// FORCAST — 线性回归预测
/// 用法: FORCAST(X, N) 求X的N周期线性回归预测下一周期值
struct FORCASTFunction: BuiltinFunction {
    let name = "FORCAST"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "FORCAST需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "FORCAST的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period >= 2 else { throw InterpreterError(message: "FORCAST的周期必须>=2") }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in (period - 1)..<count {
            let start = i - period + 1
            var sumX: Decimal = 0, sumY: Decimal = 0, sumXY: Decimal = 0, sumXX: Decimal = 0
            var valid = true
            for j in 0..<period {
                guard let y = source[start + j] else { valid = false; break }
                let x = Decimal(j)
                sumX += x; sumY += y; sumXY += x * y; sumXX += x * x
            }
            guard valid else { continue }
            let nd = Decimal(period)
            let denom = nd * sumXX - sumX * sumX
            guard denom != 0 else { continue }
            let slope = (nd * sumXY - sumX * sumY) / denom
            let intercept = (sumY - slope * sumX) / nd
            result[i] = intercept + slope * Decimal(period)
        }
        return result
    }
}

/// FILTER — 信号过滤
/// 用法: FILTER(X, N) X为真后N周期内不再为真
struct FILTERFunction: BuiltinFunction {
    let name = "FILTER"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "FILTER需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "FILTER的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: Decimal(0), count: count)
        var cooldown = 0
        for i in 0..<count {
            if cooldown > 0 { cooldown -= 1; continue }
            if let v = source[i], v != 0 {
                result[i] = 1
                cooldown = period
            }
        }
        return result
    }
}

/// BARSSINCE — 第一次满足条件到现在的周期数
/// 用法: BARSSINCE(X) 第一次X不为0到现在的周期数
struct BARSSINCEFunction: BuiltinFunction {
    let name = "BARSSINCE"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "BARSSINCE需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var firstTrue: Int?
        for i in 0..<count {
            if firstTrue == nil, let v = source[i], v != 0 {
                firstTrue = i
            }
            if let ft = firstTrue {
                result[i] = Decimal(i - ft)
            }
        }
        return result
    }
}

/// BARSCOUNT — 有效数据周期数
/// 用法: BARSCOUNT(X) 有多少根K线X有有效值
struct BARSCOUNTFunction: BuiltinFunction {
    let name = "BARSCOUNT"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "BARSCOUNT需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            result[i] = Decimal(i + 1)
        }
        return result
    }
}

/// CONST — 取最后一个值变为常量
/// 用法: CONST(X) 取X的最后一个有效值作为所有周期的值
struct CONSTFunction: BuiltinFunction {
    let name = "CONST"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "CONST需要1个参数") }
        let source = args[0]
        let lastVal = source.last(where: { $0 != nil }) ?? nil
        return Array(repeating: lastVal, count: source.count)
    }
}

/// LAST — 持续满足
/// 用法: LAST(X, A, B) 从前A周期到前B周期内X一直不为0
struct LASTFunction: BuiltinFunction {
    let name = "LAST"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "LAST需要3个参数") }
        let source = args[0]
        guard let aVal = args[1].first, let a = aVal,
              let bVal = args[2].first, let b = bVal else {
            throw InterpreterError(message: "LAST的参数无效")
        }
        let aInt = Int(truncating: a as NSDecimalNumber)
        let bInt = Int(truncating: b as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let from = i - aInt
            let to = i - bInt
            guard from >= 0 && to >= 0 && from <= to else { result[i] = 0; continue }
            var allTrue = true
            for j in from...to {
                guard j < count, let v = source[j], v != 0 else { allTrue = false; break }
            }
            result[i] = allTrue ? 1 : 0
        }
        return result
    }
}

/// DEVSQ — 偏差平方和
/// 用法: DEVSQ(X, N) 求X的N周期偏差平方和
struct DEVSQFunction: BuiltinFunction {
    let name = "DEVSQ"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "DEVSQ需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "DEVSQ的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in (period - 1)..<count {
            let start = i - period + 1
            var sum: Decimal = 0
            var valid = true
            for j in start...i {
                guard let v = source[j] else { valid = false; break }
                sum += v
            }
            guard valid else { continue }
            let avg = sum / Decimal(period)
            var devSq: Decimal = 0
            for j in start...i {
                let diff = (source[j] ?? 0) - avg
                devSq += diff * diff
            }
            result[i] = devSq
        }
        return result
    }
}

/// ROUND — 四舍五入
/// 用法: ROUND(X) 或 ROUND(X, N) 四舍五入到N位小数（默认0位）
struct ROUNDFunction: BuiltinFunction {
    let name = "ROUND"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count >= 1 && args.count <= 2 else {
            throw InterpreterError(message: "ROUND需要1-2个参数")
        }
        let source = args[0]
        let places: Int
        if args.count == 2, let pVal = args[1].first, let p = pVal {
            places = Int(truncating: p as NSDecimalNumber)
        } else {
            places = 0
        }
        return source.map { v in
            guard var v else { return nil }
            var result = Decimal()
            NSDecimalRound(&result, &v, places, .plain)
            return result
        }
    }
}

/// SIGN — 符号函数
/// 用法: SIGN(X) X>0返回1, X<0返回-1, X=0返回0
struct SIGNFunction: BuiltinFunction {
    let name = "SIGN"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "SIGN需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            if v > 0 { return Decimal(1) }
            if v < 0 { return Decimal(-1) }
            return Decimal(0)
        }
    }
}

/// SUMBARS — 向前累加到满足条件的周期数
/// 用法: SUMBARS(X, A) 求X向前累加直到>=A所需的周期数
struct SUMBARSFunction: BuiltinFunction {
    let name = "SUMBARS"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "SUMBARS需要2个参数") }
        let source = args[0]
        guard let targetVal = args[1].first, let target = targetVal else {
            throw InterpreterError(message: "SUMBARS的目标参数无效")
        }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            var sum: Decimal = 0
            for j in stride(from: i, through: 0, by: -1) {
                guard let v = source[j] else { break }
                sum += v
                if sum >= target {
                    result[i] = Decimal(i - j + 1)
                    break
                }
            }
        }
        return result
    }
}

/// MULAR — 累乘
/// 用法: MULAR(X, N) 求X的N周期累乘
struct MULARFunction: BuiltinFunction {
    let name = "MULAR"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "MULAR需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "MULAR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in (period - 1)..<count {
            let start = i - period + 1
            var product: Decimal = 1
            var valid = true
            for j in start...i {
                guard let v = source[j] else { valid = false; break }
                product *= v
            }
            if valid { result[i] = product }
        }
        return result
    }
}
