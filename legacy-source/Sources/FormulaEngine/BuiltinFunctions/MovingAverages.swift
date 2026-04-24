import Foundation

/// MA — 简单移动平均
/// 用法: MA(X, N) 求X的N周期简单移动平均
struct MAFunction: BuiltinFunction {
    let name = "MA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "MA需要2个参数")
        }
        let source = args[0]
        guard let periodVal = args[1].first, let period = periodVal else {
            throw InterpreterError(message: "MA的周期参数无效")
        }
        let n = Int(truncating: period as NSDecimalNumber)
        guard n > 0 else {
            throw InterpreterError(message: "MA的周期必须大于0")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            if i < n - 1 { continue }
            var sum: Decimal = 0
            var valid = true
            for j in (i - n + 1)...i {
                guard let v = source[j] else { valid = false; break }
                sum += v
            }
            if valid {
                var avg = sum / Decimal(n)
                var rounded = Decimal()
                NSDecimalRound(&rounded, &avg, 8, .plain)
                result[i] = rounded
            }
        }
        return result
    }
}

/// EMA — 指数移动平均
/// 用法: EMA(X, N) 求X的N周期指数移动平均
/// 公式: EMA(i) = 2/(N+1) * X(i) + (N-1)/(N+1) * EMA(i-1)
struct EMAFunction: BuiltinFunction {
    let name = "EMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "EMA需要2个参数")
        }
        let source = args[0]
        guard let periodVal = args[1].first, let period = periodVal else {
            throw InterpreterError(message: "EMA的周期参数无效")
        }
        let n = Int(truncating: period as NSDecimalNumber)
        guard n > 0 else {
            throw InterpreterError(message: "EMA的周期必须大于0")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        let multiplier = Decimal(2) / Decimal(n + 1)

        var prevEma: Decimal?
        for i in 0..<count {
            guard let value = source[i] else { continue }
            if prevEma == nil {
                prevEma = value
            } else {
                prevEma = multiplier * value + (1 - multiplier) * prevEma!
            }
            result[i] = prevEma
        }
        return result
    }
}

/// SMA — 加权移动平均（通达信特有）
/// 用法: SMA(X, N, M) = (M * X + (N-M) * SMA') / N
struct SMAFunction: BuiltinFunction {
    let name = "SMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "SMA需要3个参数")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal,
              let mVal = args[2].first, let m = mVal else {
            throw InterpreterError(message: "SMA的参数无效")
        }
        let nInt = Int(truncating: n as NSDecimalNumber)
        guard nInt > 0 else {
            throw InterpreterError(message: "SMA的N必须大于0")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)

        var prev: Decimal?
        for i in 0..<count {
            guard let value = source[i] else { continue }
            if prev == nil {
                prev = value
            } else {
                prev = (m * value + (Decimal(nInt) - m) * prev!) / Decimal(nInt)
            }
            result[i] = prev
        }
        return result
    }
}
