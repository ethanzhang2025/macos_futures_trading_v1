// 麦语言扩展 · 第 13 批（v15.25 batch20 · ~99.997% → ~99.999% 兼容度）
//
// 7 个补漏 + 进阶函数（含关键漏的 RSI）：
//   1. RSI(N)            — Relative Strength Index（基础必备 · 之前漏了）
//   2. STOCH(N)          — Stochastic %K (RSV) = (C-LLV)/(HHV-LLV)*100
//   3. VOLR(N)           — Volume Ratio = V / MA(V, N) * 100
//   4. VOSC(N1, N2)      — Volume Oscillator = (MA(V,N1)-MA(V,N2))/MA(V,N1)*100
//   5. DKX()             — DKX 多空线（中国市场）
//   6. HV(N)             — Historical Volatility · 年化 STD(LN收益)*sqrt(252)*100
//   7. ATRPCT(N)         — ATR / close * 100（百分比 ATR · 跨品种比较友好）

import Foundation

// MARK: - 1. RSI

/// RSI — Relative Strength Index (Wilder)
/// 公式：
///   gain = max(close - prev close, 0)
///   loss = max(prev close - close, 0)
///   avgGain = Wilder(gain, N) · avgLoss = Wilder(loss, N)
///   RS = avgGain / avgLoss
///   RSI = 100 - 100 / (1 + RS)
/// 经验：> 70 超买 / < 30 超卖
struct RSIFunction: BuiltinFunction {
    let name = "RSI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "RSI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "RSI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "RSI的周期必须为正整数")
        }

        let count = bars.count
        var gain = [Decimal?](repeating: nil, count: count)
        var loss = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let diff = bars[i].close - bars[i - 1].close
            gain[i] = diff > 0 ? diff : 0
            loss[i] = diff < 0 ? -diff : 0
        }
        let avgGain = MaiB13Wilder.smooth(gain, period: period)
        let avgLoss = MaiB13Wilder.smooth(loss, period: period)
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let g = avgGain[i], let l = avgLoss[i] else { continue }
            if l == 0 {
                result[i] = 100
            } else {
                let rs = g / l
                result[i] = 100 - 100 / (1 + rs)
            }
        }
        return result
    }
}

// MARK: - 2. STOCH

/// STOCH — Stochastic %K (RSV)
/// 公式：(CLOSE - LLV(LOW, N)) / (HHV(HIGH, N) - LLV(LOW, N)) * 100
/// 范围 [0, 100] · 与 WR 互补（WR 是反向）
struct STOCHFunction: BuiltinFunction {
    let name = "STOCH"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "STOCH需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "STOCH的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "STOCH的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var hi = bars[start].high
            var lo = bars[start].low
            for j in start...i {
                if bars[j].high > hi { hi = bars[j].high }
                if bars[j].low < lo { lo = bars[j].low }
            }
            let span = hi - lo
            guard span > 0 else { continue }
            result[i] = (bars[i].close - lo) / span * 100
        }
        return result
    }
}

// MARK: - 3. VOLR

/// VOLR — Volume Ratio
/// 公式：V / MA(V, N) * 100
/// 经验：> 200 巨量 / < 50 萎缩
struct VOLRFunction: BuiltinFunction {
    let name = "VOLR"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "VOLR需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "VOLR的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "VOLR的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            for j in start...i { sum += Decimal(bars[j].volume) }
            let ma = sum / Decimal(i - start + 1)
            guard ma > 0 else { continue }
            result[i] = Decimal(bars[i].volume) / ma * 100
        }
        return result
    }
}

// MARK: - 4. VOSC

/// VOSC — Volume Oscillator
/// 公式：(MA(V, N1) - MA(V, N2)) / MA(V, N1) * 100
/// 用途：短期量与长期量比 · 量能扩张/收缩
struct VOSCFunction: BuiltinFunction {
    let name = "VOSC"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 2 else {
            throw InterpreterError(message: "VOSC需要2个参数（短周期N1, 长周期N2）")
        }
        guard let n1V = args[0].first, let n1 = n1V,
              let n2V = args[1].first, let n2 = n2V else {
            throw InterpreterError(message: "VOSC的周期参数无效")
        }
        let p1 = Int(truncating: n1 as NSDecimalNumber)
        let p2 = Int(truncating: n2 as NSDecimalNumber)
        guard p1 > 0, p2 > 0 else {
            throw InterpreterError(message: "VOSC的周期必须为正整数")
        }

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let s1 = max(0, i - p1 + 1)
            let s2 = max(0, i - p2 + 1)
            var sum1: Decimal = 0
            var sum2: Decimal = 0
            for j in s1...i { sum1 += Decimal(bars[j].volume) }
            for j in s2...i { sum2 += Decimal(bars[j].volume) }
            let ma1 = sum1 / Decimal(i - s1 + 1)
            let ma2 = sum2 / Decimal(i - s2 + 1)
            guard ma1 > 0 else { continue }
            result[i] = (ma1 - ma2) / ma1 * 100
        }
        return result
    }
}

