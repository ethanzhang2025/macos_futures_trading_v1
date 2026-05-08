// 麦语言扩展 · 第 4 批（v15.25 batch11 · ~99% → ~99.5% 兼容度）
//
// 5 个 trader 实用边角函数（DMI 三件套 + TRIX + CORREL）：
//   1. PDI(N)         — Plus Directional Indicator (+DI) · DMI 趋势强度
//   2. MDI(N)         — Minus Directional Indicator (-DI) · DMI 配套
//   3. ADX(N)         — Average Directional Index · 趋势强度判定（>25 强趋势）
//   4. TRIX(N, M)     — 三重 EMA 平滑变化率 · 趋势识别 / 假突破过滤
//   5. CORREL(X, Y, N) — N 周期滚动相关系数 · 套利对冲 trader 用
//
// DMI 三件套用 Wilder smoothing（α=1/N · 等价 SMA(X,N,1)）
// CORREL 用 Decimal → Double sqrt 转换（与 SQRT/LOG 现有模式一致）

import Foundation

// MARK: - 1. PDI

/// PDI — Plus Directional Indicator（+DI）
/// 公式：
///   +DM(i) = if (H[i]-H[i-1]) > (L[i-1]-L[i]) and (H[i]-H[i-1]) > 0 then H[i]-H[i-1] else 0
///   TR(i)  = max(H-L, |H-prevC|, |L-prevC|)
///   +DM_smooth = Wilder(+DM, N) / TR_smooth = Wilder(TR, N)
///   +DI = 100 * +DM_smooth / TR_smooth
/// 用法：PDI(14) · trader 标准 N=14
struct PDIFunction: BuiltinFunction {
    let name = "PDI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "PDI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "PDI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "PDI的周期必须为正整数")
        }

        let (plusDISmooth, _, trSmooth) = DMIComputer.smoothed(bars: bars, period: period)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let plus = plusDISmooth[i], let tr = trSmooth[i], tr > 0 else { continue }
            result[i] = 100 * plus / tr
        }
        return result
    }
}

// MARK: - 2. MDI

/// MDI — Minus Directional Indicator（-DI）
/// 公式：
///   -DM(i) = if (L[i-1]-L[i]) > (H[i]-H[i-1]) and (L[i-1]-L[i]) > 0 then L[i-1]-L[i] else 0
///   -DI = 100 * -DM_smooth / TR_smooth
struct MDIFunction: BuiltinFunction {
    let name = "MDI"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "MDI需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "MDI的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "MDI的周期必须为正整数")
        }

        let (_, minusDISmooth, trSmooth) = DMIComputer.smoothed(bars: bars, period: period)
        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let minus = minusDISmooth[i], let tr = trSmooth[i], tr > 0 else { continue }
            result[i] = 100 * minus / tr
        }
        return result
    }
}

// MARK: - 3. ADX

/// ADX — Average Directional Index
/// 公式：
///   DX(i) = 100 * |+DI - -DI| / (+DI + -DI)
///   ADX = Wilder(DX, N)
/// 经验阈值：> 25 强趋势 / < 20 震荡
struct ADXFunction: BuiltinFunction {
    let name = "ADX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 else {
            throw InterpreterError(message: "ADX需要1个参数（周期N）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "ADX的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "ADX的周期必须为正整数")
        }

        let count = bars.count
        let (plusDISmooth, minusDISmooth, trSmooth) = DMIComputer.smoothed(bars: bars, period: period)

        // DX 序列
        var dx = [Decimal?](repeating: nil, count: count)
        for i in 0..<count {
            guard let p = plusDISmooth[i], let m = minusDISmooth[i], let tr = trSmooth[i], tr > 0 else { continue }
            let pdi = 100 * p / tr
            let mdi = 100 * m / tr
            let sum = pdi + mdi
            guard sum > 0 else { continue }
            dx[i] = 100 * abs(pdi - mdi) / sum
        }

        // ADX = Wilder(DX, N)
        return WilderSmoother.smooth(dx, period: period)
    }
}

// MARK: - 4. TRIX

/// TRIX — 三重 EMA 平滑变化率
/// 公式：
///   EMA1 = EMA(CLOSE, N)
///   EMA2 = EMA(EMA1, N)
///   EMA3 = EMA(EMA2, N)
///   TRIX = (EMA3[i] - EMA3[i-1]) / EMA3[i-1] * 100
///   MTRIX = MA(TRIX, M)（信号线 · 第二参数）
/// 用法：TRIX(12, 9) · 返回 TRIX（不返 MTRIX · trader 自己 MA(TRIX(...), M)）
struct TRIXFunction: BuiltinFunction {
    let name = "TRIX"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 1 || args.count == 2 else {
            throw InterpreterError(message: "TRIX需要1或2个参数（N · 可选 M 信号线 · 仅返 TRIX 不返 MTRIX）")
        }
        guard let nVal = args[0].first, let n = nVal else {
            throw InterpreterError(message: "TRIX的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "TRIX的周期必须为正整数")
        }

        // 取 close 序列
        let close = bars.map { Optional($0.close) }
        let ema1 = EMASmoother.ema(close, period: period)
        let ema2 = EMASmoother.ema(ema1, period: period)
        let ema3 = EMASmoother.ema(ema2, period: period)

        let count = bars.count
        var result = [Decimal?](repeating: nil, count: count)
        for i in 1..<count {
            guard let curr = ema3[i], let prev = ema3[i - 1], prev != 0 else { continue }
            result[i] = (curr - prev) / prev * 100
        }
        return result
    }
}

