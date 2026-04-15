import Foundation
import Shared

/// Tick分发器 — 接收Tick并分发给订阅者
public final class TickDispatcher: @unchecked Sendable {
    public typealias TickHandler = @Sendable (Tick) -> Void

    private var handlers: [String: [TickHandler]] = [:]  // instrumentID -> handlers
    private var globalHandlers: [TickHandler] = []
    private var latestTicks: [String: Tick] = [:]

    public init() {}

    /// 订阅指定合约的Tick
    public func subscribe(_ instrumentID: String, handler: @escaping TickHandler) {
        handlers[instrumentID, default: []].append(handler)
    }

    /// 订阅所有合约的Tick
    public func subscribeAll(handler: @escaping TickHandler) {
        globalHandlers.append(handler)
    }

    /// 分发Tick
    public func dispatch(_ tick: Tick) {
        latestTicks[tick.instrumentID] = tick

        if let specificHandlers = handlers[tick.instrumentID] {
            for handler in specificHandlers { handler(tick) }
        }
        for handler in globalHandlers { handler(tick) }
    }

    /// 获取指定合约的最新Tick
    public func latestTick(for instrumentID: String) -> Tick? {
        latestTicks[instrumentID]
    }

    /// 清除所有订阅
    public func removeAll() {
        handlers.removeAll()
        globalHandlers.removeAll()
    }
}
