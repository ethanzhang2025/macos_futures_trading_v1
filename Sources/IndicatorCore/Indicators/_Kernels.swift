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

    /// N 周期内最高值 HHV
    static func hhv(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }
        for i in (n - 1)..<count {
            out[i] = xs[(i - n + 1)...i].max()
        }
        return out
    }

    /// N 周期内最低值 LLV
    static func llv(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }
        for i in (n - 1)..<count {
            out[i] = xs[(i - n + 1)...i].min()
        }
        return out
    }

    /// 加权移动平均 WMA：权重 1..N，近期权重大
    /// WMA(i) = Σ(x(i-N+k) * k) / Σk (k=1..N)
    static func wma(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }
        let weightSum = Decimal(n * (n + 1) / 2)
        for i in (n - 1)..<count {
            var sum: Decimal = 0
            for k in 1...n {
                sum += xs[i - n + k] * Decimal(k)
            }
            out[i] = round8(sum / weightSum)
        }
        return out
    }

    /// 基于 Int 成交量的累积运算辅助（OBV / PVT 等通用）
    static func cumulative(_ xs: [Decimal]) -> [Decimal] {
        var acc: Decimal = 0
        return xs.map { acc += $0; return acc }
    }

    /// 在上一层 EMA 的输出上继续做 EMA（nil → 0 过渡后再 EMA）
    /// 复用目的：DEMA/TEMA/TRIX 的 "EMA → map { $0 ?? 0 } → EMA" 重复模式
    static func nextEMA(_ prev: [Decimal?], period n: Int) -> [Decimal?] {
        ema(prev.map { $0 ?? 0 }, period: n)
    }

    /// N 周期滑动窗口求和；i < N-1 返回 nil（PSY 等纯加和场景复用）
    static func slidingSum(_ xs: [Decimal], period n: Int) -> [Decimal?] {
        let count = xs.count
        var out = [Decimal?](repeating: nil, count: count)
        guard n > 0, count >= n else { return out }
        for i in (n - 1)..<count {
            out[i] = xs[(i - n + 1)...i].reduce(Decimal(0), +)
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
