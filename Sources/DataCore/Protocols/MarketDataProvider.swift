// MarketDataProvider · 实时行情推送 provider 协议
// WP-31 抽象 · 为 WP-21 CTP SimNow PoC、WP-51 K 线回放、WP-52 条件预警 提供统一订阅模型
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

/// 实时行情推送 provider
///
/// 典型使用：
/// ```swift
/// let provider: MarketDataProvider = ...
/// await provider.subscribe("rb2505") { tick in
///     // 处理 tick
/// }
/// ```
///
/// 线程契约：所有方法并发安全；handler 回调并发安全（@Sendable）。
public protocol MarketDataProvider: Sendable {
    /// 获取当前连接状态
    func connectionState() async -> ConnectionState

    /// 订阅指定合约的 Tick 推送
    /// - Parameters:
    ///   - instrumentID: 合约 ID（如 "rb2505"）
    ///   - handler: Tick 到达回调；并发安全
    func subscribe(_ instrumentID: String, handler: @escaping @Sendable (Tick) -> Void) async

    /// 取消指定合约的订阅
    func unsubscribe(_ instrumentID: String) async

    /// 清空全部订阅
    func unsubscribeAll() async
}
