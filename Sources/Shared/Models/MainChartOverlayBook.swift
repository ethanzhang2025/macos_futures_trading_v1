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

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vwap:       return "VWAP（成交量加权均价）"
        case .pivot:      return "Pivot Points（经典支撑阻力 7 线）"
        case .superTrend: return "SuperTrend（ATR 趋势止损线）"
        }
    }

    /// SF Symbol 图标
    public var icon: String {
        switch self {
        case .vwap:       return "chart.line.uptrend.xyaxis"
        case .pivot:      return "rectangle.split.3x1"
        case .superTrend: return "arrow.triangle.swap"
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

    public init(
        enabled: Set<MainChartOverlayKind> = [],
        superTrendPeriod: Int = 10,
        superTrendMultiplier: Decimal = 3
    ) {
        self.enabled = enabled
        self.superTrendPeriod = superTrendPeriod
        self.superTrendMultiplier = superTrendMultiplier
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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled              = try c.decodeIfPresent(Set<MainChartOverlayKind>.self, forKey: .enabled) ?? []
        self.superTrendPeriod     = try c.decodeIfPresent(Int.self, forKey: .superTrendPeriod) ?? 10
        self.superTrendMultiplier = try c.decodeIfPresent(Decimal.self, forKey: .superTrendMultiplier) ?? 3
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
