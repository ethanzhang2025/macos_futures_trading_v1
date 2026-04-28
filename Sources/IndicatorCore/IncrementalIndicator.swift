// WP-41 v2 · 指标增量计算协议
//
// 背景：
// - Indicator.calculate(kline:params:) 每次全量重算 O(N×M)（N=K线数 · M=指标列数）
// - 回放模式每根新 K 都全量重算成为热路径瓶颈
// - 增量推进：state + new bar → O(1) 或 O(window) per bar · 显著降低单帧成本
//
// 适用场景：回放模式 / 实时行情 KLineBuilder 流 / Alert evaluator 等热路径
// 算法不变：每步增量结果与对应 prefix 的 calculate() 末值精确一致（测试断言）
// 性能基准实测见 commit 3/4 的 demo
//
// commit 拆分：
// - commit 1/4（本次）：协议 + MA 增量（环形 buffer · O(1) per step）+ 测试
// - commit 2/4：EMA + RSI 增量（Wilder 平滑 · prev value O(1)）
// - commit 3/4：MACD + BOLL 增量（复合 / std 滑窗）+ 性能基准 demo
// - commit 4/4：ChartScene 接入（仅 .barEmitted 单调递增 case 用增量 · seek/rebuild 仍全量）

import Foundation
import Shared

/// 增量计算指标协议 · 继承 Indicator
///
/// 用法：
/// ```swift
/// var state = try MA.makeIncrementalState(kline: history, params: [20])
/// // ... 收到新 bar ...
/// let row = MA.stepIncremental(state: &state, newBar: bar)  // [Decimal?] · MA 1 列
/// ```
///
/// 不变量：
/// - history.count + step 调用次数 = 等价于全量 calculate(prefix) 的 K 线数
/// - history 的"末值"在 makeIncrementalState 中已计算并隐含在 state（如 MA sum）· 但 protocol 不强制返回
///   （用户已通过 calculate(kline: history, params:) 拿到 history 时段的全量 series）
/// - 后续 stepIncremental(state: &s, newBar: bars[history.count + i]) 返回的多列末值
///   等于 calculate(kline: history + bars[..i+1], params:) 末值
public protocol IncrementalIndicator: Indicator {
    /// 增量 state · 各指标定义自己的 sliding state（环形 buffer / prev value / EMA prev 等）
    associatedtype IncrementalState: Sendable

    /// 用全量历史 K 线初始化 state（一次 O(N) · 之后 step 是 O(1) 或 O(window)）
    /// - Note: history 不含将来要 step 的 newBar · history 末尾即"当前最新"
    static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState

    /// 推进 1 根 K 线 · 修改 state · 返回该根的多列指标末值
    /// - Returns: [Decimal?] · 数量与 calculate() 返回 [IndicatorSeries] count 一致 · nil 表示 warm-up 期未达
    static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?]
}
