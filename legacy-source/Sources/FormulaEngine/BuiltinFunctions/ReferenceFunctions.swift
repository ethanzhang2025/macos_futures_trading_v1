import Foundation

/// HHVBARS — 最高值到当前的周期数
/// 用法: HHVBARS(X, N) 求N周期内X最高值到当前的周期数
struct HHVBARSFunction: BuiltinFunction {
    let name = "HHVBARS"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "HHVBARS需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "HHVBARS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var highIdx = start
            var highest: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if highest == nil || v > highest! { highest = v; highIdx = j }
            }
            result[i] = Decimal(i - highIdx)
        }
        return result
    }
}

/// LLVBARS — 最低值到当前的周期数
/// 用法: LLVBARS(X, N) 求N周期内X最低值到当前的周期数
struct LLVBARSFunction: BuiltinFunction {
    let name = "LLVBARS"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "LLVBARS需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "LLVBARS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var lowIdx = start
            var lowest: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if lowest == nil || v < lowest! { lowest = v; lowIdx = j }
            }
            result[i] = Decimal(i - lowIdx)
        }
        return result
    }
}

/// LONGCROSS — 持续上穿
/// 用法: LONGCROSS(A, B, N) A在N周期内都小于等于B后上穿B
struct LONGCROSSFunction: BuiltinFunction {
    let name = "LONGCROSS"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "LONGCROSS需要3个参数") }
        let a = args[0], b = args[1]
        guard let nVal = args[2].first, let n = nVal else {
            throw InterpreterError(message: "LONGCROSS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        let count = a.count
        var result = [Decimal?](repeating: Decimal(0), count: count)
        for i in 1..<count {
            guard let currA = a[i], let currB = b[i],
                  let prevA = a[i - 1], let prevB = b[i - 1] else { continue }
            guard prevA <= prevB && currA > currB else { continue }
            // 检查前N周期A是否一直<=B
            let start = max(0, i - period)
            var allBelow = true
            for j in start..<i {
                guard let va = a[j], let vb = b[j] else { allBelow = false; break }
                if va > vb { allBelow = false; break }
            }
            if allBelow { result[i] = 1 }
        }
        return result
    }
}

/// BETWEEN — 介于两值之间
/// 用法: BETWEEN(A, B, C) A在B和C之间返回1
struct BETWEENFunction: BuiltinFunction {
    let name = "BETWEEN"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "BETWEEN需要3个参数") }
        let a = args[0], b = args[1], c = args[2]
        let count = a.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let va = a[i], let vb = b[i], let vc = c[i] else { continue }
            let lo = min(vb, vc)
            let hi = max(vb, vc)
            result[i] = (va >= lo && va <= hi) ? 1 : 0
        }
        return result
    }
}

/// VALUEWHEN — 条件成立时的值
/// 用法: VALUEWHEN(COND, X) 当COND成立时取X的值，否则用上一次的值
struct VALUEWHENFunction: BuiltinFunction {
    let name = "VALUEWHEN"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "VALUEWHEN需要2个参数") }
        let cond = args[0], source = args[1]
        let count = cond.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastVal: Decimal?
        for i in 0..<count {
            if let c = cond[i], c != 0 {
                lastVal = source[i]
            }
            result[i] = lastVal
        }
        return result
    }
}

/// IFF — 立即条件（同IF，通达信兼容）
struct IFFFunction: BuiltinFunction {
    let name = "IFF"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "IFF需要3个参数") }
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

/// DMA — 动态移动平均
/// 用法: DMA(X, A) 求X的动态移动平均，A为权重(0~1)
/// 公式: DMA(i) = A * X(i) + (1 - A) * DMA(i-1)
struct DMAFunction: BuiltinFunction {
    let name = "DMA"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "DMA需要2个参数") }
        let source = args[0], weight = args[1]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var prev: Decimal?
        for i in 0..<count {
            guard let value = source[i], let w = weight[i] else { continue }
            let a = max(0, min(1, w))
            if prev == nil {
                prev = value
            } else {
                prev = a * value + (1 - a) * prev!
            }
            result[i] = prev
        }
        return result
    }
}

/// WMA — 加权移动平均
/// 用法: WMA(X, N) 加权移动平均，权重为1,2,3,...,N
struct WMAFunction: BuiltinFunction {
    let name = "WMA"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "WMA需要2个参数") }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "WMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "WMA的周期必须大于0") }
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        let weightSum = Decimal(period * (period + 1) / 2)
        for i in 0..<count {
            if i < period - 1 { continue }
            var sum: Decimal = 0
            var valid = true
            for j in 0..<period {
                guard let v = source[i - period + 1 + j] else { valid = false; break }
                sum += v * Decimal(j + 1)
            }
            if valid { result[i] = sum / weightSum }
        }
        return result
    }
}
