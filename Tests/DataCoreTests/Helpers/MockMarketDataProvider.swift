// 测试专用 Mock · 验证 MarketDataProvider 协议合约
// 未来 WP-51 K 线回放会做生产级 ReplayProvider（也实现 MarketDataProvider），本 Mock 仅供 Tests 使用

import Foundation
import Shared
@testable import DataCore

/// 测试 Mock：可手动推送 Tick 给订阅方，并观察连接状态转换
public actor MockMarketDataProvider: MarketDataProvider {
    private var handlers: [String: @Sendable (Tick) -> Void] = [:]
    private var state: ConnectionState = .disconnected

    public init() {}

    public func connectionState() async -> ConnectionState { state }

    public func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async {
        handlers[instrumentID] = handler
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

    /// 模拟推送 Tick（测试用）
    public func push(_ tick: Tick) {
        handlers[tick.instrumentID]?(tick)
    }

    /// 当前订阅数（测试校验用）
    public func subscriberCount() -> Int { handlers.count }
}
