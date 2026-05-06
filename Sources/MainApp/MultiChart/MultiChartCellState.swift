// WP-44 v15.23 batch50 · 多窗口图表 · cell 状态数据模型（macOS-only · 含 KLinePeriod）
//
// 设计：
// - 每 cell 一个独立 state · 持久化到 @AppStorage（JSON）
// - 与 WindowLayout 区分：MultiChartCellState 仅含 UI 必需的合约 + 周期 + 显示标志
// - LayoutFrame 不存这里 · grid preset 计算
//
// 后续 batch51-52 会扩展：indicators / drawings / 主副图布局等

#if canImport(SwiftUI) && os(macOS)

import Foundation
import Shared

/// v15.23 batch79 · cell 副图类型（量 / KDJ / 无）· trader 切换不同维度
enum MultiChartSubChartType: String, Codable, Equatable, Hashable, CaseIterable {
    case none = "none"      // 不显示副图（主图全屏）
    case volume = "volume"  // 成交量（默认）
    case kdj = "kdj"        // KDJ 随机指标（短线超买超卖）
    case macd = "macd"      // MACD 双线 + 红绿柱（趋势 + 量能 · 中长线 trader 必看）
    case rsi = "rsi"        // RSI 14 相对强弱（独立判断超买/超卖 · 30/70 经典阈值）
    case oi = "oi"          // 持仓量 OI（中国期货独有 · 主力意图 + 趋势确认）
    case atr = "atr"        // ATR 14 平均真实波幅（Wilder · trader 设止损 + 仓位管理）

    var displayName: String {
        switch self {
        case .none: return "无副图"
        case .volume: return "成交量"
        case .kdj: return "KDJ"
        case .macd: return "MACD"
        case .rsi: return "RSI"
        case .oi: return "持仓量"
        case .atr: return "ATR"
        }
    }
}

/// 单 cell 配置（多窗口同屏共用）
struct MultiChartCellState: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var instrumentID: String
    var period: KLinePeriod
    /// v15.23 batch52-78 · 副图开关（保留兼容老 cellsJSON · batch79 起改用 subChart 字段语义）
    /// 老用户存量 showVolume=true → batch79 自动迁移为 subChart=.volume
    var showVolume: Bool
    /// v15.23 batch72 · 主图 MA 4 均线（5/10/20/60）开关 · 中国期货短线经典标配
    /// 历史 cellsJSON 缺这个字段时按 true 解码（默认开 · trader 多周期共振直观）
    var showIndicators: Bool
    /// v15.23 batch78 · BOLL 上下轨开关（突破信号 · 默认关避免噪屏 · trader 主动开深入分析）
    var showBoll: Bool
    /// v15.23 batch79 · 副图类型（量/KDJ/无 · 默认 .volume · 老用户由 showVolume 自动迁移）
    var subChart: MultiChartSubChartType
    /// v15.23 batch86 · SAR 抛物线（趋势反转 + 跟踪止损 · 默认关 · 短线 trader 主动开）
    var showSAR: Bool
    /// v15.23 batch91 · 用户手动标记的水平参考线（支撑/压力位 · 价格 list · trader 标关键价位）
    var horizontalLines: [Double]
    /// v15.23 batch93 · 主图视图模式（K 线 / 分时折线 · trader 真盘切换）
    var isTimeShareMode: Bool
    /// v15.23 batch94 · 整数关口辅助线（trader 心理关口 · 自动按价位级别 step · 默认关）
    var showIntegerLevels: Bool

    init(id: UUID = UUID(),
         instrumentID: String = "RB0",
         period: KLinePeriod = .minute15,
         showVolume: Bool = true,
         showIndicators: Bool = true,
         showBoll: Bool = false,
         subChart: MultiChartSubChartType = .volume,
         showSAR: Bool = false,
         horizontalLines: [Double] = [],
         isTimeShareMode: Bool = false,
         showIntegerLevels: Bool = false) {
        self.id = id
        self.instrumentID = instrumentID
        self.period = period
        self.showVolume = showVolume
        self.showIndicators = showIndicators
        self.showBoll = showBoll
        self.subChart = subChart
        self.showSAR = showSAR
        self.horizontalLines = horizontalLines
        self.isTimeShareMode = isTimeShareMode
        self.showIntegerLevels = showIntegerLevels
    }

    /// Codable · 老 cellsJSON 缺新字段时按合理默认值
    enum CodingKeys: String, CodingKey {
        case id, instrumentID, period, showVolume, showIndicators, showBoll, subChart, showSAR, horizontalLines, isTimeShareMode, showIntegerLevels
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.instrumentID = try c.decode(String.self, forKey: .instrumentID)
        self.period = try c.decode(KLinePeriod.self, forKey: .period)
        self.showVolume = try c.decode(Bool.self, forKey: .showVolume)
        self.showIndicators = try c.decodeIfPresent(Bool.self, forKey: .showIndicators) ?? true
        self.showBoll = try c.decodeIfPresent(Bool.self, forKey: .showBoll) ?? false
        // 老用户 cellsJSON 没 subChart 字段 → 按 showVolume 迁移：true → .volume / false → .none
        if let sub = try c.decodeIfPresent(MultiChartSubChartType.self, forKey: .subChart) {
            self.subChart = sub
        } else {
            self.subChart = self.showVolume ? .volume : .none
        }
        self.showSAR = try c.decodeIfPresent(Bool.self, forKey: .showSAR) ?? false
        self.horizontalLines = try c.decodeIfPresent([Double].self, forKey: .horizontalLines) ?? []
        self.isTimeShareMode = try c.decodeIfPresent(Bool.self, forKey: .isTimeShareMode) ?? false
        self.showIntegerLevels = try c.decodeIfPresent(Bool.self, forKey: .showIntegerLevels) ?? false
    }
}

// MARK: - v15.23 batch55 · 命名布局预设（trader 保存"日内 6 图"/"夜盘 2 图"等组合）

struct MultiChartLayoutPreset: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String                       // trader 自定义名（如"日内全屏六宫"）
    var preset: WindowGridPreset
    var cells: [MultiChartCellState]      // 完整 cell 配置（6 个 · 多余的不用）
    var createdAt: Date

    init(id: UUID = UUID(), name: String,
         preset: WindowGridPreset, cells: [MultiChartCellState],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.preset = preset
        self.cells = cells
        self.createdAt = createdAt
    }
}

#endif
