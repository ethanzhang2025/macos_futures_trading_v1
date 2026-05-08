// 麦语言扩展 · 第 12 批（v15.25 batch19 · ~99.995% → ~99.997% 兼容度）
//
// 7 个 trader 进阶趋势 / 反转 / 振荡函数：
//   1. SUPERTREND(N, M)    — Supertrend · trader 流行的趋势止损线
//   2. CHANDELIERL(N, M)   — Chandelier Long Exit = HHV(H, N) - M*ATR(N)
//   3. CHANDELIERS(N, M)   — Chandelier Short Exit = LLV(L, N) + M*ATR(N)
//   4. AO()                — Bill Williams Awesome Oscillator = MA(MED, 5) - MA(MED, 34)
//   5. AC()                — Bill Williams Acceleration = AO - MA(AO, 5)
//   6. FRACTALH()          — Bill Williams Fractal High（5-bar 局部峰）
//   7. FRACTALL()          — Bill Williams Fractal Low（5-bar 局部谷）

import Foundation

// MARK: - 1. SUPERTREND

/// SUPERTREND — 流行的趋势止损线
/// 公式：
///   HL2 = (H + L) / 2
///   atr = ATR(N)
///   upBand = HL2 + M * atr
///   downBand = HL2 - M * atr
///   if close[i-1] > upBand[i-1] → trend long，ST[i] = downBand[i]
///   if close[i-1] < downBand[i-1] → trend short，ST[i] = upBand[i]
///   else 跟随前一根 trend
/// 用法：SUPERTREND(10, 3) trader 标准参数
struct SUPERTRENDFunction: BuiltinFunction {
    let name = "SUPERTREND"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "SUPERTREND需要2个参数（N, M）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let mVal = args[1].first, let m = mVal else {
            throw InterpreterError(message: "SUPERTREND的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "SUPERTREND的周期必须为正整数")
        }

        let count = bars.count
        let atr = MaiB12ATR.compute(bars: bars, period: period)

        var upBand = [Decimal?](repeating: nil, count: count)
        var downBand = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let a = atr[i] else { continue }
            let hl2 = (bars[i].high + bars[i].low) / 2
            upBand[i] = hl2 + m * a
            downBand[i] = hl2 - m * a
        }

        var result = [Decimal?](repeating: nil, count: count)
        var trendIsLong = true
        for i in 0..<count {
            guard let up = upBand[i], let dn = downBand[i] else { continue }
            if i == 0 {
                result[i] = dn
                trendIsLong = true
                continue
            }
            let prevClose = bars[i - 1].close
            let wasLong = trendIsLong
            // 翻转判定（基于前一根 close 与前一根 ST 比较）
            if let prevST = result[i - 1] {
                if wasLong && prevClose < prevST {
                    trendIsLong = false
                } else if !wasLong && prevClose > prevST {
                    trendIsLong = true
                }
            }
            // 标准 SUPERTREND rolling lock：
            // long 时 ST = max(downBand, prevST) · 只升不降
            // short 时 ST = min(upBand, prevST) · 只降不升
            if trendIsLong {
                if wasLong, let prevST = result[i - 1] {
                    result[i] = max(dn, prevST)
                } else {
                    result[i] = dn
                }
            } else {
                if !wasLong, let prevST = result[i - 1] {
                    result[i] = min(up, prevST)
                } else {
                    result[i] = up
                }
            }
        }
        return result
    }
}

// MARK: - 2. CHANDELIERL

/// CHANDELIERL — Chandelier Long Exit
/// 公式：HHV(HIGH, N) - M * ATR(N)
/// trader 多头追踪止损 · close 跌破即止损
struct CHANDELIERLFunction: BuiltinFunction {
    let name = "CHANDELIERL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CHANDELIERL需要2个参数（N, M）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let mVal = args[1].first, let m = mVal else {
            throw InterpreterError(message: "CHANDELIERL的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CHANDELIERL的周期必须为正整数")
        }

        let count = bars.count
        let atr = MaiB12ATR.compute(bars: bars, period: period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hhv: Decimal = bars[start].high
            for j in start...i {
                if bars[j].high > hhv { hhv = bars[j].high }
            }
            guard let a = atr[i] else { continue }
            result[i] = hhv - m * a
        }
        return result
    }
}

// MARK: - 3. CHANDELIERS

/// CHANDELIERS — Chandelier Short Exit
/// 公式：LLV(LOW, N) + M * ATR(N)
struct CHANDELIERSFunction: BuiltinFunction {
    let name = "CHANDELIERS"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "CHANDELIERS需要2个参数（N, M）")
        }
        guard let nVal = args[0].first, let n = nVal,
              let mVal = args[1].first, let m = mVal else {
            throw InterpreterError(message: "CHANDELIERS的参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CHANDELIERS的周期必须为正整数")
        }

        let count = bars.count
        let atr = MaiB12ATR.compute(bars: bars, period: period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var llv: Decimal = bars[start].low
            for j in start...i {
                if bars[j].low < llv { llv = bars[j].low }
            }
            guard let a = atr[i] else { continue }
            result[i] = llv + m * a
        }
        return result
    }
}

