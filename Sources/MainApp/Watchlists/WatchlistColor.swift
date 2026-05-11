// v17.36 C1 · 自选分组颜色（trader 视觉分类 · 主力/套利/股指 等不同策略组）
//
// 设计：
// - 8 色预设 + 默认 accent（colorIndex == nil）
// - 与 ChartTheme 同源（深浅主题下颜色不变）
// - 主入口：fromIndex(_:) · 安全 clamp · 越界返回 .accentColor

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

public enum WatchlistColor {

    /// 8 色预设 · trader 一眼区分（红涨/绿跌/蓝资金/紫黑天鹅等）
    public static let preset: [(name: String, color: Color)] = [
        ("红",    Color(red: 0.96, green: 0.27, blue: 0.27)),   // 0
        ("橙",    Color(red: 1.00, green: 0.58, blue: 0.20)),   // 1
        ("黄",    Color(red: 1.00, green: 0.78, blue: 0.18)),   // 2
        ("绿",    Color(red: 0.18, green: 0.74, blue: 0.42)),   // 3
        ("青",    Color(red: 0.30, green: 0.78, blue: 1.00)),   // 4
        ("蓝",    Color(red: 0.35, green: 0.55, blue: 0.95)),   // 5
        ("紫",    Color(red: 0.63, green: 0.42, blue: 0.83)),   // 6
        ("灰",    Color(red: 0.55, green: 0.55, blue: 0.55))    // 7
    ]

    /// nil / 越界 → .accentColor（默认）
    public static func color(forIndex idx: Int?) -> Color {
        guard let i = idx, preset.indices.contains(i) else { return .accentColor }
        return preset[i].color
    }

    /// nil / 越界 → "默认"
    public static func name(forIndex idx: Int?) -> String {
        guard let i = idx, preset.indices.contains(i) else { return "默认" }
        return preset[i].name
    }
}

#endif
