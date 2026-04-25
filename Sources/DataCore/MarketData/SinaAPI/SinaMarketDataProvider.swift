// WP-31a · 新浪行情 Provider · 实现 MarketDataProvider 协议
//
// 设计取舍（与 WP-21a 哲学一致）：
// - actor 仅维护订阅集合 + 状态机；不持 Task / 不 sleep
// - 轮询节奏外置：caller 通过 pollOnce() 主动驱动；持续轮询用 SinaPollingDriver
// - 失败时上报 stateMachine.reportConnectionLost；caller 决定是否重连
// - SinaQuote → Tick 转换走 SinaQuoteToTick.convert（5 档盘口补 0）
// - 多合约一次 HTTP（fetchQuotes 批量）；按 instrumentID 精确分发
//
// 测试策略：注入 SinaQuoteFetching 协议 stub；无需打真网络
//
// Production 启动顺序：
//   let fetcher = SinaMarketData()
//   let provider = SinaMarketDataProvider(fetcher: fetcher)
//   await provider.connect()
//   await provider.subscribe("RB0") { tick in ... }
//   let driver = SinaPollingDriver(provider: provider, interval: 3.0)
//   await driver.start()

import Foundation
import Shared

/// 新浪行情 provider · 拉取式 → Tick 推送适配
public actor SinaMarketDataProvider: MarketDataProvider {

    public let stateMachine: ConnectionStateMachine

    private let fetcher: any SinaQuoteFetching
    private var handlers: [String: @Sendable (Tick) -> Void] = [:]

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

    public func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async {
        handlers[instrumentID] = handler
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

    /// 拉取一次所有已订阅合约的报价并分发
    /// - Parameter now: 注入时间（默认 Date()）；用于 Tick.tradingDay/updateTime
    /// - Returns: 实际分发到 handler 的 Tick 数（已解析失败的合约会被跳过）
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

        var dispatched = 0
        for quote in quotes {
            guard let handler = handlers[quote.symbol] else { continue }
            handler(SinaQuoteToTick.convert(quote, instrumentID: quote.symbol, now: now))
            dispatched += 1
        }
        return dispatched
    }

    // MARK: - 内省（测试 / 调试用）

    public func subscriberCount() -> Int { handlers.count }
    public func isSubscribed(_ instrumentID: String) -> Bool { handlers[instrumentID] != nil }
}
