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
import Shared

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

    // v17.94 · K 线"涨/跌"语义色（按 CandleColorMode 切换 redUp / greenUp）
    // 历史：candleBull(red) / candleBear(green) 写死中国习惯 · 调用方意图都是"涨"/"跌" 而非"红"/"绿"
    // 改造：调用方改用 candleUp(mode:) / candleDown(mode:) · ChartSettingsStore.loadCandleColorMode 决定 swap

    /// 涨色（按用户偏好 mode 决定红/绿）
    func candleUp(mode: CandleColorMode) -> Color {
        switch mode {
        case .redUpGreenDown: return candleBull   // 中国习惯：涨红
        case .greenUpRedDown: return candleBear   // 国际习惯：涨绿
        }
    }

    /// 跌色（按用户偏好 mode 决定绿/红）
    func candleDown(mode: CandleColorMode) -> Color {
        switch mode {
        case .redUpGreenDown: return candleBear   // 中国习惯：跌绿
        case .greenUpRedDown: return candleBull   // 国际习惯：跌红
        }
    }

    /// HUD 半透明背景（深色主题用黑底 · 浅色主题用白底 · 让 HUD 文字始终对比清晰）
    var hudBackground: Color {
        switch self {
        case .dark:  return Color.black.opacity(0.60)
        case .light: return Color.white.opacity(0.85)
        }
    }

    /// v17.113 · HUD 半透明背景（带用户偏好 mode · subtle/normal/strong · 跟 dark/light 主题适配）
    /// 老 caller 仍用 var hudBackground（默认 normal）· 新 caller 用本方法
    func hudBackground(mode: HUDOpacityMode) -> Color {
        switch self {
        case .dark:  return Color.black.opacity(mode.darkAlpha)
        case .light: return Color.white.opacity(mode.lightAlpha)
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

// MARK: - 通用 chart 视觉常量（v15.41 · 套利/期权/多图等子窗口共享 · 视觉一致性收敛）
//
// 目标：消除 4 大窗口（SpreadWindow / SpreadBacktestSheet / OptionWindow / OptionBacktestSheet）
//       的散落 hardcoded 颜色 / 字号 / tooltip 风格 · 让 trader 体感一致
//
// 现状收敛：
// - white.opacity 9 级 → 4 级（0.85/0.70/0.55/0.30）
// - 字号 11/10/9 三级（特殊大字 emptyResult 单独保留）
// - tooltip 黑底 0.85 / 白边 0.30 / 6pt 圆角 / 8pt padding · 主图 + 4 子窗口同款
//
// v1 仅深色场景（套利/期权图都是深色 Canvas）· v2 扩浅色（待主题切换扩到子窗口）
extension ChartTheme {

    // MARK: 折线 / 信号色（语义化 · 全 chart 共用）

    /// 主线（套利价差 / Z 线 / 累积 PnL · cyan）
    static let chartLine = Color.cyan
    /// 次线（mean 中线 · 白虚 30%）
    static let chartLineSecondary = Color.white.opacity(0.30)
    /// band 信号线（±2σ 通道 / breakeven · 橙虚）
    static let chartBandLine = Color.orange.opacity(0.40)
    /// 突出 band（hover 时强调用 · 橙 85%）
    static let chartBandLineEmphasized = Color.orange.opacity(0.85)
    /// 现价标识（垂直虚线 · cyan 50%）
    static let chartSpotLine = Color.cyan.opacity(0.50)

    // MARK: 涨跌 / 盈亏色（语义复用 candle）

    /// 盈亏分段过渡（PnL 跨 0 段 · 黄 · 与 CandleColorMode 无关）
    static let chartTransition = Color.yellow

    // v17.125 · 旧 4 个写死 static let（chartProfit/Loss/Emphasized）v17.110 标 deprecated 后已 0 调用 · 本版彻底删除。

    // v17.105 · PnL 盈亏色按 CandleColorMode swap（trader 视觉一致性）
    //
    // 历史问题：chartProfit/Loss 写死 green/red（国际惯例），与 K 线 candleUp/Down 不一致：
    //   - 用户选「涨绿跌红」（greenUp · 国际）→ candle 涨绿 + PnL 涨绿 ✅ 一致
    //   - 用户选「涨红跌绿」（redUp · 中国）  → candle 涨红 + PnL 还是涨绿 ❌ 不一致
    //
    // 修正：PnL 语义 = "赚 / 亏"，方向跟 K 线"涨 / 跌"一致更直觉。
    //   - redUpGreenDown（中国）：profit=red（涨红=赚），loss=green
    //   - greenUpRedDown（国际）：profit=green，loss=red

    /// 盈利色（按 CandleColorMode swap · v17.105）
    static func chartProfitColor(mode: CandleColorMode) -> Color {
        switch mode {
        case .redUpGreenDown: return Color.red       // 中国：涨红=赚=红
        case .greenUpRedDown: return Color.green     // 国际：涨绿=赚=绿
        }
    }

    /// 亏损色（按 CandleColorMode swap · v17.105）
    static func chartLossColor(mode: CandleColorMode) -> Color {
        switch mode {
        case .redUpGreenDown: return Color.green     // 中国：跌绿=亏=绿
        case .greenUpRedDown: return Color.red       // 国际：跌红=亏=红
        }
    }

    /// 突出盈利色（hover/信号高亮用 · 0.85 alpha · v17.105）
    static func chartProfitEmphasizedColor(mode: CandleColorMode) -> Color {
        chartProfitColor(mode: mode).opacity(0.85)
    }

    /// 突出亏损色（hover/信号高亮用 · 0.85 alpha · v17.105）
    static func chartLossEmphasizedColor(mode: CandleColorMode) -> Color {
        chartLossColor(mode: mode).opacity(0.85)
    }

    // MARK: tooltip 风格（hover 4 图 · 主图 KLineCrosshairView 同款）

    /// tooltip 背景（黑 0.85 · 与主图 KLineCrosshairView default 一致）
    static let tooltipBackground = Color.black.opacity(0.85)
    /// tooltip 描边
    static let tooltipBorder = Color.white.opacity(0.30)
    /// tooltip 主文字（高亮值 / 标题）
    static let tooltipPrimary = Color.white
    /// tooltip 次文字（普通值 / 副标题）
    static let tooltipSecondary = Color.white.opacity(0.85)
    /// tooltip 标签文字（行首 label · "价差" / "Z" 等）
    static let tooltipLabel = Color.white.opacity(0.65)
    /// tooltip 弱化文字（时间 / 单位 / 注释）
    static let tooltipMuted = Color.white.opacity(0.55)
    /// tooltip 提示文字（最弱 · 边角说明 · "✓=ITM" 等）
    static let tooltipDimmed = Color.white.opacity(0.40)
    /// tooltip 内分隔线
    static let tooltipDivider = Color.white.opacity(0.30)

    // MARK: 十字光标

    /// 十字虚线
    static let crosshairLine = Color.white.opacity(0.50)

    // MARK: 字号系统（trader 一眼看清的紧凑等距）

    /// 主值（hover tooltip 数值 / HUD 数字 · 11pt monospaced）
    static let fontValue = Font.system(size: 11, design: .monospaced)
    /// 主值粗体（标题 / 高亮）
    static let fontValueBold = Font.system(size: 11, design: .monospaced).weight(.bold)
    /// 标签（行首 label · 与值同字号 · 颜色弱化区分）
    static let fontLabel = Font.system(size: 11, design: .monospaced)
    /// 副值（点位编号 / 范围说明 · 10pt）
    static let fontSubvalue = Font.system(size: 10, design: .monospaced)
    /// 提示（最小 · 单位 / 备注 · 9pt）
    static let fontHint = Font.system(size: 9, design: .monospaced)

    // v17.113 · 字号 mode-aware API（按 ChartFontSize sizeDelta ±1pt · trader 偏好 small / medium 默认 / large）
    //
    // 老 caller 用 fontValue / fontValueBold / fontLabel / fontSubvalue / fontHint 5 个 static let 不变（默认 medium）
    // 新 caller 用 fontValue(size:) 等方法 · 接 ChartFontSize 切换字号档

    private static let fontBaseValue: CGFloat = 11
    private static let fontBaseSubvalue: CGFloat = 10
    private static let fontBaseHint: CGFloat = 9

    /// 主值（hover tooltip 数值 / HUD 数字）按字号档切换
    static func fontValue(size: ChartFontSize) -> Font {
        .system(size: fontBaseValue + size.sizeDelta, design: .monospaced)
    }
    /// 主值粗体（标题 / 高亮）按字号档切换
    static func fontValueBold(size: ChartFontSize) -> Font {
        .system(size: fontBaseValue + size.sizeDelta, design: .monospaced).weight(.bold)
    }
    /// 标签（行首 label）按字号档切换 · 与 fontValue 同字号
    static func fontLabel(size: ChartFontSize) -> Font {
        .system(size: fontBaseValue + size.sizeDelta, design: .monospaced)
    }
    /// 副值（点位编号 / 范围说明）按字号档切换
    static func fontSubvalue(size: ChartFontSize) -> Font {
        .system(size: fontBaseSubvalue + size.sizeDelta, design: .monospaced)
    }
    /// 提示（最小 · 单位 / 备注）按字号档切换
    static func fontHint(size: ChartFontSize) -> Font {
        .system(size: fontBaseHint + size.sizeDelta, design: .monospaced)
    }

    // MARK: tooltip 容器尺寸约定（避免 4 窗口写不同的圆角 / padding）

    static let tooltipPadding: CGFloat = 8
    static let tooltipCornerRadius: CGFloat = 6
    static let tooltipBorderWidth: CGFloat = 0.5
    static let crosshairLineWidth: CGFloat = 0.5
    static let crosshairDash: [CGFloat] = [4, 4]
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
