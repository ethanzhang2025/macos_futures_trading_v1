// WP-31a · 新浪行情 Provider · 实现 MarketDataProvider 协议
// WP-44c · 同合约多 handler 字典：[instrumentID: [token: handler]]
//
// 设计取舍（与 WP-21a 哲学一致）：
// - actor 仅维护订阅集合 + 状态机；不持 Task / 不 sleep
// - 轮询节奏外置：caller 通过 pollOnce() 主动驱动；持续轮询用 SinaPollingDriver
// - 失败时上报 stateMachine.reportConnectionLost；caller 决定是否重连
// - SinaQuote → Tick 转换走 SinaQuoteToTick.convert（5 档盘口补 0）
// - 多合约一次 HTTP（fetchQuotes 批量）；按 instrumentID 精确分发到 bucket 内每个 handler
//
// 测试策略：注入 SinaQuoteFetching 协议 stub；无需打真网络
//
// Production 启动顺序：
//   let fetcher = SinaMarketData()
//   let provider = SinaMarketDataProvider(fetcher: fetcher)
//   await provider.connect()
//   let token = await provider.subscribe("RB0") { tick in ... }
//   let driver = SinaPollingDriver(provider: provider, interval: 3.0)
//   await driver.start()
//   // 退订时
//   await provider.unsubscribe("RB0", token: token)

import Foundation
import Shared

/// 新浪行情 provider · 拉取式 → Tick 推送适配
public actor SinaMarketDataProvider: MarketDataProvider {

    public let stateMachine: ConnectionStateMachine

    private let fetcher: any SinaQuoteFetching
    /// WP-44c · [instrumentID: [token: handler]]：同合约多订阅者
    private var handlers: [String: [SubscriptionToken: @Sendable (Tick) -> Void]] = [:]

    /// - Parameters:
    ///   - fetcher: 报价拉取实现（默认 SinaMarketData；测试可注入 stub）
    ///   - backoff: 重连退避策略
    public init(
        fetcher: any SinaQuoteFetching = SinaMarketData(),
        backoff: BackoffPolicy = ExponentialBackoff()
    ) {
        self.fetcher = fetcher
        self.stateMachine = ConnectionStateMachine(backoff: backoff)
    }

    // MARK: - MarketDataProvider 协议

    public func connectionState() async -> ConnectionState {
        await stateMachine.state
    }

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

    // MARK: - 连接生命周期

    /// 进入 connected 态（Sina 是无状态 HTTP，握手仅维护状态机语义）
    public func connect() async {
        await stateMachine.reportConnecting()
        await stateMachine.reportConnected()
    }

    /// 主动断开 + 清空所有订阅
    public func disconnect() async {
        handlers.removeAll()
        await stateMachine.reportDisconnected()
    }

    // MARK: - 轮询驱动（caller 控时）

    /// 拉取一次所有已订阅合约的报价并分发给 bucket 内每个 handler
    /// - Parameter now: 注入时间（默认 Date()）；用于 Tick.tradingDay/updateTime
    /// - Returns: 实际有 handler 收到 tick 的合约数（已解析失败的合约会被跳过）
    @discardableResult
    public func pollOnce(now: Date = Date()) async -> Int {
        guard !handlers.isEmpty else { return 0 }
        let symbols = Array(handlers.keys)

        let quotes: [SinaQuote]
        do {
            quotes = try await fetcher.fetchQuotes(symbols: symbols)
        } catch {
            await stateMachine.reportConnectionLost()
            return 0
        }

        var dispatchedSymbols = 0
        for quote in quotes {
            guard let bucket = handlers[quote.symbol], !bucket.isEmpty else { continue }
            let tick = SinaQuoteToTick.convert(quote, instrumentID: quote.symbol, now: now)
            for handler in bucket.values { handler(tick) }
            dispatchedSymbols += 1
        }
        return dispatchedSymbols
    }

    // MARK: - 内省（测试 / 调试用）

    /// 订阅的合约数（即 handlers 字典的 key 数量）
    public func subscriberCount() -> Int { handlers.count }
    /// 指定合约的 handler 数（WP-44c · 同合约多订阅者计数）
    public func handlerCount(for instrumentID: String) -> Int { handlers[instrumentID]?.count ?? 0 }
    public func isSubscribed(_ instrumentID: String) -> Bool { handlers[instrumentID]?.isEmpty == false }
}
