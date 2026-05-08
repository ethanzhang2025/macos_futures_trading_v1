// 麦语言扩展 · 第 42 批（v15.25 batch49 · 期货专属 · 期限结构 / 基差 / 跨月）
//
// 7 个函数（中国期货市场特有概念）：
//   1. BASIS(spot, future)            — 基差 = spot - future
//   2. ROLLYIELD(near, far, days)     — 移仓年化收益率 (near-far)/far/days*365
//   3. TERMSTRUCT(near, mid, far)     — 期限结构 1=contango -1=back 0=平
//   4. CONTANGO(near, far)            — 升水判定 (1=升水 0=否)
//   5. BACKWARDATION(near, far)       — 贴水判定 (1=贴水 0=否)
//   6. CONTRACTSPREAD(c1, c2)         — 跨月价差 c1 - c2
//   7. FRONTMONTH(vol1, vol2, vol3)   — 主力合约判定（量最大 1/2/3）

import Foundation

// MARK: - 1. BASIS

/// BASIS(spot, future) — 现货 - 期货
struct BASISFunction: BuiltinFunction {
    let name = "BASIS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "BASIS需要2个参数（现货价, 期货价）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let s = args[0][i], let f = args[1][i] else { continue }
            result[i] = s - f
        }
        return result
    }
}

// MARK: - 2. ROLLYIELD

/// ROLLYIELD(near, far, days) — 移仓年化收益率 = (near-far)/far/days*365
struct ROLLYIELDFunction: BuiltinFunction {
    let name = "ROLLYIELD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "ROLLYIELD需要3个参数（近月价, 远月价, 间隔天数）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let near = args[0][i], let far = args[1][i], let d = args[2][i] else { continue }
            guard far > 0, d > 0 else { continue }
            result[i] = (near - far) / far / d * 365
        }
        return result
    }
}

// MARK: - 3. TERMSTRUCT

/// TERMSTRUCT(near, mid, far) — 1=升水(contango) -1=贴水(backwardation) 0=非单调
struct TERMSTRUCTFunction: BuiltinFunction {
    let name = "TERMSTRUCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "TERMSTRUCT需要3个参数（近月, 中月, 远月）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let n = args[0][i], let m = args[1][i], let f = args[2][i] else { continue }
            if f > m && m > n { result[i] = 1 }
            else if n > m && m > f { result[i] = -1 }
            else { result[i] = 0 }
        }
        return result
    }
}

// MARK: - 4. CONTANGO

/// CONTANGO(near, far) — 1=升水（远>近）0=否
struct CONTANGOFunction: BuiltinFunction {
    let name = "CONTANGO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "CONTANGO需要2个参数（近月, 远月）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let n = args[0][i], let f = args[1][i] else { continue }
            result[i] = (f > n) ? 1 : 0
        }
        return result
    }
}

// MARK: - 5. BACKWARDATION

/// BACKWARDATION(near, far) — 1=贴水（近>远）0=否
struct BACKWARDATIONFunction: BuiltinFunction {
    let name = "BACKWARDATION"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "BACKWARDATION需要2个参数（近月, 远月）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let n = args[0][i], let f = args[1][i] else { continue }
            result[i] = (n > f) ? 1 : 0
        }
        return result
    }
}

// MARK: - 6. CONTRACTSPREAD

/// CONTRACTSPREAD(c1, c2) — 跨月价差 c1 - c2
struct CONTRACTSPREADFunction: BuiltinFunction {
    let name = "CONTRACTSPREAD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else { throw InterpreterError(message: "CONTRACTSPREAD需要2个参数（合约1, 合约2）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count,
                  let a = args[0][i], let b = args[1][i] else { continue }
            result[i] = a - b
        }
        return result
    }
}

// MARK: - 7. FRONTMONTH

/// FRONTMONTH(vol1, vol2, vol3) — 主力合约编号（量最大 → 1/2/3）
/// 三个 volume 都为 0 → nil
struct FRONTMONTHFunction: BuiltinFunction {
    let name = "FRONTMONTH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else { throw InterpreterError(message: "FRONTMONTH需要3个参数（合约1量, 合约2量, 合约3量）") }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard i < args[0].count, i < args[1].count, i < args[2].count,
                  let v1 = args[0][i], let v2 = args[1][i], let v3 = args[2][i] else { continue }
            if v1 <= 0 && v2 <= 0 && v3 <= 0 { continue }
            if v1 >= v2 && v1 >= v3 { result[i] = 1 }
            else if v2 >= v3 { result[i] = 2 }
            else { result[i] = 3 }
        }
        return result
    }
}