// MARK: - 4. AO

/// AO — Awesome Oscillator (Bill Williams)
/// 公式：MA(MED, 5) - MA(MED, 34) · MED = (H+L)/2
/// 用途：动量振荡 · 上穿 0 多 / 下穿 0 空 / 颜色变化（红绿）做信号
struct AOFunction: BuiltinFunction {
    let name = "AO"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "AO不需要参数（固定 5/34）")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            // MA((H+L)/2, 5)
            let s5 = max(0, i - 5 + 1)
            var sum5: Decimal = 0
            for j in s5...i { sum5 += (bars[j].high + bars[j].low) / 2 }
            let ma5 = sum5 / Decimal(i - s5 + 1)
            // MA((H+L)/2, 34)
            let s34 = max(0, i - 34 + 1)
            var sum34: Decimal = 0
            for j in s34...i { sum34 += (bars[j].high + bars[j].low) / 2 }
            let ma34 = sum34 / Decimal(i - s34 + 1)
            result[i] = ma5 - ma34
        }
        return result
    }
}

// MARK: - 5. AC

/// AC — Acceleration / Deceleration (Bill Williams)
/// 公式：AC = AO - MA(AO, 5)
struct ACFunction: BuiltinFunction {
    let name = "AC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "AC不需要参数")
        }
        let count = bars.count
        // 先算 AO
        var ao = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s5 = max(0, i - 5 + 1)
            var sum5: Decimal = 0
            for j in s5...i { sum5 += (bars[j].high + bars[j].low) / 2 }
            let ma5 = sum5 / Decimal(i - s5 + 1)
            let s34 = max(0, i - 34 + 1)
            var sum34: Decimal = 0
            for j in s34...i { sum34 += (bars[j].high + bars[j].low) / 2 }
            let ma34 = sum34 / Decimal(i - s34 + 1)
            ao[i] = ma5 - ma34
        }
        // AC = AO - MA(AO, 5)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - 5 + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = ao[j] { sum += v; cnt += 1 }
            }
            guard cnt > 0, let aoVal = ao[i] else { continue }
            let maAO = sum / Decimal(cnt)
            result[i] = aoVal - maAO
        }
        return result
    }
}

// MARK: - 6. FRACTALH

/// FRACTALH — Bill Williams Fractal High
/// 5-bar 标准：H[i-2] > H[i-4], H[i-2] > H[i-3], H[i-2] > H[i-1], H[i-2] > H[i]
/// 满足时 result[i] = H[i-2] · 否则保持前值（最近一次确认的 fractal）
struct FRACTALHFunction: BuiltinFunction {
    let name = "FRACTALH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "FRACTALH不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastFractal: Decimal?
        for i in 4..<count {
            let center = bars[i - 2].high
            if center > bars[i - 4].high && center > bars[i - 3].high
                && center > bars[i - 1].high && center > bars[i].high {
                lastFractal = center
            }
            result[i] = lastFractal
        }
        return result
    }
}

// MARK: - 7. FRACTALL

/// FRACTALL — Bill Williams Fractal Low
/// 5-bar 标准：L[i-2] < L[i-4], L[i-2] < L[i-3], L[i-2] < L[i-1], L[i-2] < L[i]
struct FRACTALLFunction: BuiltinFunction {
    let name = "FRACTALL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "FRACTALL不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        var lastFractal: Decimal?
        for i in 4..<count {
            let center = bars[i - 2].low
            if center < bars[i - 4].low && center < bars[i - 3].low
                && center < bars[i - 1].low && center < bars[i].low {
                lastFractal = center
            }
            result[i] = lastFractal
        }
        return result
    }
}

// MARK: - 内部 ATR helper（与 batch3 ATRFunction 隔离 · 直接读 bars）

private enum MaiB12ATR {
    static func compute(bars: [BarData], period: Int) -> [Decimal?] {
        let count = bars.count
        // TR
        var tr = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let h = bars[i].high
            let l = bars[i].low
            if i == 0 {
                tr[i] = h - l
            } else {
                let prevC = bars[i - 1].close
                let hl = h - l
                let hPrevC = abs(h - prevC)
                let lPrevC = abs(l - prevC)
                tr[i] = max(max(hl, hPrevC), lPrevC)
            }
        }
        // ATR = SMA(TR, period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = tr[j] { sum += v; cnt += 1 }
            }
            if cnt > 0 {
                result[i] = sum / Decimal(cnt)
            }
        }
        return result
    }
}