// MARK: - 5. CORREL

/// CORREL — N 周期滚动相关系数
/// 公式：
///   mean_x = SMA(X, N) · mean_y = SMA(Y, N)
///   cov = SMA((X - mean_x) * (Y - mean_y), N)
///   std_x = sqrt(SMA((X - mean_x)^2, N))
///   std_y = sqrt(SMA((Y - mean_y)^2, N))
///   correl = cov / (std_x * std_y) ∈ [-1, 1]
/// 用法：CORREL(CLOSE, REF(CLOSE,1), 20) · trader 套利配对相关度
struct CORRELFunction: BuiltinFunction {
    let name = "CORREL"

    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?] {
        guard args.count == 3 else {
            throw InterpreterError(message: "CORREL需要3个参数（X, Y, N）")
        }
        let x = args[0]
        let y = args[1]
        guard let nVal = args[2].first, let n = nVal else {
            throw InterpreterError(message: "CORREL的周期参数无效")
        }
        let period = Int(truncating: n as NSDecimalNumber)
        guard period > 0 else {
            throw InterpreterError(message: "CORREL的周期必须为正整数")
        }
        guard x.count == y.count else {
            throw InterpreterError(message: "CORREL的X和Y长度必须一致")
        }

        let count = x.count
        var result = [Decimal?](repeating: nil, count: count)

        for i in 0..<count {
            let start = max(0, i - period + 1)
            // 收集窗口内成对非 nil 值
            var xs: [Decimal] = []
            var ys: [Decimal] = []
            for j in start...i {
                guard let xv = x[j], let yv = y[j] else { continue }
                xs.append(xv)
                ys.append(yv)
            }
            guard xs.count >= 2 else { continue }

            let nDec = Decimal(xs.count)
            let meanX = xs.reduce(Decimal(0), +) / nDec
            let meanY = ys.reduce(Decimal(0), +) / nDec

            var cov: Decimal = 0
            var varX: Decimal = 0
            var varY: Decimal = 0
            for k in 0..<xs.count {
                let dx = xs[k] - meanX
                let dy = ys[k] - meanY
                cov += dx * dy
                varX += dx * dx
                varY += dy * dy
            }
            cov /= nDec
            varX /= nDec
            varY /= nDec

            // sqrt 用 Double 中转（与 SQRT 现有模式一致）
            let stdX = Decimal(sqrt(NSDecimalNumber(decimal: varX).doubleValue))
            let stdY = Decimal(sqrt(NSDecimalNumber(decimal: varY).doubleValue))
            let denom = stdX * stdY
            guard denom > 0 else { continue }
            result[i] = cov / denom
        }
        return result
    }
}

// MARK: - 内部计算辅助

/// Wilder 平滑（等价 SMA(X, N, 1) · α=1/N）
/// smoothed[i] = smoothed[i-1] * (N-1)/N + value[i] / N
/// 第一根有效值 seed = 该值
private enum WilderSmoother {
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

private enum EMASmoother {
    static func ema(_ src: [Decimal?], period: Int) -> [Decimal?] {
        let count = src.count
        var result = [Decimal?](repeating: nil, count: count)
        guard period > 0, count > 0 else { return result }
        let multiplier = Decimal(2) / Decimal(period + 1)
        var prev: Decimal?
        for i in 0..<count {
            guard let v = src[i] else { continue }
            if prev == nil {
                prev = v
            } else {
                prev = multiplier * v + (1 - multiplier) * prev!
            }
            result[i] = prev
        }
        return result
    }
}

/// DMI 共享计算 · 一次性算 +DM_smooth / -DM_smooth / TR_smooth
/// 三个指标（PDI/MDI/ADX）共享此核心 · 避免重复算 +DM 和 -DM
private enum DMIComputer {

    static func smoothed(bars: [BarData], period: Int) -> (
        plusDISmooth: [Decimal?],
        minusDISmooth: [Decimal?],
        trSmooth: [Decimal?]
    ) {
        let count = bars.count
        var plusDM = [Decimal?](repeating: nil, count: count)
        var minusDM = [Decimal?](repeating: nil, count: count)
        var tr = [Decimal?](repeating: nil, count: count)

        for i in 0..<count {
            let h = bars[i].high
            let l = bars[i].low
            if i == 0 {
                plusDM[i] = 0
                minusDM[i] = 0
                tr[i] = h - l
            } else {
                let prevH = bars[i - 1].high
                let prevL = bars[i - 1].low
                let prevC = bars[i - 1].close
                let upMove = h - prevH
                let downMove = prevL - l
                plusDM[i] = (upMove > downMove && upMove > 0) ? upMove : 0
                minusDM[i] = (downMove > upMove && downMove > 0) ? downMove : 0
                let hl = h - l
                let hPrevC = abs(h - prevC)
                let lPrevC = abs(l - prevC)
                tr[i] = max(max(hl, hPrevC), lPrevC)
            }
        }

        let plusSmooth = WilderSmoother.smooth(plusDM, period: period)
        let minusSmooth = WilderSmoother.smooth(minusDM, period: period)
        let trSmoothed = WilderSmoother.smooth(tr, period: period)
        return (plusSmooth, minusSmooth, trSmoothed)
    }
}
