// 麦语言扩展 · 第 25 批（v15.25 batch32 · 数学完备 + 最大回撤）
//
// 7 个数学函数 + 风险管理：
//   1. SIN(X)         — 正弦
//   2. COS(X)         — 余弦
//   3. ATAN(X)        — 反正切
//   4. PI()           — π 常数（≈3.14159）
//   5. MAXDD(X)       — 最大回撤（绝对值）= max(prev high - current)
//   6. MAXDDPCT(X)    — 最大回撤百分比 = MAXDD(X) / prev high * 100
//   7. DRAWDOWN(X)    — 当前回撤（高点到当前）

import Foundation

// MARK: - 1. SIN

struct SINFunction: BuiltinFunction {
    let name = "SIN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "SIN需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return Decimal(sin(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

// MARK: - 2. COS

struct COSFunction: BuiltinFunction {
    let name = "COS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "COS需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return Decimal(cos(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

// MARK: - 3. ATAN

struct ATANFunction: BuiltinFunction {
    let name = "ATAN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "ATAN需要1个参数") }
        return args[0].map { v in
            guard let v else { return nil }
            return Decimal(atan(NSDecimalNumber(decimal: v).doubleValue))
        }
    }
}

// MARK: - 4. PI

/// PI() — π 常数（每根 bar 都返 π）
struct PIFunction: BuiltinFunction {
    let name = "PI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else { throw InterpreterError(message: "PI不需要参数") }
        let pi = Decimal(Double.pi)
        return [Decimal?](repeating: pi, count: bars.count)
    }
}

// MARK: - 5. MAXDD

/// MAXDD(X) — 截至当前的最大回撤（绝对值）
/// 公式：max over j <= i 的 (max_prev_X[j] - X[i])
/// max_prev_X[j] = max X 从 0 到 j
struct MAXDDFunction: BuiltinFunction {
    let name = "MAXDD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "MAXDD需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var runningMax: Decimal?
        var maxDD: Decimal = 0
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if runningMax == nil || v > runningMax! { runningMax = v }
            if let m = runningMax {
                let dd = m - v
                if dd > maxDD { maxDD = dd }
            }
            result[i] = maxDD
        }
        return result
    }
}

// MARK: - 6. MAXDDPCT

/// MAXDDPCT(X) — 最大回撤百分比（基于历史峰值）
/// 公式：max over j <= i 的 (max_prev[j] - X[i]) / max_prev[j] * 100
struct MAXDDPCTFunction: BuiltinFunction {
    let name = "MAXDDPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "MAXDDPCT需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var runningMax: Decimal?
        var maxDDPct: Decimal = 0
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if runningMax == nil || v > runningMax! { runningMax = v }
            if let m = runningMax, m > 0 {
                let ddPct = (m - v) / m * 100
                if ddPct > maxDDPct { maxDDPct = ddPct }
            }
            result[i] = maxDDPct
        }
        return result
    }
}

// MARK: - 7. DRAWDOWN

/// DRAWDOWN(X) — 当前回撤（历史高点到当前）
/// 公式：max_prev[i] - X[i]
struct DRAWDOWNFunction: BuiltinFunction {
    let name = "DRAWDOWN"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else { throw InterpreterError(message: "DRAWDOWN需要1个参数") }
        let source = args[0]
        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)
        var runningMax: Decimal?
        for i in 0..<count {
            guard let v = source[i] else { continue }
            if runningMax == nil || v > runningMax! { runningMax = v }
            if let m = runningMax {
                result[i] = m - v
            }
        }
        return result
    }
}
