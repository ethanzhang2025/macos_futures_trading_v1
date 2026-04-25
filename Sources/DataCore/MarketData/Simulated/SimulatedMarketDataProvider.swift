// WP-21a · 无真 CTP 库依赖的行情模拟实现
// 设计目的：
// - SwiftUI demo / 集成测试无需真 SimNow 账号即可跑通完整管线
// - 作为 WP-21b（Mac 真 CTP 桥接）的契约参考实现
// - 集成 ConnectionStateMachine 演示断线重连闭环
//
// 与 Tests/Helpers/MockMarketDataProvider 的区别：
// - 本类是 production code，不暴露 setState 直接改状态（必须走 connect/disconnect/simulate* API）
// - 集成 ConnectionStateMachine（attempt 计数 + 退避秒数 + AsyncStream 状态推送）
// - 多合约严格隔离（push 只走 instrumentID 精确匹配）
//
// 命名抉择：用 Simulated 而非 CTPSimNow —— 本类不实际接 CTP API，避免误导

import Foundation
import Shared

/// 无外部依赖的行情数据 provider 模拟实现
public actor SimulatedMarketDataProvider: MarketDataProvider {

    /// 暴露状态机供上层订阅状态变化（observe AsyncStream）或读取 attemptCount
    public let stateMachine: ConnectionStateMachine

    private var handlers: [String: @Sendable (Tick) -> Void] = [:]

    public init(backoff: BackoffPolicy = ExponentialBackoff()) {
        self.stateMachine = ConnectionStateMachine(backoff: backoff)
    }

    // MARK: - MarketDataProvider 协议

    public func connectionState() async -> ConnectionState {
        await stateMachine.state
    }

    public func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async {
        handlers[instrumentID] = handler
    }

    public func unsubscribe(_ instrumentID: String) async {
        handlers.removeValue(forKey: instrumentID)
    }

    public func unsubscribeAll() async {
        handlers.removeAll()
    }

    // MARK: - 连接生命周期（行为层模拟 CTP）

    /// 同步握手（瞬时进入 connecting → connected）
    /// 真 CTP 实现里这里要异步等服务器响应（参考 WP-21b CTPMarketDataProvider）
    public func connect() async {
        await stateMachine.reportConnecting()
        await stateMachine.reportConnected()
    }

    /// 主动断开 + 清空所有订阅
    public func disconnect() async {
        handlers.removeAll()
        await stateMachine.reportDisconnected()
    }

    // MARK: - 故障注入（仅用于测试 / demo · production CTP 实现里没有这些）

    /// 模拟连接丢失 → 进入 reconnecting(attempt: N)
    /// - Returns: 状态机给出的退避秒数（caller 应据此 sleep 后再 connect）
    @discardableResult
    public func simulateConnectionLost() async -> TimeInterval {
        await stateMachine.reportConnectionLost()
    }

    /// 模拟错误终态（不自动重连）
    public func simulateError(_ message: String) async {
        await stateMachine.reportError(message)
    }

    // MARK: - 数据注入

    /// 推送 Tick 到对应 instrumentID 的订阅 handler
    /// - Returns: 是否成功找到订阅者
    @discardableResult
    public func push(_ tick: Tick) -> Bool {
        guard let handler = handlers[tick.instrumentID] else { return false }
        handler(tick)
        return true
    }

    /// 批量推送（按合约精确分发，未订阅的 Tick 静默丢弃）
    /// - Returns: 实际推送成功的 Tick 数
    @discardableResult
    public func pushBatch(_ ticks: [Tick]) -> Int {
        ticks.reduce(0) { $0 + (push($1) ? 1 : 0) }
    }

    // MARK: - 内省（测试 / demo 用）

    public func subscriberCount() -> Int { handlers.count }
    public func isSubscribed(_ instrumentID: String) -> Bool { handlers[instrumentID] != nil }
}
