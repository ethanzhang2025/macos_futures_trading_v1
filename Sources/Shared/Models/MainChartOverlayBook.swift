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
    case pivot        // Pivot Points 5 线（前一根 H/L/C 推算 · daily 周期最适用 · v17.150 7→5）
    case superTrend   // SuperTrend · ATR 趋势止损线（rolling lock · 与麦语言 SUPERTREND 一致）
    case ichimoku     // Ichimoku 一目均衡表 4 线（Tenkan/Kijun/Senkou-A/Senkou-B · CHIKOU 用未来 close 不画）
    case donchian     // Donchian Channel 唐奇安通道 3 线（HHV/LLV/MID · 海龟交易法核心）
    case keltner      // Keltner Channel 肯特纳通道 3 线（EMA ± mult*ATR · 趋势/挤压识别）
    case sar          // SAR · Welles Wilder 抛物线转向（趋势止损 · 反向信号 · v17.153）
    case priceChannel // Price Channel 价格通道 2 线（HHV/LLV close 版 · 趋势突破 · v17.153）
    case envelopes    // Envelopes 包络线 3 线（MA ± k% · 经典支撑阻力区 · v17.153）
    case hma          // HMA · Hull 移动平均（WMA 复合 · 低延迟 · trader 高级用户 · v17.159）
    case dema         // DEMA · 双重 EMA（2*EMA - EMA(EMA) · 比 EMA 反应更快 · v17.159）
    case tema         // TEMA · 三重 EMA（3*EMA - 3*EMA(EMA) + EMA(EMA(EMA)) · 极低延迟 · v17.159）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vwap:         return "VWAP（成交量加权均价）"
        case .pivot:        return "Pivot Points（经典支撑阻力 5 线）"
        case .superTrend:   return "SuperTrend（ATR 趋势止损线）"
        case .ichimoku:     return "Ichimoku（一目均衡表 4 线）"
        case .donchian:     return "Donchian Channel（唐奇安通道 3 线）"
        case .keltner:      return "Keltner Channel（肯特纳通道 3 线）"
        case .sar:          return "SAR（抛物线转向止损点）"
        case .priceChannel: return "Price Channel（价格通道 2 线 · close 极值）"
        case .envelopes:    return "Envelopes（包络线 3 线 · MA ± k%）"
        case .hma:          return "HMA（Hull 移动平均 · 低延迟）"
        case .dema:         return "DEMA（双重 EMA · 反应快）"
        case .tema:         return "TEMA（三重 EMA · 极低延迟）"
        }
    }

    /// SF Symbol 图标
    public var icon: String {
        switch self {
        case .vwap:         return "chart.line.uptrend.xyaxis"
        case .pivot:        return "rectangle.split.3x1"
        case .superTrend:   return "arrow.triangle.swap"
        case .ichimoku:     return "cloud.fill"
        case .donchian:     return "rectangle.expand.vertical"
        case .keltner:      return "rectangle.compress.vertical"
        case .sar:          return "circle.dotted"
        case .priceChannel: return "rectangle.righthalf.inset.filled"
        case .envelopes:    return "waveform.path.ecg"
        case .hma:          return "wave.3.forward"
        case .dema:         return "wave.3.right"
        case .tema:         return "wave.3.up"
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
    /// v17.161 · Ichimoku CHIKOU 滞后线开关（默认 false · close 后移 kijun 根 · 高级用户开启）
    /// 实时回放下最新 kijun 根 CHIKOU 显示为空 · ChartIndicatorRunner.step 会用新 K 退避填到 (newLen-1-kijun) 位置
    public var ichimokuShowChikou: Bool
    /// v17.162 · Pivot R3/S3 极端阈值线开关（默认 false 5 线 · 开启则 7 线 P/R1/S1/R2/S2/R3/S3）
    public var showPivotR3S3: Bool
    /// v17.162 · SuperTrend 多空方向分色（默认 false 单色 · 开启则按 DIR 拆 SUPERTREND-LONG/SHORT 两段 · 多绿空红视觉）
    public var showSuperTrendDirectionColor: Bool
    /// Donchian period（默认 20 · 海龟法标准）
    public var donchianPeriod: Int
    /// Keltner EMA 中轴周期（默认 20）
    public var keltnerEMA: Int
    /// Keltner ATR 周期（默认 10）
    public var keltnerATR: Int
    /// Keltner multiplier（默认 2 · 标准）
    public var keltnerMultiplier: Decimal
    /// SAR 加速因子初值（默认 0.02 · Welles Wilder · v17.153）
    public var sarStep: Decimal
    /// SAR 加速因子上限（默认 0.2 · v17.153）
    public var sarMax: Decimal
    /// PriceChannel 周期（默认 20 · v17.153）
    public var priceChannelPeriod: Int
    /// Envelopes 中轴 MA 周期（默认 20 · v17.153）
    public var envelopesPeriod: Int
    /// Envelopes 上下偏移百分比（默认 2.5 · v17.153）
    public var envelopesPercent: Decimal
    /// HMA Hull 移动平均周期（默认 16 · trader 高级用户 · v17.159）
    public var hmaPeriod: Int
    /// DEMA 双重 EMA 周期（默认 20 · v17.159）
    public var demaPeriod: Int
    /// TEMA 三重 EMA 周期（默认 20 · v17.159）
    public var temaPeriod: Int

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
        keltnerMultiplier: Decimal = 2,
        sarStep: Decimal = Decimal(string: "0.02") ?? Decimal(0.02),
        sarMax: Decimal = Decimal(string: "0.2") ?? Decimal(0.2),
        priceChannelPeriod: Int = 20,
        envelopesPeriod: Int = 20,
        envelopesPercent: Decimal = Decimal(string: "2.5") ?? Decimal(2.5),
        hmaPeriod: Int = 16,
        demaPeriod: Int = 20,
        temaPeriod: Int = 20,
        ichimokuShowChikou: Bool = false,
        showPivotR3S3: Bool = false,
        showSuperTrendDirectionColor: Bool = false
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
        self.sarStep = sarStep
        self.sarMax = sarMax
        self.priceChannelPeriod = priceChannelPeriod
        self.envelopesPeriod = envelopesPeriod
        self.envelopesPercent = envelopesPercent
        self.hmaPeriod = hmaPeriod
        self.demaPeriod = demaPeriod
        self.temaPeriod = temaPeriod
        self.ichimokuShowChikou = ichimokuShowChikou
        self.showPivotR3S3 = showPivotR3S3
        self.showSuperTrendDirectionColor = showSuperTrendDirectionColor
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
        case sarStep, sarMax, priceChannelPeriod, envelopesPeriod, envelopesPercent  // v17.153
        case hmaPeriod, demaPeriod, temaPeriod  // v17.159
        case ichimokuShowChikou                 // v17.161
        case showPivotR3S3, showSuperTrendDirectionColor  // v17.162
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
        self.sarStep              = try c.decodeIfPresent(Decimal.self, forKey: .sarStep) ?? Decimal(string: "0.02")!
        self.sarMax               = try c.decodeIfPresent(Decimal.self, forKey: .sarMax) ?? Decimal(string: "0.2")!
        self.priceChannelPeriod   = try c.decodeIfPresent(Int.self, forKey: .priceChannelPeriod) ?? 20
        self.envelopesPeriod      = try c.decodeIfPresent(Int.self, forKey: .envelopesPeriod) ?? 20
        self.envelopesPercent     = try c.decodeIfPresent(Decimal.self, forKey: .envelopesPercent) ?? Decimal(string: "2.5")!
        self.hmaPeriod            = try c.decodeIfPresent(Int.self, forKey: .hmaPeriod) ?? 16
        self.demaPeriod           = try c.decodeIfPresent(Int.self, forKey: .demaPeriod) ?? 20
        self.temaPeriod           = try c.decodeIfPresent(Int.self, forKey: .temaPeriod) ?? 20
        self.ichimokuShowChikou   = try c.decodeIfPresent(Bool.self, forKey: .ichimokuShowChikou) ?? false
        self.showPivotR3S3        = try c.decodeIfPresent(Bool.self, forKey: .showPivotR3S3) ?? false
        self.showSuperTrendDirectionColor = try c.decodeIfPresent(Bool.self, forKey: .showSuperTrendDirectionColor) ?? false
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
