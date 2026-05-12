// MainApp · Shell · v17.67 · Workspace 内置预设库
// trader 主动选「从预设新建...」时使用 · 不影响首次启动 Workspace.defaults()（已有 3 个）
// 设计：每个预设 = 一组完整 PaneConfig + paneLayout + 推荐 primaryTab + 简介

import Foundation

public enum WorkspacePreset: String, CaseIterable, Identifiable, Sendable {
    case multiPeriodResonance    // 📈 多周期共振（4 周期 + blue group）
    case multiSymbolMonitor      // 🌃 多品种监控（6 主力合约）
    case watchlistAndChart       // 🎨 自选+图表（2-Pane 左右）
    case optionStrategy          // 📋 期权策略台（4-Pane chart/option/spread/journal）
    case fullNineGrid            // 📊 全屏 9 格（多周期 + 多品种综合）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .multiPeriodResonance: return "多周期共振"
        case .multiSymbolMonitor:   return "多品种监控"
        case .watchlistAndChart:    return "自选 + 图表"
        case .optionStrategy:       return "期权策略台"
        case .fullNineGrid:         return "全屏 9 格综合"
        }
    }

    public var emoji: String {
        switch self {
        case .multiPeriodResonance: return "📈"
        case .multiSymbolMonitor:   return "🌃"
        case .watchlistAndChart:    return "🎨"
        case .optionStrategy:       return "📋"
        case .fullNineGrid:         return "📊"
        }
    }

    public var subtitle: String {
        switch self {
        case .multiPeriodResonance: return "rb2510 · 1m / 5m / 15m / 1H · blue group 联动"
        case .multiSymbolMonitor:   return "rb / hc / i / au / ag / cu · 6 主力合约 5m"
        case .watchlistAndChart:    return "左 watchlist + 右 K 线图表 · 经典看盘"
        case .optionStrategy:       return "chart + option chain + spread + journal · 4 联动"
        case .fullNineGrid:         return "多周期 6 + watchlist + spread + journal · 全屏布局"
        }
    }

    public var recommendedPrimaryTab: PrimaryTab {
        switch self {
        case .multiPeriodResonance, .multiSymbolMonitor, .watchlistAndChart, .fullNineGrid:
            return .watching
        case .optionStrategy:
            return .option
        }
    }

    public var paneLayout: PaneLayout {
        switch self {
        case .watchlistAndChart:    return .twoHorizontal
        case .multiPeriodResonance: return .four
        case .optionStrategy:       return .four
        case .multiSymbolMonitor:   return .sixGrid
        case .fullNineGrid:         return .nineGrid
        }
    }

    public func panes() -> [PaneConfig] {
        switch self {
        case .multiPeriodResonance:
            return [
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "1m",  groupColor: .blue),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m",  groupColor: .blue),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "15m", groupColor: .blue),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "1H",  groupColor: .blue),
            ]
        case .multiSymbolMonitor:
            return [
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "hc2510", periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "i2510",  periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "au2512", periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "ag2512", periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "cu2511", periodRaw: "5m"),
            ]
        case .watchlistAndChart:
            return [
                PaneConfig(kind: .watchlist),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m"),
            ]
        case .optionStrategy:
            return [
                PaneConfig(kind: .chart,  symbol: "rb2510", periodRaw: "5m",  groupColor: .orange),
                PaneConfig(kind: .option, symbol: "rb2510",                    groupColor: .orange),
                PaneConfig(kind: .spread, symbol: "rb2510",                    groupColor: .orange),
                PaneConfig(kind: .journal),
            ]
        case .fullNineGrid:
            return [
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "1m",  groupColor: .red),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m",  groupColor: .red),
                PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "15m", groupColor: .red),
                PaneConfig(kind: .chart, symbol: "hc2510", periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "i2510",  periodRaw: "5m"),
                PaneConfig(kind: .chart, symbol: "au2512", periodRaw: "5m"),
                PaneConfig(kind: .watchlist),
                PaneConfig(kind: .spread),
                PaneConfig(kind: .journal),
            ]
        }
    }

    /// 直接构造完整 Workspace · 应用预设
    public func toWorkspace() -> Workspace {
        let now = Date()
        return Workspace(
            name: "\(emoji) \(displayName)",
            primaryTab: recommendedPrimaryTab,
            paneLayout: paneLayout,
            panes: panes(),
            createdAt: now,
            lastUsedAt: now
        )
    }
}
