// WP-21a · 断线重连退避策略
// 提供 BackoffPolicy 协议 + ExponentialBackoff 默认实现（指数退避 + cap + jitter）
// 设计原则：
// - 时间用 TimeInterval（Double 秒）保持跨平台稳定（Swift Duration 在某些 Linux 版本仍不稳）
// - RNG 用 () -> Double 闭包注入（Sendable 友好；RandomNumberGenerator 协议 mutating next() 不便于跨 actor）
// - 纯 value type · 无副作用 · 可单测

import Foundation

/// 断线重连退避策略协议
public protocol BackoffPolicy: Sendable {
    /// 计算第 attempt 次重连前的等待时长
    /// - Parameter attempt: 第几次重连（从 1 开始；0 表示首次连接，返回 0）
    /// - Returns: 等待秒数；保证 >= 0
    func nextDelay(forAttempt attempt: Int) -> TimeInterval
}

/// 指数退避 · base * factor^(attempt-1)，cap 在 maxDelay，叠加 ±jitterRatio 抖动
public struct ExponentialBackoff: BackoffPolicy {
    public let baseDelay: TimeInterval
    public let factor: Double
    public let maxDelay: TimeInterval
    /// jitter 比例（0..1）；0 = 无抖动，0.2 = ±20%
    public let jitterRatio: Double
    /// 随机数源（产出 [0, 1)）。注入便于测试可重现
    private let rng: @Sendable () -> Double

    public init(
        baseDelay: TimeInterval = 1.0,
        factor: Double = 2.0,
        maxDelay: TimeInterval = 60.0,
        jitterRatio: Double = 0.2,
        rng: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        precondition(baseDelay >= 0, "baseDelay 必须 >= 0")
        precondition(factor >= 1, "factor 必须 >= 1（否则退避变递减）")
        precondition(maxDelay >= baseDelay, "maxDelay 必须 >= baseDelay")
        precondition(jitterRatio >= 0 && jitterRatio < 1, "jitterRatio 应在 [0, 1)")
        self.baseDelay = baseDelay
        self.factor = factor
        self.maxDelay = maxDelay
        self.jitterRatio = jitterRatio
        self.rng = rng
    }

    public func nextDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponent = Double(attempt - 1)
        let raw = baseDelay * pow(factor, exponent)
        let capped = min(raw, maxDelay)
        // jitter 范围：[-jitterRatio, +jitterRatio) · rng()*2-1 把 [0,1) 映射到 [-1, 1)
        let jitter = capped * jitterRatio * (rng() * 2 - 1)
        return max(0, capped + jitter)
    }
}

/// 无退避（每次重连立刻执行；测试或特殊场景用）
public struct NoBackoff: BackoffPolicy {
    public init() {}
    public func nextDelay(forAttempt attempt: Int) -> TimeInterval { 0 }
}
