// WP-21a · 断线重连状态机
// 纯状态机设计：actor 只管状态转移 + 退避秒数计算，不持有 Task / 不主动 sleep
// caller（如 CTPSimNowMockProvider）根据 reportConnectionLost 返回的退避秒数 sleep 后再 reportConnecting
// 这种设计的好处：
// - 测试 100% 确定性（无时间依赖）
// - 状态机职责单一（不耦合具体连接动作）
// - 重启/取消语义清晰（caller 控 Task 生命周期）

import Foundation

/// 连接状态机 actor · 包装 ConnectionState 转移 + 自动 attempt 计数 + 退避秒数计算
///
/// 典型用法：
/// ```swift
/// let machine = ConnectionStateMachine(backoff: ExponentialBackoff())
/// await machine.reportConnecting()
/// // 实际尝试连接
/// if connected { await machine.reportConnected() }
/// else {
///     let delay = await machine.reportConnectionLost()
///     try await Task.sleep(...)  // caller 决定 sleep 实现
///     await machine.reportConnecting()  // 再次尝试
/// }
/// ```
public actor ConnectionStateMachine {

    // MARK: - 公开只读状态

    public private(set) var state: ConnectionState = .disconnected
    /// 累积重连次数（reportConnected / reportDisconnected 时归零）
    public private(set) var attemptCount: Int = 0

    // MARK: - 私有

    private let backoff: BackoffPolicy
    private var continuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    // MARK: - 初始化

    public init(backoff: BackoffPolicy = ExponentialBackoff()) {
        self.backoff = backoff
    }

    // MARK: - 状态订阅

    /// 订阅状态变化（含初始状态 yield 一次）；多订阅者支持
    /// stream 终止时会自动移除
    public func observe() -> AsyncStream<ConnectionState> {
        let id = UUID()
        let stream = AsyncStream<ConnectionState> { continuation in
            self.continuations[id] = continuation
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - 事件上报（外部驱动状态转移）

    /// 事件：进入连接中（首次连接 OR 重连后再次尝试）
    public func reportConnecting() {
        transition(to: .connecting)
    }

    /// 事件：连接成功（重置 attempt 计数）
    public func reportConnected() {
        attemptCount = 0
        transition(to: .connected)
    }

    /// 事件：主动断开（清空 attempt 计数）
    public func reportDisconnected() {
        attemptCount = 0
        transition(to: .disconnected)
    }

    /// 事件：连接丢失 → 进入 reconnecting(attempt: N) 状态
    /// - Returns: 在下一次 reportConnecting 前 caller 应等待的秒数（来自 BackoffPolicy）
    @discardableResult
    public func reportConnectionLost() -> TimeInterval {
        attemptCount += 1
        let delay = backoff.nextDelay(forAttempt: attemptCount)
        transition(to: .reconnecting(attempt: attemptCount))
        return delay
    }

    /// 事件：进入错误终态（不自动重连，需 caller 显式 reset）
    public func reportError(_ message: String) {
        attemptCount = 0
        transition(to: .error(message))
    }

    /// 重置到 disconnected 初始态（供 caller 在 error 后恢复）
    public func reset() {
        attemptCount = 0
        transition(to: .disconnected)
    }

    // MARK: - 私有：转移与广播

    private func transition(to newState: ConnectionState) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }
}
