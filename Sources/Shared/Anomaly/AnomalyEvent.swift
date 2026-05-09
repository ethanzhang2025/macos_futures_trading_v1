// 异常事件模型（v15.54 · ⌘⌥A 异常品种监控）
//
// 5 维度异常 · 全市场扫描（60+ 品种）· 不订阅 Tick · 基于 SectorPresets 快照
// v2 接 CTP 真行情后整段切换数据源 · API 不变
//
// 与 AlertCore 的边界：
// - AlertCore = 实时 Tick 驱动 · 用户预设条件 · 触发通知
// - Anomaly   = 全市场快照扫描 · 自动浮现异常 · 可视化（无主动通知 v1）

import Foundation

/// 异常类型 · 5 维度
public enum AnomalyKind: String, Sendable, Codable, CaseIterable, Identifiable {
    /// 价格异动：|涨跌幅| ≥ 阈值（默认 ±2%）
    case priceSpike
    /// 持仓异动：openInterestK 显著高于板块均值（默认 ≥ 1.5×）
    case oiSpike
    /// 资金异动：净流入金额绝对值 ≥ 阈值（默认 ±50 百万元）
    case fundSurge
    /// 量价背离：涨价但减仓 / 跌价但增仓（mock：基于 hash 标记）
    case priceOIDivergence
    /// 板块离群：方向与板块多数相反（多数涨我跌 · 反之亦然）
    case sectorOutlier

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .priceSpike:         return "价格异动"
        case .oiSpike:            return "持仓异动"
        case .fundSurge:          return "资金异动"
        case .priceOIDivergence:  return "量价背离"
        case .sectorOutlier:      return "板块离群"
        }
    }

    /// SF Symbol 图标
    public var icon: String {
        switch self {
        case .priceSpike:         return "bolt.fill"
        case .oiSpike:            return "chart.bar.fill"
        case .fundSurge:          return "dollarsign.circle.fill"
        case .priceOIDivergence:  return "arrow.left.arrow.right"
        case .sectorOutlier:      return "exclamationmark.triangle.fill"
        }
    }
}

/// 单条异常事件
public struct AnomalyEvent: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let instrumentID: String
    public let instrumentName: String
    public let sector: Sector
    public let kind: AnomalyKind
    /// 严重度 [0, 100] · UI 排序 + 染色用
    public let severity: Double
    /// 中文描述（含触发数值）
    public let description: String
    public let detectedAt: Date

    public init(
        id: UUID = UUID(),
        instrumentID: String,
        instrumentName: String,
        sector: Sector,
        kind: AnomalyKind,
        severity: Double,
        description: String,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.instrumentName = instrumentName
        self.sector = sector
        self.kind = kind
        self.severity = max(0, min(100, severity))
        self.description = description
        self.detectedAt = detectedAt
    }
}

/// 异常检测阈值（5 类各一组）· 可调
public struct AnomalyThresholds: Sendable, Equatable {
    /// 价格异动：|changePct| ≥ 阈值（百分比 · 默认 2.0 = 2%）
    public var priceSpikePct: Double
    /// 持仓异动：openInterestK / 板块均值 ≥ 阈值（默认 1.5）
    public var oiSpikeMultiple: Double
    /// 资金异动：|净流入百万| ≥ 阈值（默认 50.0）
    public var fundSurgeMillion: Double
    /// 启用各类
    public var enabledKinds: Set<AnomalyKind>

    public init(
        priceSpikePct: Double = 2.0,
        oiSpikeMultiple: Double = 1.5,
        fundSurgeMillion: Double = 50.0,
        enabledKinds: Set<AnomalyKind> = Set(AnomalyKind.allCases)
    ) {
        self.priceSpikePct = priceSpikePct
        self.oiSpikeMultiple = oiSpikeMultiple
        self.fundSurgeMillion = fundSurgeMillion
        self.enabledKinds = enabledKinds
    }

    public static let `default` = AnomalyThresholds()
}

/// 检测结果汇总
public struct AnomalyDetectionResult: Sendable, Equatable {
    /// 全部事件 · 按 severity 降序
    public let events: [AnomalyEvent]
    /// 各类计数
    public let countByKind: [AnomalyKind: Int]
    /// 各板块计数（板块分布饼图用）
    public let countBySector: [Sector: Int]

    public init(events: [AnomalyEvent], countByKind: [AnomalyKind: Int], countBySector: [Sector: Int]) {
        self.events = events
        self.countByKind = countByKind
        self.countBySector = countBySector
    }

    public var total: Int { events.count }
}
