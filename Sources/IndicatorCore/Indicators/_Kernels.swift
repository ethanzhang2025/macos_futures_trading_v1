// WP-41 · 指标计算 kernel · internal 复用层
// 各 public Indicator 类型调用本层 kernel；kernel 与 Legacy FormulaEngine/BuiltinFunctions/*.swift 算法等价
// 未来优化方向：Legacy 底层函数 pure 化后可共用同一 kernel（见 Indicator.swift 顶部注释）

import Foundation

enum Kernels {
    /// Decimal 按 8 位精度 plain 模式 round（与 Legacy NSDecimalRound 一致）
    @inline(__always)
    static func round8(_ v: Decimal) -> Decimal {
        var input = v
        var out = Decimal()
        NSDecimalRound(&out, &input, 8, .plain)
        return out
    }

    /// 简单移动平均 MA（SMA）
    /// 公式：MA(i) = (X(i-N+1) + ... + X(i)) / N；i < N-1 返回 nil
    static func ma(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }

        let nDec = Decimal(n)
        for i in (n - 1)..<count {
            let window = xs[(i - n + 1)...i]
            let sum = window.reduce(Decimal(0), +)
            out[i] = round8(sum / nDec)
        }
        return out
    }

    /// 指数移动平均 EMA
    /// 公式：EMA(i) = 2/(N+1) * X(i) + (N-1)/(N+1) * EMA(i-1)；种子点 i = N-1 取前 N 根 SMA
    static func ema(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }

        let alpha = Decimal(2) / Decimal(n + 1)
        let oneMinusAlpha = Decimal(1) - alpha

        // 第 N-1 处以 SMA 为种子
        let seedSum = xs.prefix(n).reduce(Decimal(0), +)
        var prev = seedSum / Decimal(n)
        out[n - 1] = round8(prev)

        for i in n..<count {
            prev = alpha * xs[i] + oneMinusAlpha * prev
            out[i] = round8(prev)
        }
        return out
    }

    /// Wilder 平滑（RSI / ATR 用，α = 1/N 而非 2/(N+1)）
    /// 公式：Smooth(i) = (Smooth(i-1) * (N-1) + X(i)) / N；种子点 i = N-1 取前 N 根 SMA
    static func wilder(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }

        let nDec = Decimal(n)
        let nMinus1 = Decimal(n - 1)

        let seedSum = xs.prefix(n).reduce(Decimal(0), +)
        var prev = seedSum / nDec
        out[n - 1] = round8(prev)

        for i in n..<count {
            prev = (prev * nMinus1 + xs[i]) / nDec
            out[i] = round8(prev)
        }
        return out
    }

    /// N 周期样本标准差（总体标准差，分母 N；BOLL 约定）
    /// Decimal 精度不支持 sqrt，用 Double 过渡后转回 Decimal
    static func stddev(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }

        let nDec = Decimal(n)
        for i in (n - 1)..<count {
            let window = xs[(i - n + 1)...i]
            let mean = window.reduce(Decimal(0), +) / nDec
            let variance = window.reduce(Decimal(0)) { acc, x in
                let d = x - mean
                return acc + d * d
            } / nDec
            let sd = Decimal(NSDecimalNumber(decimal: variance).doubleValue.squareRoot())
            out[i] = round8(sd)
        }
        return out
    }
}
