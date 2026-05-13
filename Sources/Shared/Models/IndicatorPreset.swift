// v17.154 · 一键指标套装（trader 快速切换不同流派的指标组合）
//
// 应用 preset 时一次性 push 到三个 source：
//   - selectedSubIndicators（Set<SubIndicatorKind>）→ 副图开启集合
//   - overlayBook.enabled（Set<MainChartOverlayKind>）→ 主图叠加开启集合
//   - 不动 IndicatorParamsBook（参数沿用用户调好的偏好 · preset 只切"开哪些"不动"参数值"）
//
// 设计取舍（Karpathy "最少惊讶"）：
// - preset 是 push（覆盖）非 merge · 让 trader 心智清晰（点 "国际派" 就回到该套装）
// - 用 SubIndicatorKind / MainChartOverlayKind 的 rawValue 字符串引用 · 避免 Shared 引入 MainApp 类型
// - SubIndicatorKind 在 MainApp · 这里只暴露 rawValue · 调用方负责映射

import Foundation

/// 指标套装枚举
public enum IndicatorPreset: String, CaseIterable, Sendable, Identifiable {
    case classic       // 经典国内派（MACD + KDJ + RSI + Volume · 中国 trader 习惯）
    case international // 国际派（Ichimoku + MFI + ADX + CMF · 全球技术分析协会标准）
    case priceVolume   // 价量派（VWAP + OBV + PVT + CMF · 资金流核心）
    case turtle        // 海龟交易法（Donchian Channel + ATR % · 经典趋势突破）
    case scalper       // 短线日内（VWAP + Pivot + SuperTrend + Stoch + ROC）
    case minimal       // 裸 K（全关 · 干净画面 · 看 K 线本身）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic:       return "🇨🇳 经典国内派"
        case .international: return "🌐 国际派"
        case .priceVolume:   return "💰 价量派"
        case .turtle:        return "🐢 海龟法"
        case .scalper:       return "⚡ 短线日内"
        case .minimal:       return "🕊 裸 K（全关）"
        }
    }

    public var subtitle: String {
        switch self {
        case .classic:       return "MACD + KDJ + RSI + 成交量 · 中国 trader 入门标配"
        case .international: return "Ichimoku + MFI + ADX + CMF · 全球技术分析协会标准"
        case .priceVolume:   return "VWAP + OBV + PVT + CMF · 资金流分析核心"
        case .turtle:        return "Donchian + ATR% · 海龟交易法趋势突破经典"
        case .scalper:       return "VWAP + Pivot + SuperTrend + Stoch + ROC · 短线日内"
        case .minimal:       return "全部关闭 · 看 K 线本身 · 裸 K 派 / 价格行为派"
        }
    }

    /// 副图集合（SubIndicatorKind.rawValue）
    public var subIndicatorRaws: [String] {
        switch self {
        case .classic:       return ["macd", "kdj", "rsi", "volume"]
        case .international: return ["mfi", "adx", "cmf", "atrp"]
        case .priceVolume:   return ["obv", "pvt", "cmf", "volume"]
        case .turtle:        return ["atrp", "bbw"]
        case .scalper:       return ["stoch", "roc", "volume"]
        case .minimal:       return []
        }
    }

    /// 主图 overlay 集合（MainChartOverlayKind.rawValue）
    public var overlayRaws: [String] {
        switch self {
        case .classic:       return []                                          // 国内派习惯只看 MA/BOLL（已默认开 · 不在 overlay）
        case .international: return ["ichimoku"]
        case .priceVolume:   return ["vwap"]
        case .turtle:        return ["donchian"]
        case .scalper:       return ["vwap", "pivot", "superTrend"]
        case .minimal:       return []
        }
    }
}
