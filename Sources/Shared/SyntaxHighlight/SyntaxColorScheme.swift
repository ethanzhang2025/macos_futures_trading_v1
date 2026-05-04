// WP-65 v15.22 batch2 · syntax 高亮配色方案（kind → RGB · 深/浅主题适配）
//
// 设计：
// - 不依赖 SwiftUI Color / NSColor · 输出 RGB(Double) · UI 层自己包装
//   （Linux 测试可验证 · macOS 用 NSColor / SwiftUI Color 包装）
// - 两套配色：dark / light · 与 ChartTheme 双主题对齐
// - 颜色经验值：参考 Xcode / VSCode 暗色 · 数值高对比 · 关键字偏暖 · 字符串偏冷
//
// 配色原则：
// - keyword 紫红（控制流醒目）
// - builtinFunc 蓝（数据源 · 大量出现）
// - number 橙（数值视觉跳出）
// - string 绿（字符串 · 经典选择）
// - comment 灰（次要 · 不抢戏）
// - drawAttribute 青（绘图属性 · 与函数区分）
// - operatorPunct textPrimary（与正文同色 · 不强调）
// - identifier textPrimary（用户变量 · 与正文同色）
// - error 红（错误高亮）

import Foundation

/// RGB（每分量 0~1）+ 不依赖任何 UI 框架 · 跨平台
public struct SyntaxRGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// 16 进制 hex（如 "#FF8800"）便于 UI 调试 / 持久化
    public var hex: String {
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, ri)), max(0, min(255, gi)), max(0, min(255, bi)))
    }
}

/// syntax 配色方案（kind → RGB）· 深/浅主题各一套
public enum SyntaxColorScheme: Sendable, Equatable {
    case dark
    case light

    /// 切换主题（与 chartTheme 同步用）
    public var opposite: SyntaxColorScheme { self == .dark ? .light : .dark }

    public func color(for kind: SyntaxColorKind) -> SyntaxRGB {
        switch self {
        case .dark:  return Self.darkPalette[kind] ?? Self.darkPalette[.identifier]!
        case .light: return Self.lightPalette[kind] ?? Self.lightPalette[.identifier]!
        }
    }

    // MARK: - 调色板（与 Xcode Default Dark / Light 接近）

    private static let darkPalette: [SyntaxColorKind: SyntaxRGB] = [
        .keyword:        SyntaxRGB(0.99, 0.45, 0.84),   // #FE73D7 紫红 · 控制流
        .builtinFunc:    SyntaxRGB(0.42, 0.78, 0.97),   // #6BC7F8 亮蓝 · 函数
        .number:         SyntaxRGB(0.97, 0.62, 0.36),   // #F89E5C 橙
        .string:         SyntaxRGB(0.52, 0.85, 0.55),   // #85D98C 绿
        .comment:        SyntaxRGB(0.55, 0.58, 0.62),   // #8C949E 灰
        .drawAttribute:  SyntaxRGB(0.40, 0.85, 0.85),   // #66D9D9 青
        .operatorPunct:  SyntaxRGB(0.85, 0.85, 0.88),   // #D9D9E0 浅白（与正文同色）
        .identifier:     SyntaxRGB(0.92, 0.92, 0.94),   // #EBEBF0 白
        .error:          SyntaxRGB(0.96, 0.34, 0.34),   // #F55757 红
    ]

    private static let lightPalette: [SyntaxColorKind: SyntaxRGB] = [
        .keyword:        SyntaxRGB(0.78, 0.16, 0.55),   // #C7298C 暗紫红
        .builtinFunc:    SyntaxRGB(0.10, 0.40, 0.78),   // #1A66C7 深蓝
        .number:         SyntaxRGB(0.72, 0.36, 0.10),   // #B85C1A 暗橙
        .string:         SyntaxRGB(0.20, 0.58, 0.30),   // #33944D 暗绿
        .comment:        SyntaxRGB(0.45, 0.48, 0.52),   // #737A85 中灰
        .drawAttribute:  SyntaxRGB(0.10, 0.55, 0.60),   // #1A8C99 暗青
        .operatorPunct:  SyntaxRGB(0.20, 0.22, 0.25),   // #333840 深灰（正文）
        .identifier:     SyntaxRGB(0.10, 0.11, 0.13),   // #1A1C21 黑
        .error:          SyntaxRGB(0.78, 0.18, 0.18),   // #C72E2E 暗红
    ]
}
