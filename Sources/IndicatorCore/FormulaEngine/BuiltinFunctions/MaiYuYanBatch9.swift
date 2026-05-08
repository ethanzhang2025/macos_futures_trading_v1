// 麦语言扩展 · 第 9 批（v15.25 batch16 · ~99.97% → ~99.98% 兼容度）
//
// 7 个 trader 进阶函数（含经典 PSAR）：
//   1. PSAR()              — Parabolic SAR · trader 经典反转点（默认 AF 0.02-0.20）
//   2. PVI()               — Positive Volume Index · 普通投资者跟踪（与 NVI 互补）
//   3. ULTOSC(N1, N2, N3)  — Ultimate Oscillator · 三周期综合摆动
//   4. STOCHRSI(N)         — Stochastic RSI · 复合超买超卖
//   5. WAD()               — Williams Accumulation/Distribution · 累积量价
//   6. HD()                — High Diff · H[i] - H[i-1]（DMI 中间量）
//   7. LD()                — Low Diff · L[i-1] - L[i]（DMI 中间量）

import Foundation

// MARK: - 1. PSAR

/// PSAR — Parabolic SAR · Wells Wilder 经典反转点
/// 默认参数：AF 起步 0.02 · 步长 0.02 · 上限 0.20
/// 用法：PSAR() · 不带参数（标准默认值）
/// trader 用法：close 上穿 PSAR 入多 / 下穿 PSAR 入空
struct PSARFunction: BuiltinFunction {
    let name = "PSAR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "PSAR不需要参数（默认 AF 0.02-0.20）")
        }
        let count = bars.count
        guard count >= 2 else {
            return [Decimal?](repeating: nil, count: count)
        }

        var result = [Decimal?](repeating: nil, count: count)
        let afStart = Decimal(string: "0.02")!
        let afStep = Decimal(string: "0.02")!
        let afMax = Decimal(string: "0.20")!

        // 初始方向：用前两根 close 比较
        var isLong = bars[1].close >= bars[0].close
        var sar: Decimal = isLong ? bars[0].low : bars[0].high
        var ep: Decimal = isLong ? bars[0].high : bars[0].low
        var af: Decimal = afStart

        result[0] = sar

        for i in 1..<count {
            // 计算下一根 SAR（基于前根状态）
            sar = sar + af * (ep - sar)

            // 限制 SAR 不超过最近两根的 H/L（防止 SAR 错位）
            if isLong {
                let prevLow = bars[i - 1].low
                if sar > prevLow { sar = prevLow }
                if i >= 2 {
                    let prev2Low = bars[i - 2].low
                    if sar > prev2Low { sar = prev2Low }
                }
            } else {
                let prevHigh = bars[i - 1].high
                if sar < prevHigh { sar = prevHigh }
                if i >= 2 {
                    let prev2High = bars[i - 2].high
                    if sar < prev2High { sar = prev2High }
                }
            }

            // 趋势翻转条件
            if isLong && bars[i].low < sar {
                isLong = false
                sar = ep
                ep = bars[i].low
                af = afStart
            } else if !isLong && bars[i].high > sar {
                isLong = true
                sar = ep
                ep = bars[i].high
                af = afStart
            } else {
                // 同向延续 · 检查 EP 是否更新
                if isLong {
                    if bars[i].high > ep {
                        ep = bars[i].high
                        af = min(af + afStep, afMax)
                    }
                } else {
                    if bars[i].low < ep {
                        ep = bars[i].low
                        af = min(af + afStep, afMax)
                    }
                }
            }

            result[i] = sar
        }
        return result
    }
}

// MARK: - 2. PVI

/// PVI — Positive Volume Index 普通投资者指数（与 NVI 互补）
/// 公式：
///   PVI[0] = 1000
///   if V[i] > V[i-1]: PVI[i] = PVI[i-1] * (1 + (C[i]-C[i-1])/C[i-1])
///   else: PVI[i] = PVI[i-1]
/// 用途：放量时记录价格变化 · 反映普通投资者行为
struct PVIFunction: BuiltinFunction {
    let name = "PVI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "PVI不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }
        var pvi: Decimal = 1000
        result[0] = pvi
        for i in 1..<count {
            if bars[i].volume > bars[i - 1].volume {
                let prevC = bars[i - 1].close
                if prevC != 0 {
                    let chg = (bars[i].close - prevC) / prevC
                    pvi = pvi * (1 + chg)
                }
            }
            result[i] = pvi
        }
        return result
    }
}

// MARK: - 3. ULTOSC

