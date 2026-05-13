// v17.139 · 主图叠加指标偏好（VWAP / Pivot Points / SuperTrend）
// 设计要点（与 HUDFieldsBook / IndicatorParamsBook 同模式 · Karpathy "避免过度复杂"）：
// - 3 个 overlay 固定（不让用户自加 · 简化数据流）
// - 全局共享 · 跨合约/周期一致（trader 偏好"我开 VWAP 永远开"）
// - SuperTrend 参数（period/multiplier）用户可调 · UserDefaults 持久化
// - Codable JSON 持久化 · v1 单独 key · 缺失时 fallback default = 全关
// - 默认全关：HUD 不被指标线塞满 · 用户主动开才上线

import Foundation

/// 主图叠加指标种类（按未来扩展顺序）
public enum MainChartOverlayKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case vwap         // VWAP · 累积成交量加权均价（trader 日内基准）
    case pivot        // Pivot Points 7 线（前一根 H/L/C 推算 · daily 周期最适用）
    case superTrend   // SuperTrend · ATR 趋势止损线（rolling lock · 与麦语言 SUPERTREND 一致）
    case ichimoku     // Ichimoku 一目均衡表 4 线（Tenkan/Kijun/Senkou-A/Senkou-B · CHIKOU 用未来 close 不画）
    case donchian     // Donchian Channel 唐奇安通道 3 线（HHV/LLV/MID · 海龟交易法核心）
    case keltner      // Keltner Channel 肯特纳通道 3 线（EMA ± mult*ATR · 趋势/挤压识别）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vwap:       return "VWAP（成交量加权均价）"
        case .pivot:      return "Pivot Points（经典支撑阻力 7 线）"
        case .superTrend: return "SuperTrend（ATR 趋势止损线）"
        case .ichimoku:   return "Ichimoku（一目均衡表 4 线）"
        case .donchian:   return "Donchian Channel（唐奇安通道 3 线）"
        case .keltner:    return "Keltner Channel（肯特纳通道 3 线）"
        }
    }

    /// SF Symbol 图标
    public var icon: String {
        switch self {
        case .vwap:       return "chart.line.uptrend.xyaxis"
        case .pivot:      return "rectangle.split.3x1"
        case .superTrend: return "arrow.triangle.swap"
        case .ichimoku:   return "cloud.fill"
        case .donchian:   return "rectangle.expand.vertical"
        case .keltner:    return "rectangle.compress.vertical"
        }
    }
}

/// 主图叠加偏好（全局 · 跨合约共享）
public struct MainChartOverlayBook: Sendable, Codable, Equatable {
    /// 启用的 overlay 集合
    public var enabled: Set<MainChartOverlayKind>
    /// SuperTrend period（默认 10 · 与麦语言 SUPERTREND 默认一致）
    public var superTrendPeriod: Int
    /// SuperTrend multiplier（默认 3 · 标准参数）
    public var superTrendMultiplier: Decimal
    /// Ichimoku 转换线 Tenkan-sen 周期（默认 9）
    public var ichimokuTenkan: Int
    /// Ichimoku 基准线 Kijun-sen 周期（默认 26）
    public var ichimokuKijun: Int
    /// Ichimoku 先行 B Senkou-Span-B 周期（默认 52）
    public var ichimokuSenkou: Int
    /// Donchian period（默认 20 · 海龟法标准）
    public var donchianPeriod: Int
    /// Keltner EMA 中轴周期（默认 20）
    public var keltnerEMA: Int
    /// Keltner ATR 周期（默认 10）
    public var keltnerATR: Int
    /// Keltner multiplier（默认 2 · 标准）
    public var keltnerMultiplier: Decimal

    public init(
        enabled: Set<MainChartOverlayKind> = [],
        superTrendPeriod: Int = 10,
        superTrendMultiplier: Decimal = 3,
        ichimokuTenkan: Int = 9,
        ichimokuKijun: Int = 26,
        ichimokuSenkou: Int = 52,
        donchianPeriod: Int = 20,
        keltnerEMA: Int = 20,
        keltnerATR: Int = 10,
        keltnerMultiplier: Decimal = 2
    ) {
        self.enabled = enabled
        self.superTrendPeriod = superTrendPeriod
        self.superTrendMultiplier = superTrendMultiplier
        self.ichimokuTenkan = ichimokuTenkan
        self.ichimokuKijun = ichimokuKijun
        self.ichimokuSenkou = ichimokuSenkou
        self.donchianPeriod = donchianPeriod
        self.keltnerEMA = keltnerEMA
        self.keltnerATR = keltnerATR
        self.keltnerMultiplier = keltnerMultiplier
    }

    public static let `default` = MainChartOverlayBook()

    /// 三种 overlay 中是否有任意启用（短路用：全关时跳过 overlay 计算）
    public var anyEnabled: Bool { !enabled.isEmpty }

    public func isEnabled(_ kind: MainChartOverlayKind) -> Bool {
        enabled.contains(kind)
    }

    public mutating func setEnabled(_ kind: MainChartOverlayKind, _ on: Bool) {
        if on { enabled.insert(kind) } else { enabled.remove(kind) }
    }

    // MARK: - Codable · decodeIfPresent fallback（兼容未来字段扩展）

    private enum CodingKeys: String, CodingKey {
        case enabled, superTrendPeriod, superTrendMultiplier
        case ichimokuTenkan, ichimokuKijun, ichimokuSenkou
        case donchianPeriod, keltnerEMA, keltnerATR, keltnerMultiplier
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled              = try c.decodeIfPresent(Set<MainChartOverlayKind>.self, forKey: .enabled) ?? []
        self.superTrendPeriod     = try c.decodeIfPresent(Int.self, forKey: .superTrendPeriod) ?? 10
        self.superTrendMultiplier = try c.decodeIfPresent(Decimal.self, forKey: .superTrendMultiplier) ?? 3
        self.ichimokuTenkan       = try c.decodeIfPresent(Int.self, forKey: .ichimokuTenkan) ?? 9
        self.ichimokuKijun        = try c.decodeIfPresent(Int.self, forKey: .ichimokuKijun) ?? 26
        self.ichimokuSenkou       = try c.decodeIfPresent(Int.self, forKey: .ichimokuSenkou) ?? 52
        self.donchianPeriod       = try c.decodeIfPresent(Int.self, forKey: .donchianPeriod) ?? 20
        self.keltnerEMA           = try c.decodeIfPresent(Int.self, forKey: .keltnerEMA) ?? 20
        self.keltnerATR           = try c.decodeIfPresent(Int.self, forKey: .keltnerATR) ?? 10
        self.keltnerMultiplier    = try c.decodeIfPresent(Decimal.self, forKey: .keltnerMultiplier) ?? 2
    }
}

// MARK: - UserDefaults 加载/保存

public enum MainChartOverlayStore {
    public static let key = "mainChartOverlay.v1"

    /// 失败/不存在返回 nil（caller 决定 fallback default）
    public static func load(defaults: UserDefaults = .standard) -> MainChartOverlayBook? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MainChartOverlayBook.self, from: data)
    }

    /// 写入 UserDefaults · 失败静默
    public static func save(_ book: MainChartOverlayBook, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }
}
