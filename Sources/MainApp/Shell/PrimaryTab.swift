// MainApp · Shell · v17.0 PoC Step 1
// 一级模块 Tab 枚举 · 5 大模块（看盘 / 套利 / 期权 / 复盘 / 训练）
// 与 Workspace.primaryTab 一对多 · ⌘+1..5 切换

import Foundation

public enum PrimaryTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case watching   = "watching"   // 看盘
    case arbitrage  = "arbitrage"  // 套利
    case option     = "option"     // 期权
    case review     = "review"     // 复盘
    case training   = "training"   // 训练

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .watching:  return "看盘"
        case .arbitrage: return "套利"
        case .option:    return "期权"
        case .review:    return "复盘"
        case .training:  return "训练"
        }
    }

    public var emoji: String {
        switch self {
        case .watching:  return "📊"
        case .arbitrage: return "💱"
        case .option:    return "📈"
        case .review:    return "📝"
        case .training:  return "🎯"
        }
    }

    /// 该模块默认 Pane 类型（新建 workspace 时第一 Pane）
    public var defaultPaneKind: PaneKind {
        switch self {
        case .watching:  return .chart
        case .arbitrage: return .spread
        case .option:    return .option
        case .review:    return .review
        case .training:  return .training
        }
    }
}