/// ULTOSC — Ultimate Oscillator (Larry Williams)
/// 公式：
///   BP = CLOSE - MIN(LOW, REF(CLOSE,1))
///   TR = MAX(HIGH, REF(CLOSE,1)) - MIN(LOW, REF(CLOSE,1))
///   AvgN = SUM(BP, N) / SUM(TR, N)
///   ULTOSC = 100 * (4*AvgN1 + 2*AvgN2 + AvgN3) / 7
/// 默认 N1=7, N2=14, N3=28
/// 经验：> 70 超买 / < 30 超卖
struct ULTOSCFunction: BuiltinFunction {
    let name = "ULTOSC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "ULTOSC需要3个参数（N1, N2, N3）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V,
              let n3V = args[2].first, let n3 = n3V else {
            throw InterpreterError(message: "ULTOSC的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        let p3 = Int(truncating: n3 as NSDecimalNumber)
        guard p1 > 0, p2 > 0, p3 > 0 else {
            throw InterpreterError(message: "ULTOSC的周期必须为正整数")
        }

        let count = bars.count
        // BP / TR
        var bp = [Decimal?](repeating: nil, count: count)
        var tr = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prevC = bars[i - 1].close
            let trueLow = min(bars[i].low, prevC)
            let trueHigh = max(bars[i].high, prevC)
            bp[i] = bars[i].close - trueLow
            tr[i] = trueHigh - trueLow
        }

        func avgN(_ p: Int, at i: Int) -> Decimal? {
            let start = max(1, i - p + 1)
            var bpSum: Decimal = 0
            var trSum: Decimal = 0
            for j in start...i {
                guard let b = bp[j], let t = tr[j] else { continue }
                bpSum += b
                trSum += t
            }
            guard trSum > 0 else { return nil }
            return bpSum / trSum
        }

        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let a1 = avgN(p1, at: i),
                  let a2 = avgN(p2, at: i),
                  let a3 = avgN(p3, at: i) else { continue }
            result[i] = 100 * (4 * a1 + 2 * a2 + a3) / 7
        }
        return result
    }
}

// MARK: - 4. STOCHRSI

/// STOCHRSI — Stochastic RSI
/// 公式：
///   RSI = RSI(CLOSE, N)
///   STOCHRSI = (RSI - LLV(RSI, N)) / (HHV(RSI, N) - LLV(RSI, N)) * 100
/// 范围 [0, 100] · 经验：> 80 超买 / < 20 超卖
/// 注：本实现内部计算 RSI（Wilder 平滑 = SMMA）
struct STOCHRSIFunction: BuiltinFunction {
    let name = "STOCHRSI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "STOCHRSI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "STOCHRSI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "STOCHRSI的周期必须为正整数")
        }

        let count = bars.count
        // RSI
        var gain = [Decimal?](repeating: nil, count: count)
        var loss = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let diff = bars[i].close - bars[i - 1].close
            gain[i] = diff > 0 ? diff : 0
            loss[i] = diff < 0 ? -diff : 0
        }
        let avgGain = MaiB9Wilder.smooth(gain, period: period)
        let avgLoss = MaiB9Wilder.smooth(loss, period: period)
        var rsi = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let g = avgGain[i], let l = avgLoss[i] else { continue }
            if l == 0 {
                rsi[i] = 100
            } else {
                let rs = g / l
                rsi[i] = 100 - 100 / (1 + rs)
            }
        }

        // STOCHRSI = (RSI - LLV(RSI, N)) / (HHV(RSI, N) - LLV(RSI, N)) * 100
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi: Decimal?
            var lo: Decimal?
            for j in start...i {
                guard let v = rsi[j] else { continue }
                if hi == nil || v > hi! { hi = v }
                if lo == nil || v < lo! { lo = v }
            }
            guard let r = rsi[i], let h = hi, let l = lo else { continue }
            let span = h - l
            guard span > 0 else { continue }
            result[i] = (r - l) / span * 100
        }
        return result
    }
}

// MARK: - 5. WAD

/// WAD — Williams Accumulation/Distribution
/// 公式：
///   TRH = MAX(HIGH, REF(CLOSE,1))
///   TRL = MIN(LOW, REF(CLOSE,1))
///   if C > REF(C,1): pad = C - TRL
///   if C < REF(C,1): pad = C - TRH
///   else: pad = 0
///   WAD = 累计 pad
struct WADFunction: BuiltinFunction {
    let name = "WAD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "WAD不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return result }
        result[0] = 0
        var cum: Decimal = 0
        for i in 1..<count {
            let prevC = bars[i - 1].close
            let trh = max(bars[i].high, prevC)
            let trl = min(bars[i].low, prevC)
            var pad: Decimal = 0
            if bars[i].close > prevC {
                pad = bars[i].close - trl
            } else if bars[i].close < prevC {
                pad = bars[i].close - trh
            }
            cum += pad
            result[i] = cum
        }
        return result
    }
}

// MARK: - 6. HD

/// HD — High Diff = H[i] - H[i-1]
struct HDFunction: BuiltinFunction {
    let name = "HD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "HD不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = bars[i].high - bars[i - 1].high
        }
        return result
    }
}

// MARK: - 7. LD

/// LD — Low Diff = L[i-1] - L[i]
struct LDFunction: BuiltinFunction {
    let name = "LD"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "LD不需要参数")
        }
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            result[i] = bars[i - 1].low - bars[i].low
        }
        return result
    }
}

// MARK: - 内部 Wilder 平滑（与 batch4 隔离）

private enum MaiB9Wilder {
    static func smooth(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        let nDec = Decimal(period)
        let alpha = Decimal(1) / nDec
        let oneMinusAlpha = (nDec - 1) / nDec
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = prev! * oneMinusAlpha + v * alpha
            }
            result[i] = prev
        }
        return result
    }
}
