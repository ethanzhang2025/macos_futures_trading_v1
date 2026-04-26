// MarketDataProvider · 实时行情推送 provider 协议
// WP-31 抽象 · 为 WP-21 CTP SimNow PoC、WP-51 K 线回放、WP-52 条件预警 提供统一订阅模型
// WP-44c · 同合约多 handler：subscribe 返回 SubscriptionToken；unsubscribe(_:token:) 精确退订
// 实现方（按计划）：CTPMarketDataProvider（WP-220 Stage B）/ SimNowMarketDataProvider（WP-21）/ MockMarketDataProvider（Tests 用）
// 非目标：REST 轮询式数据源（那是 HistoricalKLineProvider，见同目录）

import Foundation
import Shared

/// 连接状态，供 UI 显示状态灯 / 断线重连策略使用
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)  // 指数退避第 N 次
    case error(String)
}

/// 订阅句柄 · WP-44c 起 caller 用此 token 精确退订自己的 handler，不影响同合约其他订阅者
public typealias SubscriptionToken = UUID

/// 实时行情推送 provider
///
/// 典型使用：
/// ```swift
/// let provider: MarketDataProvider = ...
/// let token = await provider.subscribe("rb2505") { tick in
///     // 处理 tick
/// }
/// // 不再需要时
/// await provider.unsubscribe("rb2505", token: token)
/// ```
///
/// 线程契约：所有方法并发安全；handler 回调并发安全（@Sendable）。
public protocol MarketDataProvider: Sendable {
    /// 获取当前连接状态
    func connectionState() async -> ConnectionState

    /// 订阅指定合约的 Tick 推送（WP-44c 起支持同合约多 handler）
    /// - Parameters:
    ///   - instrumentID: 合约 ID（如 "rb2505"）
    ///   - handler: Tick 到达回调；并发安全
    /// - Returns: 订阅句柄（caller 用它精确退订自己的 handler）
    @discardableResult
    func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async -> SubscriptionToken

    /// 精确退订单个 handler（不影响同合约其他订阅者）
    func unsubscribe(_ instrumentID: String, token: SubscriptionToken) async

    /// 清空指定合约的所有 handler（disconnect / 强制重置场景）
    func unsubscribe(_ instrumentID: String) async

    /// 清空全部订阅
    func unsubscribeAll() async
}
