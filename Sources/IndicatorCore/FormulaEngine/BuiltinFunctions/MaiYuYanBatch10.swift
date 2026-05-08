// 麦语言扩展 · 第 10 批（v15.25 batch17 · ~99.98% → ~99.99% 兼容度）
//
// 7 个枢轴/能量/AD 函数：
//   1. PIVOT()       — Pivot Point = (REF(H,1)+REF(L,1)+REF(C,1))/3
//   2. R1()          — Resistance 1 = 2*PIVOT - REF(L,1)
//   3. S1()          — Support 1 = 2*PIVOT - REF(H,1)
//   4. CR(N)         — 能量指标（中国市场常用）= 上扬量/下扬量*100
//   5. WVAD(N)       — Williams V·A·D 量价累计
//   6. AROONL(N)     — Aroon Up（距 N 周期最高的 bar 数距离）
//   7. AROONS(N)     — Aroon Down（距 N 周期最低的 bar 数距离）

import Foundation

// MARK: - 1. PIVOT

/// PIVOT — 枢轴点 = (REF(H,1) + REF(L,1) + REF(C,1)) / 3
/// 用前一根的 H/L/C 算当根的中枢（标准定义）
struct PIVOTFunction: BuiltinFunction {
    let name = "PIVOT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "PIVOT不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = (bars[i - 1].high + bars[i - 1].low + bars[i - 1].close) / 3
        }
        return result
    }
}

// MARK: - 2. R1

/// R1 — Resistance 1 = 2*PIVOT - REF(L, 1)
struct R1Function: BuiltinFunction {
    let name = "R1"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "R1不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let pivot = (bars[i - 1].high + bars[i - 1].low + bars[i - 1].close) / 3
            result[i] = 2 * pivot - bars[i - 1].low
        }
        return result
    }
}

// MARK: - 3. S1

/// S1 — Support 1 = 2*PIVOT - REF(H, 1)
struct S1Function: BuiltinFunction {
    let name = "S1"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "S1不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let pivot = (bars[i - 1].high + bars[i - 1].low + bars[i - 1].close) / 3
            result[i] = 2 * pivot - bars[i - 1].high
        }
        return result
    }
}

// MARK: - 4. CR

/// CR — 能量指标
/// 公式：
///   MID = REF((H + L) / 2, 1)
///   UP = SUM(MAX(0, H - MID), N)
///   DOWN = SUM(MAX(0, MID - L), N)
///   CR = UP / DOWN * 100
/// 经验：CR > 200 多头 / CR < 50 空头
struct CRFunction: BuiltinFunction {
    let name = "CR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "CR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "CR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let start = max(1, i - period + 1)
            var up: Decimal = 0
            var down: Decimal = 0
            for j in start...i {
                let mid = (bars[j - 1].high + bars[j - 1].low) / 2
                let upTerm = bars[j].high - mid
                let downTerm = mid - bars[j].low
                if upTerm > 0 { up += upTerm }
                if downTerm > 0 { down += downTerm }
            }
            if down > 0 {
                result[i] = up / down * 100
            } else {
                // 连续上涨无下扬 · 极端多头 · 返大数（与 VR 处理一致）
                result[i] = up > 0 ? Decimal(string: "999")! : 0
            }
        }
        return result
    }
}

// MARK: - 5. WVAD

/// WVAD — Williams Volume Accumulation/Distribution
/// 公式：
///   AD = (CLOSE - OPEN) / (HIGH - LOW) * VOLUME
///   WVAD = SUM(AD, N)
/// 用途：量价综合 · 与 OBV 相比考虑了实体大小
struct WVADFunction: BuiltinFunction {
    let name = "WVAD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "WVAD需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "WVAD的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "WVAD的周期必须为正整数")
        }

        let count = bars.count
        // AD per bar
        var ad = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let span = bars[i].high - bars[i].low
            guard span > 0 else {
                ad[i] = 0
                continue
            }
            let factor = (bars[i].close - bars[i].open) / span
            ad[i] = factor * Decimal(bars[i].volume)
        }

        // SUM(AD, N)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i {
                if let v = ad[j] { sum += v }
            }
            result[i] = sum
        }
        return result
    }
}

// MARK: - 6. AROONL

/// AROONL — Aroon Up
/// 公式：(N - 距 N 周期最高的 bar 数) / N * 100
/// 范围 [0, 100] · 100 = 当前根就是最高 / 0 = N 周期前是最高
struct AROONLFunction: BuiltinFunction {
    let name = "AROONL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AROONL需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AROONL的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AROONL的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var maxVal: Decimal = bars[start].high
            var maxIdx = start
            for j in start...i {
                if bars[j].high > maxVal { maxVal = bars[j].high; maxIdx = j }
            }
            let len = i - start + 1
            let denom = max(len - 1, 1)
            result[i] = Decimal(len - 1 - (i - maxIdx)) / Decimal(denom) * 100
        }
        return result
    }
}

// MARK: - 7. AROONS

/// AROONS — Aroon Down
/// 公式：(N - 距 N 周期最低的 bar 数) / N * 100
struct AROONSFunction: BuiltinFunction {
    let name = "AROONS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "AROONS需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "AROONS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "AROONS的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var minVal: Decimal = bars[start].low
            var minIdx = start
            for j in start...i {
                if bars[j].low < minVal { minVal = bars[j].low; minIdx = j }
            }
            let len = i - start + 1
            let denom = max(len - 1, 1)
            result[i] = Decimal(len - 1 - (i - minIdx)) / Decimal(denom) * 100
        }
        return result
    }
}
