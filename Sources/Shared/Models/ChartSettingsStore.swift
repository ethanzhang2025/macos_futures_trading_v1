// MainApp · v17.92 · 图表偏好（K 线配色 + 价格精度）· v17.111 加 4 项（字号 / HUD 透明 / 网格 / 副图高）
//
// 与既有持久化分工：
// - IndicatorParamsBook（Shared）= 指标默认参数（MA/MACD/KDJ/RSI/BOLL 等 19 类）
// - ChartTheme（MainApp/ChartTheme.swift）= dark/light 配色主题（line/tooltip/band）
// - ChartSettingsStore（本文件）= K 线涨跌配色方向 + 价格精度位数 + 字号 + HUD 透明 + 网格 + 副图高
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

/// v17.111 · HUD / Tooltip / Axis 字号档（影响 priceTopBar 大字 + OHLCTooltip + KLineAxisView 等）
public enum ChartFontSize: String, CaseIterable, Sendable {
    case small      // 紧凑（13" Mac 多窗口 trader · -1 pt）
    case medium     // 标准（默认 · v17.110 之前的写死值）
    case large      // 宽松（大屏 · 演讲模式 · +1 pt）

    public var displayName: String {
        switch self {
        case .small:  return "紧凑"
        case .medium: return "标准（默认）"
        case .large:  return "宽松"
        }
    }

    /// 相对标准字号的偏移（point）· 中等档 = 0
    public var sizeDelta: CGFloat {
        switch self {
        case .small:  return -1
        case .medium: return 0
        case .large:  return +1
        }
    }
}

/// v17.111 · HUD 半透明背景档（影响 K 线 HUD / Tooltip / Crosshair chip 等 hud 元素）
public enum HUDOpacityMode: String, CaseIterable, Sendable {
    case subtle     // 弱（0.40 · 浅 trader 喜欢透出背景 K 线）
    case normal     // 标准（默认 · 0.60）
    case strong     // 强（0.80 · trader 强对比读数 · 不在意挡 K 线）

    public var displayName: String {
        switch self {
        case .subtle: return "弱（透出 K 线）"
        case .normal: return "标准（默认）"
        case .strong: return "强（高对比）"
        }
    }

    /// dark 主题下 hudBackground alpha 值
    public var darkAlpha: Double {
        switch self {
        case .subtle: return 0.40
        case .normal: return 0.60
        case .strong: return 0.80
        }
    }

    /// light 主题下 hudBackground alpha 值（高一档对比度补偿）
    public var lightAlpha: Double {
        switch self {
        case .subtle: return 0.65
        case .normal: return 0.85
        case .strong: return 0.95
        }
    }
}

/// v17.111 · 主图/副图 grid label 密度（影响 KLineAxisView 主刻度间距 · 网格线 stride）
public enum GridDensity: String, CaseIterable, Sendable {
    case sparse     // 疏（少标 · 适合长趋势看大格局 · 间距 ×1.5）
    case medium     // 中（默认 · 既有 stride）
    case dense      // 密（多标 · 短线 trader 看刻度 · 间距 ×0.7）

    public var displayName: String {
        switch self {
        case .sparse: return "疏（大趋势）"
        case .medium: return "中（默认）"
        case .dense:  return "密（短线）"
        }
    }

    /// 相对标准 stride 的倍率（中等 = 1.0）· axis label / grid line spacing 用
    public var strideMultiplier: CGFloat {
        switch self {
        case .sparse: return 1.5
        case .medium: return 1.0
        case .dense:  return 0.7
        }
    }
}

/// v17.111 · 副图默认占比（启动 / 重置时主图: 副图区高度比例 · 用户拖分割条仍可临时调）
public enum SubChartDefaultRatio: String, CaseIterable, Sendable {
    case slim       // 窄副图（重心主图 · trader 主看 K 线 · 副图比 0.20）
    case normal     // 标准（默认 · 副图比 0.30）
    case tall       // 高副图（重心副图 · trader 主看指标 · 副图比 0.40）

    public var displayName: String {
        switch self {
        case .slim:   return "窄（重心主图）"
        case .normal: return "标准（默认）"
        case .tall:   return "高（重心副图）"
        }
    }

    /// 副图区在主图+副图总高度中的占比 [0.20, 0.40]
    public var ratio: CGFloat {
        switch self {
        case .slim:   return 0.20
        case .normal: return 0.30
        case .tall:   return 0.40
        }
    }
}

public enum ChartSettingsStore {

    // MARK: - Keys

    static let candleColorKey = "chart.settings.v1.candleColorMode"
    static let pricePrecisionKey = "chart.settings.v1.pricePrecision"
    // v17.111 · 新加 4 项
    static let chartFontSizeKey = "chart.settings.v1.fontSize"
    static let hudOpacityKey = "chart.settings.v1.hudOpacity"
    static let gridDensityKey = "chart.settings.v1.gridDensity"
    static let subChartRatioKey = "chart.settings.v1.subChartRatio"

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

    // MARK: - v17.111 · 字号档

    public static func loadChartFontSize(defaults: UserDefaults = .standard) -> ChartFontSize {
        guard let raw = defaults.string(forKey: chartFontSizeKey),
              let mode = ChartFontSize(rawValue: raw) else { return .medium }
        return mode
    }

    public static func saveChartFontSize(_ mode: ChartFontSize, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: chartFontSizeKey)
    }

    // MARK: - v17.111 · HUD 半透明档

    public static func loadHUDOpacityMode(defaults: UserDefaults = .standard) -> HUDOpacityMode {
        guard let raw = defaults.string(forKey: hudOpacityKey),
              let mode = HUDOpacityMode(rawValue: raw) else { return .normal }
        return mode
    }

    public static func saveHUDOpacityMode(_ mode: HUDOpacityMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: hudOpacityKey)
    }

    // MARK: - v17.111 · 网格密度

    public static func loadGridDensity(defaults: UserDefaults = .standard) -> GridDensity {
        guard let raw = defaults.string(forKey: gridDensityKey),
              let mode = GridDensity(rawValue: raw) else { return .medium }
        return mode
    }

    public static func saveGridDensity(_ mode: GridDensity, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: gridDensityKey)
    }

    // MARK: - v17.111 · 副图默认占比

    public static func loadSubChartDefaultRatio(defaults: UserDefaults = .standard) -> SubChartDefaultRatio {
        guard let raw = defaults.string(forKey: subChartRatioKey),
              let mode = SubChartDefaultRatio(rawValue: raw) else { return .normal }
        return mode
    }

    public static func saveSubChartDefaultRatio(_ mode: SubChartDefaultRatio, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: subChartRatioKey)
    }

    // MARK: - 恢复默认（Settings 中"恢复默认"按钮）

    public static func resetAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: candleColorKey)
        defaults.removeObject(forKey: pricePrecisionKey)
        defaults.removeObject(forKey: chartFontSizeKey)
        defaults.removeObject(forKey: hudOpacityKey)
        defaults.removeObject(forKey: gridDensityKey)
        defaults.removeObject(forKey: subChartRatioKey)
    }
}
