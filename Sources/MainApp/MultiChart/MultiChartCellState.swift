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

/// 单 cell 配置（多窗口同屏共用）
struct MultiChartCellState: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var instrumentID: String
    var period: KLinePeriod
    var showVolume: Bool
    /// v15.23 batch72 · 主图 MA 双均线（MA5 + MA20）开关 · 中国期货短线标配
    /// 历史 cellsJSON 缺这个字段时按 true 解码（默认开 · trader 多周期共振直观）
    var showIndicators: Bool
    /// v15.23 batch78 · BOLL 上下轨开关（突破信号 · 默认关避免噪屏 · trader 主动开深入分析）
    var showBoll: Bool

    init(id: UUID = UUID(),
         instrumentID: String = "RB0",
         period: KLinePeriod = .minute15,
         showVolume: Bool = true,
         showIndicators: Bool = true,
         showBoll: Bool = false) {
        self.id = id
        self.instrumentID = instrumentID
        self.period = period
        self.showVolume = showVolume
        self.showIndicators = showIndicators
        self.showBoll = showBoll
    }

    /// Codable · 老 cellsJSON 反序列化时 showIndicators/showBoll 缺字段时按 true / false 默认
    enum CodingKeys: String, CodingKey {
        case id, instrumentID, period, showVolume, showIndicators, showBoll
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.instrumentID = try c.decode(String.self, forKey: .instrumentID)
        self.period = try c.decode(KLinePeriod.self, forKey: .period)
        self.showVolume = try c.decode(Bool.self, forKey: .showVolume)
        self.showIndicators = try c.decodeIfPresent(Bool.self, forKey: .showIndicators) ?? true
        self.showBoll = try c.decodeIfPresent(Bool.self, forKey: .showBoll) ?? false
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
