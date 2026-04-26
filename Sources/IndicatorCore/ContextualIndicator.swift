// ContextualIndicator · 需要合约元数据 + 每日动态数据 + 每根 K 线时间戳的指标
//
// 区别于 Indicator：
// - Indicator: calculate(kline:, params:) · 仅依赖 KLineSeries（向量计算）
// - ContextualIndicator: calculate(kline:, barTimes:, context:, params:)
//   · 额外依赖 FuturesContext（合约规格 + 每日涨跌停/结算价 + 交易时段）
//   · 与每根 K 线对应的时间戳 barTimes
//
// 用例：B1 Step 2 的 4 个占位指标真实化
//   · LimitPriceLines        （涨跌停板线）
//   · DeliveryCountdown       （交割日倒计时）
//   · SettlementPriceLine     （结算价线）
//   · SessionDivider          （日盘/夜盘分界）
//
// 设计取舍：
// - barTimes 必填（明确 contract · 调用方负责提供 · KLineSeries 不带 date 字段）
// - 协议级 throws · 实现层用 IndicatorError.invalidParameter 抛长度不匹配等

import Foundation
import Shared
import DataCore

/// 需要合约元数据 + 每日动态数据 + 每根 K 线时间戳的指标协议
public protocol ContextualIndicator: Sendable {
    /// 指标标识（LIMIT / DELIVERY / SETTLE / SESSION 等）
    static var identifier: String { get }

    /// 指标分类
    static var category: IndicatorCategory { get }

    /// 参数定义
    static var parameters: [IndicatorParameter] { get }

    /// 计算指标
    /// - Parameters:
    ///   - kline: K 线序列
    ///   - barTimes: 每根 K 线对应的时间戳（长度需等于 kline.count）
    ///   - context: 期货合约 + 每日动态数据视图
    ///   - params: 指标参数（按 parameters 顺序）
    /// - Returns: 一条或多条时间序列，长度与 kline 对齐（无对应数据点为 nil）
    static func calculate(
        kline: KLineSeries,
        barTimes: [Date],
        context: FuturesContext,
        params: [Decimal]
    ) throws -> [IndicatorSeries]
}
