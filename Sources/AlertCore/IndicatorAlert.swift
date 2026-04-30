// WP-52 v15.x · 指标条件预警数据模型
// AlertCondition.indicator(spec) 走这套结构 · evaluator 通过 K 线序列计算指标 + 判断 cross
//
// 设计要点：
// - IndicatorKind 仅 4 类（MA/EMA/MACD/RSI）· 覆盖 90%+ 实战场景 · 后续按需扩展
// - IndicatorEvent 6 种事件 · 全部是"上一根 vs 当前根"的 cross 语义 · 不做 above/below 静态条件（重复触发问题用 cross 解决）
// - period 字段：每条预警绑定固定周期 · 5m 建的预警必须用 5m K 线评估 · 不会跟 ChartScene 切周期漂移

import Foundation
import Shared

/// 指标条件预警的完整描述
public struct IndicatorAlertSpec: Sendable, Codable, Equatable, Hashable {
    /// 哪种指标（MA/EMA/MACD/RSI）
    public var indicator: IndicatorKind
    /// 指标参数（MA: [period] / MACD: [fast, slow, signal] / RSI: [period]）
    public var params: [Decimal]
    /// 触发事件
    public var event: IndicatorEvent
    /// 评估周期（哪个周期 K 线满足才触发）
    public var period: KLinePeriod

    public init(indicator: IndicatorKind, params: [Decimal], event: IndicatorEvent, period: KLinePeriod) {
        self.indicator = indicator
        self.params = params
        self.event = event
        self.period = period
    }

    /// 用户可读描述（UI 显示用）
    public var displayDescription: String {
        let paramText = params.map { "\($0)" }.joined(separator: ",")
        return "\(indicator.displayName)(\(paramText)) \(event.displayDescription) · \(period.displayName)"
    }
}

/// 指标种类
public enum IndicatorKind: String, Sendable, Codable, CaseIterable {
    case ma     // 简单移动平均
    case ema    // 指数移动平均
    case macd   // MACD
    case rsi    // RSI

    public var displayName: String {
        switch self {
        case .ma:   return "MA 均线"
        case .ema:  return "EMA 均线"
        case .macd: return "MACD"
        case .rsi:  return "RSI"
        }
    }

    /// 默认参数（创建预警时填入表单的默认值）
    public var defaultParams: [Decimal] {
        switch self {
        case .ma:   return [20]
        case .ema:  return [12]
        case .macd: return [12, 26, 9]
        case .rsi:  return [14]
        }
    }

    /// 该指标支持的事件列表（UI 表单用）
    public var supportedEvents: [IndicatorEvent] {
        switch self {
        case .ma, .ema:
            return [.priceCrossAboveLine, .priceCrossBelowLine]
        case .macd:
            return [.macdGoldenCross, .macdDeathCross]
        case .rsi:
            return [.rsiCrossAbove(70), .rsiCrossBelow(30)]
        }
    }
}

/// 触发事件 · 全部是 cross 语义（上一根 vs 当前根）
public enum IndicatorEvent: Sendable, Codable, Equatable, Hashable {
    /// MA/EMA · 收盘价上穿单线（prevClose < line(prev) ∧ close >= line(current)）
    case priceCrossAboveLine
    /// MA/EMA · 收盘价下穿单线
    case priceCrossBelowLine
    /// MACD · DIF 上穿 DEA（prevDIF < prevDEA ∧ DIF >= DEA）
    case macdGoldenCross
    /// MACD · DIF 下穿 DEA
    case macdDeathCross
    /// RSI · 上穿阈值（默认 70 超买边界）
    case rsiCrossAbove(Decimal)
    /// RSI · 下穿阈值（默认 30 超卖边界）
    case rsiCrossBelow(Decimal)

    public var displayDescription: String {
        switch self {
        case .priceCrossAboveLine: return "价格上穿"
        case .priceCrossBelowLine: return "价格下穿"
        case .macdGoldenCross:     return "金叉（DIF 上穿 DEA）"
        case .macdDeathCross:      return "死叉（DIF 下穿 DEA）"
        case .rsiCrossAbove(let t): return "上穿 \(t)"
        case .rsiCrossBelow(let t): return "下穿 \(t)"
        }
    }
}