// MARK: - 5. DKX

/// DKX — 多空线（中国市场指标）
/// 公式：
///   MID = (3*CLOSE + HIGH + LOW + OPEN) / 6
///   DKX = (20*MID + 19*REF(MID,1) + ... + 1*REF(MID,19)) / 210
/// 用途：判定多空趋势 · 通常配合 MADKX = MA(DKX, 10) 使用
struct DKXFunction: BuiltinFunction {
    let name = "DKX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.isEmpty else {
            throw InterpreterError(message: "DKX不需要参数")
        }
        let count = bars.count
        // MID
        var mid = [Decimal](repeating: 0, count: count)
        for i in 0..<count {
            mid[i] = (3 * bars[i].close + bars[i].high + bars[i].low + bars[i].open) / 6
        }
        // DKX = sum(weight * MID) / 210 · weights: 20 → 1（共 20 项）
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            var sum: Decimal = 0
            for k in 0...min(19, i) {
                let weight = Decimal(20 - k)
                sum += weight * mid[i - k]
            }
            // 实际有效权重总和
            let kMax = min(19, i)
            var weightTotal: Decimal = 0
            for k in 0...kMax { weightTotal += Decimal(20 - k) }
            guard weightTotal > 0 else { continue }
            result[i] = sum / weightTotal
        }
        return result
    }
}

// MARK: - 6. HV

/// HV — Historical Volatility（年化）
/// 公式：
///   ret = LN(CLOSE / REF(CLOSE, 1))
///   HV = STD(ret, N) * SQRT(252) * 100
/// 用途：期权定价 / 风险评估 · 期货也用
/// 注：sqrt(252) ≈ 15.87 · 期货国内交易日约 240-250
struct HVFunction: BuiltinFunction {
    let name = "HV"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "HV需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "HV的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "HV的周期必须为正整数")
        }

        let count = bars.count
        // ret 序列
        var ret = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            let prev = bars[i - 1].close
            guard prev > 0 else { continue }
            let ratio = bars[i].close / prev
            let ratioD = NSDecimalNumber(decimal: ratio).doubleValue
            guard ratioD > 0 else { continue }
            ret[i] = Decimal(log(ratioD))
        }

        // STD(ret, N) * sqrt(252) * 100
        let annualFactor = Decimal(sqrt(252.0))
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(1, i - period + 1)
            guard start <= i else { continue }
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = ret[j] { sum += v; cnt += 1 }
            }
            guard cnt >= 2 else { continue }
            let mean = sum / Decimal(cnt)
            var sqSum: Decimal = 0
            for j in start...i {
                if let v = ret[j] { sqSum += (v - mean) * (v - mean) }
            }
            let variance = sqSum / Decimal(cnt)
            let varD = NSDecimalNumber(decimal: variance).doubleValue
            guard varD >= 0 else { continue }
            let std = Decimal(sqrt(varD))
            result[i] = std * annualFactor * 100
        }
        return result
    }
}

// MARK: - 7. ATRPCT

/// ATRPCT — ATR 百分比 = ATR(N) / CLOSE * 100
/// 用途：跨品种比较波动率 · 黄金 ATR 100 元 / 大豆 ATR 5 元 · 看 % 才公平
struct ATRPCTFunction: BuiltinFunction {
    let name = "ATRPCT"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ATRPCT需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ATRPCT的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ATRPCT的周期必须为正整数")
        }

        let count = bars.count
        // TR + ATR
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

        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - period + 1)
            var sum: Decimal = 0
            var cnt = 0
            for j in start...i {
                if let v = tr[j] { sum += v; cnt += 1 }
            }
            guard cnt > 0 else { continue }
            let atr = sum / Decimal(cnt)
            guard bars[i].close > 0 else { continue }
            result[i] = atr / bars[i].close * 100
        }
        return result
    }
}

// MARK: - 内部 Wilder smoothing（与 batch9 隔离）

private enum MaiB13Wilder {
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
