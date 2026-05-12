// MainApp · v17.92 · 图表偏好（K 线配色 + 价格精度）
//
// 与既有持久化分工：
// - IndicatorParamsBook（Shared）= 指标默认参数（MA/MACD/KDJ/RSI/BOLL 等 19 类）
// - ChartTheme（MainApp/ChartTheme.swift）= dark/light 配色主题（line/tooltip/band）
// - ChartSettingsStore（本文件）= K 线涨跌配色方向 + 价格精度位数
//
// Stage A 重点：Settings 偏好"可调"且持久化 · ChartScene 接通分多次迭代
// 用 enum + rawValue 持久化 · UserDefaults 兼容字符串 / Int 直存

import Foundation

/// K 线涨跌配色方向（独立于 dark/light 主题）
public enum CandleColorMode: String, CaseIterable, Sendable {
    /// 中国习惯：涨红 / 跌绿（默认）
    case redUpGreenDown
    /// 国际习惯（TradingView 默认）：涨绿 / 跌红
    case greenUpRedDown

    public var displayName: String {
        switch self {
        case .redUpGreenDown: return "涨红跌绿（中国习惯）"
        case .greenUpRedDown: return "涨绿跌红（国际习惯）"
        }
    }
}

/// 价格精度（小数位数）· auto = 跟随合约约定
public enum PricePrecisionMode: String, CaseIterable, Sendable {
    case auto      // 跟随合约（StepSize 推算）
    case fixed2
    case fixed3
    case fixed4

    public var displayName: String {
        switch self {
        case .auto:   return "自动（跟随合约）"
        case .fixed2: return "固定 2 位"
        case .fixed3: return "固定 3 位"
        case .fixed4: return "固定 4 位"
        }
    }

    /// 实际位数（auto 时返回 nil · 由调用方按合约决定）
    public var digits: Int? {
        switch self {
        case .auto:   return nil
        case .fixed2: return 2
        case .fixed3: return 3
        case .fixed4: return 4
        }
    }
}

public enum ChartSettingsStore {

    // MARK: - Keys

    static let candleColorKey = "chart.settings.v1.candleColorMode"
    static let pricePrecisionKey = "chart.settings.v1.pricePrecision"

    // MARK: - K 线涨跌配色方向

    public static func loadCandleColorMode(defaults: UserDefaults = .standard) -> CandleColorMode {
        guard let raw = defaults.string(forKey: candleColorKey),
              let mode = CandleColorMode(rawValue: raw) else { return .redUpGreenDown }
        return mode
    }

    public static func saveCandleColorMode(_ mode: CandleColorMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: candleColorKey)
    }

    // MARK: - 价格精度

    public static func loadPricePrecision(defaults: UserDefaults = .standard) -> PricePrecisionMode {
        guard let raw = defaults.string(forKey: pricePrecisionKey),
              let mode = PricePrecisionMode(rawValue: raw) else { return .auto }
        return mode
    }

    public static func savePricePrecision(_ mode: PricePrecisionMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: pricePrecisionKey)
    }

    // MARK: - 恢复默认（Settings 中"恢复默认"按钮）

    public static func resetAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: candleColorKey)
        defaults.removeObject(forKey: pricePrecisionKey)
    }
}
