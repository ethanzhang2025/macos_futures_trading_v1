import SwiftUI

/// 深色交易主题配色
enum Theme {
    // 背景
    static let background = Color(red: 0.09, green: 0.09, blue: 0.11)       // #171719
    static let panelBackground = Color(red: 0.12, green: 0.12, blue: 0.14)  // #1E1E24
    static let chartBackground = Color(red: 0.10, green: 0.10, blue: 0.12)  // #1A1A1F

    // 涨跌
    static let up = Color(red: 0.92, green: 0.26, blue: 0.24)      // 红 涨
    static let down = Color(red: 0.18, green: 0.75, blue: 0.45)    // 绿 跌
    static let flat = Color(red: 0.60, green: 0.60, blue: 0.65)    // 灰 平

    // 文字
    static let textPrimary = Color(red: 0.88, green: 0.88, blue: 0.90)
    static let textSecondary = Color(red: 0.50, green: 0.50, blue: 0.55)
    static let textMuted = Color(red: 0.35, green: 0.35, blue: 0.40)

    // 线条
    static let gridLine = Color(red: 0.20, green: 0.20, blue: 0.24)
    static let crosshair = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let border = Color(red: 0.22, green: 0.22, blue: 0.26)

    // 均线
    static let ma5 = Color(red: 1.0, green: 0.75, blue: 0.20)     // 橙黄
    static let ma10 = Color(red: 0.30, green: 0.70, blue: 1.0)    // 蓝
    static let ma20 = Color(red: 0.85, green: 0.35, blue: 0.85)   // 紫

    // 成交量
    static let volumeUp = Color(red: 0.92, green: 0.26, blue: 0.24).opacity(0.6)
    static let volumeDown = Color(red: 0.18, green: 0.75, blue: 0.45).opacity(0.6)

    // 十字光标信息框
    static let tooltipBackground = Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.95)

    // 选中高亮
    static let selected = Color(red: 0.20, green: 0.35, blue: 0.55)

    /// 价格颜色
    static func priceColor(_ change: Decimal) -> Color {
        if change > 0 { return up }
        if change < 0 { return down }
        return flat
    }
}
