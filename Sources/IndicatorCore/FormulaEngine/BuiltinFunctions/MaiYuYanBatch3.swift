// 麦语言扩展 · 第 3 批（v15.25 batch001 · ~95% → ~99% 兼容度）
//
// 5 个 trader 实用边角函数（避开画图/筹码分布/命名非标）：
//   1. TR        — 真实波幅 max(H-L, |H-prevC|, |L-prevC|)
//   2. ATR       — 平均真实波幅 = MA(TR, N) · 止损 / 波动率系统基础
//   3. TROUGH    — 最近一次波谷的值（与 LASTPEAK 对称 · 配套 TROUGHBARS）
//   4. HHVCROSS  — 上穿前 N 周期最高（突破系统 · 与 priceBreakoutHigh AlertCondition 对应）
//   5. REFV      — 浮动周期引用 REFV(X, N) · N 是 series 而非常量（动态周期算法）
//
// Stage A 工作包清单第 3 批预留补完 · 麦语言扩展收尾

import Foundation

// MARK: - 1. TR

/// TR — True Range 真实波幅
/// = MAX(MAX(HIGH - LOW, ABS(HIGH - REF(CLOSE,1))), ABS(LOW - REF(CLOSE,1)))
/// 用法：TR · 不需参数 · 直接读 bars 的 H/L/C
/// 第一根 bar 没有 prevClose · 退化为 H - L
struct TRFunction: BuiltinFunction {
    let name = "TR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "TR不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let h = bars[i].high
            let l = bars[i].low
            let hl = h - l
            if i == 0 {
                result[i] = hl
            } else {
                let prevC = bars[i - 1].close
                let hPrevC = abs(h - prevC)
                let lPrevC = abs(l - prevC)
                result[i] = max(max(hl, hPrevC), lPrevC)
            }
        }
        return result
    }
}

// MARK: - 2. ATR

/// ATR — 平均真实波幅 = MA(TR, N)
/// 用法：ATR(N) · trader 常用 ATR(14) 做止损宽度
/// 实现：内部先算 TR · 再走简单移动平均
struct ATRFunction: BuiltinFunction {
    let name = "ATR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ATR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ATR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ATR的周期必须为正整数")
        }

        // Step 1：算 TR
        let count = bars.count
        var tr = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let h = bars[i].high
            let l = bars[i].low
            let hl = h - l
            if i == 0 {
                tr[i] = hl
            } else {
                let prevC = bars[i - 1].close
                let hPrevC = abs(h - prevC)
                let lPrevC = abs(l - prevC)
                tr[i] = max(max(hl, hPrevC), lPrevC)
            }
        }

        // Step 2：MA(TR, N)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var validCount = 0
            for j in start...i {
                if let v = tr[j] {
                    sum += v
                    validCount += 1
                }
            }
            if validCount > 0 {
                result[i] = sum / Decimal(validCount)
            }
        }
        return result
    }
}

// MARK: - 3. TROUGH

/// TROUGH — 最近一次波谷的值（与 LASTPEAK 对称 · 配套 TROUGHBARS）
/// 波谷定义：X[i-1] < X[i-2] && X[i-1] < X[i] · 即局部最小
/// 用法：TROUGH(CLOSE) 返回最近一次局部最小值
struct TROUGHFunction: BuiltinFunction {
    let name = "TROUGH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "TROUGH需要1个参数")
        }
        let x = args[0]
        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastTroughValue: Decimal?
        for i in 0..<count {
            if i >= 2,
               let prev = x[i - 1], let prev2 = x[i - 2], let curr = x[i],
               prev < prev2 && prev < curr {
                lastTroughValue = prev
            }
            result[i] = lastTroughValue
        }
        return result
    }
}

// MARK: - 4. HHVCROSS

/// HHVCROSS — 上穿前 N 周期最高（突破系统）
/// 定义：CROSS(X, REF(HHV(X, N), 1))
/// 即当前值首次上穿"上一根的 N 周期最高"·
/// 与 AlertCondition.priceBreakoutHigh 对应 · trader Donchian 通道突破信号源
struct HHVCROSSFunction: BuiltinFunction {
    let name = "HHVCROSS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "HHVCROSS需要2个参数（X, N）")
        }
        let source = args[0]
        guard let nVal = args[1].first, let n = nVal else {
            throw InterpreterError(message: "HHVCROSS的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "HHVCROSS的周期必须为正整数")
        }

        let count = source.count
        var result = [Decimal?](repeating: nil, count: count)

        // 算 HHV(X, period)
        var hhv = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var highest: Decimal?
            for j in start...i {
                guard let v = source[j] else { continue }
                if highest == nil || v > highest! { highest = v }
            }
            hhv[i] = highest
        }

        // CROSS(source, REF(hhv, 1))
        for i in 1..<count {
            guard let curr = source[i],
                  let prevSrc = source[i - 1],
                  let target = hhv[i - 1]
            else { continue }
            // 上穿：前一根 < target · 当前根 >= target
            if prevSrc < target && curr >= target {
                result[i] = 1
            } else {
                result[i] = 0
            }
        }
        return result
    }
}

// MARK: - 5. REFV

/// REFV — 浮动周期引用 REFV(X, N)
/// N 是 series（每根 bar 自己的偏移量）· 与 REF（N 是常量）互补
/// 用法：REFV(CLOSE, BARSLAST(C>O)) · 引用最近一次满足条件 N 根前的 close
struct REFVFunction: BuiltinFunction {
    let name = "REFV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "REFV需要2个参数（X, N_series）")
        }
        let source = args[0]
        let offsets = args[1]
        let count = source.count
        guard offsets.count == count else {
            throw InterpreterError(message: "REFV的偏移序列长度需与源序列一致")
        }
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let nVal = offsets[i] else { continue }
            let offset = Int(truncating: nVal as NSDecimalNumber)
            guard offset >= 0, i - offset >= 0 else { continue }
            result[i] = source[i - offset]
        }
        return result
    }
}
