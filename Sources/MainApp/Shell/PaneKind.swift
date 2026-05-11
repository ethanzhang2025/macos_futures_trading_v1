// MainApp · Shell · v17.0 PoC Step 1
// Pane 类型枚举 · 20 种可嵌入 view 的类别
// Pane = Workspace 内一个 view 占位 · PaneHost 按 kind 实例化对应 view

import Foundation

public enum PaneKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // 看盘类
    case chart              // K 线主图（ChartScene）
    case watchlist          // 自选合约
    case sectorHeatmap      // 板块热力（Sector）
    case anomalyMonitor     // 异常监控
    case multiChart         // 多 chart 布局

    // 套利类
    case spread             // 跨期套利
    case calendarSpread     // 日历套利
    case spreadAlert        // 价差告警

    // 期权类
    case option             // 期权链
    case optionBacktest     // 期权回测

    // 复盘类
    case review             // 复盘工作台
    case journal            // 交易日志

    // 训练类
    case training           // 训练 Window
    case formulaEditor      // 公式编辑器

    // 工具类
    case position           // 持仓
    case correlation        // 相关性
    case moneyFlow          // 资金流向
    case heatmap            // 热力图
    case instrumentDashboard // 品种深度
    case sessionCompare     // 时段对比

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chart:              return "K 线图表"
        case .watchlist:          return "自选合约"
        case .sectorHeatmap:      return "板块热力"
        case .anomalyMonitor:     return "异常监控"
        case .multiChart:         return "多图表"
        case .spread:             return "跨期套利"
        case .calendarSpread:     return "日历套利"
        case .spreadAlert:        return "价差告警"
        case .option:             return "期权链"
        case .optionBacktest:     return "期权回测"
        case .review:             return "复盘工作台"
        case .journal:            return "交易日志"
        case .training:           return "训练"
        case .formulaEditor:      return "公式编辑器"
        case .position:           return "持仓"
        case .correlation:        return "相关性"
        case .moneyFlow:          return "资金流向"
        case .heatmap:            return "热力图"
        case .instrumentDashboard: return "品种深度"
        case .sessionCompare:     return "时段对比"
        }
    }

    public var emoji: String {
        switch self {
        case .chart, .multiChart:        return "📊"
        case .watchlist:                 return "⭐"
        case .sectorHeatmap, .heatmap:   return "🔥"
        case .anomalyMonitor:            return "⚠️"
        case .spread, .calendarSpread:   return "💱"
        case .spreadAlert:               return "🔔"
        case .option, .optionBacktest:   return "📈"
        case .review:                    return "📝"
        case .journal:                   return "📓"
        case .training:                  return "🎯"
        case .formulaEditor:             return "🧮"
        case .position:                  return "💼"
        case .correlation:               return "🔗"
        case .moneyFlow:                 return "💧"
        case .instrumentDashboard:       return "🧭"
        case .sessionCompare:            return "⏱"
        }
    }

    /// 该类 Pane 是否需要绑定 symbol（true = 参与彩色 group 联动）
    public var bindsSymbol: Bool {
        switch self {
        case .chart, .multiChart, .spread, .calendarSpread,
             .option, .optionBacktest, .position, .instrumentDashboard,
             .sessionCompare:
            return true
        default:
            return false
        }
    }
}
