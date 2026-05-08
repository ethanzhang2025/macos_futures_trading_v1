// 麦语言扩展 · 第 39 批（v15.25 batch46 · 基础差值 + 中价 MA）
//
// 7 个简单封装函数（trader 直接写法 alias）：
//   1. HLDIFF()     — H - L 振幅
//   2. HCDIFF()     — H - C（与 UPPERWICK 类似但不限实体）
//   3. CLDIFF()     — C - L
//   4. OCDIFF()     — O - C
//   5. TPRMA(N)     — MA(TYP, N) · 典型价均线
//   6. HLAVGMA(N)   — MA((H+L)/2, N) · 中价均线
//   7. OCAVGMA(N)   — MA((O+C)/2, N) · 开收均线

import Foundation

// MARK: - 1. HLDIFF

struct HLDIFFFunction: BuiltinFunction {
    let name = "HLDIFF"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HLDIFF不需要参数") }
        return bars.map { Optional($0.high - $0.low) }
    }
}

// MARK: - 2. HCDIFF

struct HCDIFFFunction: BuiltinFunction {
    let name = "HCDIFF"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "HCDIFF不需要参数") }
        return bars.map { Optional($0.high - $0.close) }
    }
}

// MARK: - 3. CLDIFF

struct CLDIFFFunction: BuiltinFunction {
    let name = "CLDIFF"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "CLDIFF不需要参数") }
        return bars.map { Optional($0.close - $0.low) }
    }
}

// MARK: - 4. OCDIFF

struct OCDIFFFunction: BuiltinFunction {
    let name = "OCDIFF"
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "OCDIFF不需要参数") }
        return bars.map { Optional($0.open - $0.close) }
    }
}

// MARK: - 5. TPRMA

/// TPRMA(N) — MA(TYP, N) = MA((H+L+C)/3, N)
struct TPRMAFunction: BuiltinFunction {
    let name = "TPRMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "TPRMA需要1个参数（周期N）") }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "TPRMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "TPRMA的周期必须为正整数") }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i {
                sum += (bars[j].high + bars[j].low + bars[j].close) / 3
            }
            result[i] = sum / Decimal(i - s + 1)
        }
        return result
    }
}

// MARK: - 6. HLAVGMA

/// HLAVGMA(N) — MA((H+L)/2, N)
struct HLAVGMAFunction: BuiltinFunction {
    let name = "HLAVGMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "HLAVGMA需要1个参数（周期N）") }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "HLAVGMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "HLAVGMA的周期必须为正整数") }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i {
                sum += (bars[j].high + bars[j].low) / 2
            }
            result[i] = sum / Decimal(i - s + 1)
        }
        return result
    }
}

// MARK: - 7. OCAVGMA

/// OCAVGMA(N) — MA((O+C)/2, N)
struct OCAVGMAFunction: BuiltinFunction {
    let name = "OCAVGMA"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "OCAVGMA需要1个参数（周期N）") }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "OCAVGMA的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else { throw InterpreterError(message: "OCAVGMA的周期必须为正整数") }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in s...i {
                sum += (bars[j].open + bars[j].close) / 2
            }
            result[i] = sum / Decimal(i - s + 1)
        }
        return result
    }
}
