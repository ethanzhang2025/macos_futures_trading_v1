// MainApp · 主图主题（v15.8 · 深色 / 浅色切换）
//
// 设计要点（Karpathy "避免过度复杂"）：
// - 主题只覆盖"跨主题需切换的"颜色（背景 / 文字 / 网格 / candle）
// - 不覆盖语义颜色（MACD 黄/紫 / KDJ 黄/紫/蓝 等 · 这些颜色无关主题 · 保持原色）
// - 不覆盖图标系统色（Button/Toggle 跟随系统 .preferredColorScheme）
// - UserDefaults 持久化 key=chartTheme.v1
//
// 不做：
// - 不做用户自定义颜色（v1 仅 .dark/.light 二选一）
// - 不做 system follow（用户已通过 SwiftUI .preferredColorScheme 间接控制 · v2 评估）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation

/// K 线主图主题
enum ChartTheme: String, CaseIterable, Identifiable, Codable {
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark:  return "深色"
        case .light: return "浅色"
        }
    }

    var icon: String {
        switch self {
        case .dark:  return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    /// 主图 / 副图 / HUD 背景色（深色 #11141A · 浅色 #F5F6F8）
    var background: Color {
        switch self {
        case .dark:  return Color(red: 0.07,  green: 0.08,  blue: 0.10)
        case .light: return Color(red: 0.96,  green: 0.965, blue: 0.972)
        }
    }

    /// 工具栏背景（与主图协调 · 深色 #15171C · 浅色 #ECEEF1）
    var toolbarBackground: Color {
        switch self {
        case .dark:  return Color(red: 0.082, green: 0.090, blue: 0.110)
        case .light: return Color(red: 0.925, green: 0.932, blue: 0.945)
        }
    }

    /// 主要文字（深色白 / 浅色黑）
    var textPrimary: Color {
        switch self {
        case .dark:  return .white
        case .light: return Color(red: 0.10, green: 0.11, blue: 0.13)
        }
    }

    /// 次要文字（HUD 标签 / 副图 stat label）
    var textSecondary: Color {
        switch self {
        case .dark:  return Color.white.opacity(0.55)
        case .light: return Color(red: 0.40, green: 0.42, blue: 0.46)
        }
    }

    /// 网格线（背景上的轻微分隔）
    var gridLine: Color {
        switch self {
        case .dark:  return Color.white.opacity(0.10)
        case .light: return Color.black.opacity(0.10)
        }
    }

    /// K 线涨色（红 · 中国习惯涨红跌绿 · 与系统不同）
    /// 主题不改红绿语义 · 仅微调亮度让浅色背景下不刺眼
    var candleBull: Color {
        switch self {
        case .dark:  return Color(red: 0.96, green: 0.27, blue: 0.27)
        case .light: return Color(red: 0.85, green: 0.18, blue: 0.18)
        }
    }

    var candleBear: Color {
        switch self {
        case .dark:  return Color(red: 0.18, green: 0.74, blue: 0.42)
        case .light: return Color(red: 0.10, green: 0.55, blue: 0.30)
        }
    }

    /// HUD 半透明背景（深色主题用黑底 · 浅色主题用白底 · 让 HUD 文字始终对比清晰）
    var hudBackground: Color {
        switch self {
        case .dark:  return Color.black.opacity(0.60)
        case .light: return Color.white.opacity(0.85)
        }
    }

    /// v15.17 · SwiftUI ColorScheme 桥接 · ChartScene 用 .preferredColorScheme(chartTheme.colorScheme)
    /// 让 sheet / 系统按钮 / NSPopUpButton 等系统色组件也跟主题切换
    var colorScheme: ColorScheme {
        switch self {
        case .dark:  return .dark
        case .light: return .light
        }
    }
}

// MARK: - 跨 Window 主题同步（v15.17 · 让次级窗口 sheet/popup 也跟主图 chartTheme.v1）

/// v15.17 · ViewModifier · 监听 chartTheme.v1 UserDefaults 变化 · 动态 .preferredColorScheme
/// 用于 AlertWindow / JournalWindow / TradingWindow 等次级窗口 · 不持有 chartTheme @State 也能跟主题
struct ChartThemeFollowing: ViewModifier {
    @State private var theme: ChartTheme = ChartThemeStore.load() ?? .dark

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(theme.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                if let t = ChartThemeStore.load(), t != theme {
                    theme = t
                }
            }
    }
}

extension View {
    /// 简便扩展：`.followingChartTheme()` 让任意 View 跟主图主题切换
    func followingChartTheme() -> some View {
        modifier(ChartThemeFollowing())
    }
}

// MARK: - Metal MTLClearColor 桥接（v15.x 主图 K 线 Metal 渲染背景跟主题）

#if canImport(Metal)
import Metal

extension ChartTheme {
    /// MTKView.clearColor 用 · 与 background SwiftUI Color 对齐
    /// 深色 #11141A · 浅色 #F5F6F8（数值与 KLineMetalView.defaultClearColor / lightClearColor 同步）
    var metalClearColor: MTLClearColor {
        switch self {
        case .dark:  return MTLClearColorMake(0.07,  0.08,  0.10,  1.0)
        case .light: return MTLClearColorMake(0.96,  0.965, 0.972, 1.0)
        }
    }
}
#endif

// MARK: - UserDefaults 加载/保存

enum ChartThemeStore {
    static let key = "chartTheme.v1"

    static func load(defaults: UserDefaults = .standard) -> ChartTheme? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return ChartTheme(rawValue: raw)
    }

    static func save(_ theme: ChartTheme, defaults: UserDefaults = .standard) {
        defaults.set(theme.rawValue, forKey: key)
    }
}

#endif
