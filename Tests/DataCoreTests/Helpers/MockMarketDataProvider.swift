// 测试专用 Mock · 验证 MarketDataProvider 协议合约
// 未来 WP-51 K 线回放会做生产级 ReplayProvider（也实现 MarketDataProvider），本 Mock 仅供 Tests 使用

import Foundation
import Shared
@testable import DataCore

/// 测试 Mock：可手动推送 Tick 给订阅方，并观察连接状态转换
/// WP-44c · 同合约多 handler 字典，与生产 provider 行为一致
public actor MockMarketDataProvider: MarketDataProvider {
    private var handlers: [String: [SubscriptionToken: @Sendable (Tick) -> Void]] = [:]
    private var state: ConnectionState = .disconnected

    public init() {}

    public func connectionState() async -> ConnectionState { state }

    @discardableResult
    public func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async -> SubscriptionToken {
        let token = UUID()
        handlers[instrumentID, default: [:]][token] = handler
        return token
    }

    public func unsubscribe(_ instrumentID: String, token: SubscriptionToken) async {
        handlers[instrumentID]?.removeValue(forKey: token)
        if handlers[instrumentID]?.isEmpty == true {
            handlers.removeValue(forKey: instrumentID)
        }
    }

    public func unsubscribe(_ instrumentID: String) async {
        handlers.removeValue(forKey: instrumentID)
    }

    public func unsubscribeAll() async {
        handlers.removeAll()
    }

    // MARK: - 测试控制接口

    /// 变更连接状态（测试用）
    public func setState(_ newState: ConnectionState) {
        state = newState
    }

    /// 模拟推送 Tick（测试用，dispatch 给 bucket 内每个 handler）
    public func push(_ tick: Tick) {
        guard let bucket = handlers[tick.instrumentID] else { return }
        for handler in bucket.values { handler(tick) }
    }

    /// 当前订阅的合约数（测试校验用）
    public func subscriberCount() -> Int { handlers.count }
    /// 指定合约的 handler 数（测试校验用）
    public func handlerCount(for instrumentID: String) -> Int { handlers[instrumentID]?.count ?? 0 }
}
