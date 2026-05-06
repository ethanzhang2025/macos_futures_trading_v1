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

    init(id: UUID = UUID(),
         instrumentID: String = "RB0",
         period: KLinePeriod = .minute15,
         showVolume: Bool = true) {
        self.id = id
        self.instrumentID = instrumentID
        self.period = period
        self.showVolume = showVolume
    }
}

#endif
