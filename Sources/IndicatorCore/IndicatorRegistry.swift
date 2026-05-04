// WP-41 v15.18 · 指标注册表（集中元数据 · UI 自动列出可用指标）
//
// 设计取舍：
// - 单一权威来源 · UI / Settings / Picker 不需 hardcode 列表
// - 加新指标只需更新此处 · UI 自动呈现
// - 静态 list（编译期类型安全 · 不运行时反射）

import Foundation
import Shared

/// 指标元数据条目（不含 calculate · 仅用于 UI 列表）
public struct IndicatorEntry: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public let category: IndicatorCategory
    public let parameterCount: Int

    public init(identifier: String, displayName: String, category: IndicatorCategory, parameterCount: Int) {
        self.identifier = identifier
        self.displayName = displayName
        self.category = category
        self.parameterCount = parameterCount
    }
}

public enum IndicatorRegistry {

    /// 全部已注册指标（v15.18 末 60+ · 加新指标同步加 entry）
    public static let allEntries: [IndicatorEntry] = [
        // 趋势 trend
        .init(identifier: "MA",         displayName: "均线 MA",            category: .trend, parameterCount: 1),
        .init(identifier: "WMA",        displayName: "加权均线 WMA",        category: .trend, parameterCount: 1),
        .init(identifier: "DEMA",       displayName: "双指数均线 DEMA",     category: .trend, parameterCount: 1),
        .init(identifier: "TEMA",       displayName: "三指数均线 TEMA",     category: .trend, parameterCount: 1),
        .init(identifier: "HMA",        displayName: "Hull 均线 HMA",      category: .trend, parameterCount: 1),
        .init(identifier: "VWAP",       displayName: "成交量加权均价 VWAP", category: .trend, parameterCount: 0),
        .init(identifier: "SAR",        displayName: "抛物线转向 SAR",     category: .trend, parameterCount: 2),
        .init(identifier: "Supertrend", displayName: "超级趋势",            category: .trend, parameterCount: 2),
        .init(identifier: "ADX",        displayName: "平均趋向 ADX",       category: .trend, parameterCount: 1),
        .init(identifier: "AROON",      displayName: "Aroon 趋势强度",     category: .trend, parameterCount: 1),
        .init(identifier: "STC",        displayName: "Schaff Trend Cycle", category: .trend, parameterCount: 4),

        // 震荡 oscillator
        .init(identifier: "MACD",       displayName: "MACD",              category: .oscillator, parameterCount: 3),
        .init(identifier: "KDJ",        displayName: "KDJ",               category: .oscillator, parameterCount: 3),
        .init(identifier: "RSI",        displayName: "RSI",               category: .oscillator, parameterCount: 1),
        .init(identifier: "Stochastic", displayName: "Stochastic",        category: .oscillator, parameterCount: 2),
        .init(identifier: "CCI",        displayName: "CCI 顺势",           category: .oscillator, parameterCount: 1),
        .init(identifier: "WilliamsR",  displayName: "Williams %R",       category: .oscillator, parameterCount: 1),
        .init(identifier: "ROC",        displayName: "ROC 变动率",         category: .oscillator, parameterCount: 1),
        .init(identifier: "TRIX",       displayName: "TRIX",              category: .oscillator, parameterCount: 1),
        .init(identifier: "BIAS",       displayName: "BIAS 乖离率",        category: .oscillator, parameterCount: 1),
        .init(identifier: "PSY",        displayName: "PSY 心理线",         category: .oscillator, parameterCount: 1),
        .init(identifier: "DMI",        displayName: "DMI 趋向",           category: .oscillator, parameterCount: 1),
        .init(identifier: "CMO",        displayName: "Chande 动量",        category: .oscillator, parameterCount: 1),
        .init(identifier: "ELDER",      displayName: "Elder Ray 多空力量", category: .oscillator, parameterCount: 1),
        .init(identifier: "CHOPPINESS", displayName: "震荡度 CHOP",        category: .oscillator, parameterCount: 1),

        // 量价 volume
        .init(identifier: "Volume",     displayName: "成交量",             category: .volume, parameterCount: 0),
        .init(identifier: "OBV",        displayName: "OBV 累积量价",       category: .volume, parameterCount: 0),
        .init(identifier: "MFI",        displayName: "MFI 资金流",         category: .volume, parameterCount: 1),
        .init(identifier: "CMF",        displayName: "Chaikin 资金流",     category: .volume, parameterCount: 1),
        .init(identifier: "VR",         displayName: "VR 容量比率",        category: .volume, parameterCount: 1),
        .init(identifier: "PVT",        displayName: "PVT 价量趋势",       category: .volume, parameterCount: 0),
        .init(identifier: "ADL",        displayName: "ADL 累积/派发",      category: .volume, parameterCount: 0),
        .init(identifier: "VOSC",       displayName: "VOSC 量震荡",        category: .volume, parameterCount: 2),
        .init(identifier: "FI",         displayName: "ForceIndex 力量",   category: .volume, parameterCount: 1),

        // 波动率 / 通道 volatility
        .init(identifier: "BOLL",       displayName: "布林带 BOLL",        category: .volatility, parameterCount: 2),
        .init(identifier: "ATR",        displayName: "真实波幅 ATR",       category: .volatility, parameterCount: 1),
        .init(identifier: "ATRP",       displayName: "标准化 ATR%",        category: .volatility, parameterCount: 1),
        .init(identifier: "BBW",        displayName: "布林带宽 BBW",       category: .volatility, parameterCount: 2),
        .init(identifier: "KC",         displayName: "Keltner 通道",      category: .volatility, parameterCount: 2),
        .init(identifier: "Donchian",   displayName: "Donchian 通道",     category: .volatility, parameterCount: 1),
        .init(identifier: "StdDev",     displayName: "标准差 StdDev",     category: .volatility, parameterCount: 1),
        .init(identifier: "HV",         displayName: "历史波动率 HV",      category: .volatility, parameterCount: 1),
        .init(identifier: "PriceChannel", displayName: "价格通道",         category: .volatility, parameterCount: 1),
        .init(identifier: "Envelopes",  displayName: "包络线 Envelopes",  category: .volatility, parameterCount: 2),

        // 结构 structure
        .init(identifier: "PivotPoints", displayName: "枢轴点 Pivot",     category: .structure, parameterCount: 0),
        .init(identifier: "ZigZag",      displayName: "ZigZag",          category: .structure, parameterCount: 1),
        .init(identifier: "Ichimoku",    displayName: "Ichimoku 一目均衡", category: .structure, parameterCount: 3),
        .init(identifier: "Fractal",     displayName: "分形 Fractal",     category: .structure, parameterCount: 1),

        // 期货特有 futures
        .init(identifier: "OpenInterest",     displayName: "持仓量",         category: .futures, parameterCount: 0),
        .init(identifier: "DOI",              displayName: "持仓变化 ΔOI",  category: .futures, parameterCount: 0),
        .init(identifier: "LIMIT",            displayName: "涨跌停板线",     category: .futures, parameterCount: 0),
        .init(identifier: "DELIVERY",         displayName: "交割日倒计时",   category: .futures, parameterCount: 0),
        .init(identifier: "SETTLE",           displayName: "结算价线",       category: .futures, parameterCount: 0),
        .init(identifier: "SESSION",          displayName: "日盘/夜盘分界",  category: .futures, parameterCount: 0),
    ]

    /// 按分类分组（UI Picker 分组渲染用）
    public static func entriesByCategory() -> [IndicatorCategory: [IndicatorEntry]] {
        Dictionary(grouping: allEntries, by: \.category)
    }

    /// 按 identifier 查询单条
    public static func entry(for identifier: String) -> IndicatorEntry? {
        allEntries.first { $0.identifier == identifier }
    }

    /// 总数（debug / status 显示）
    public static var totalCount: Int { allEntries.count }
}
