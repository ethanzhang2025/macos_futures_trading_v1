// ChartCore · WP-40 · 时间轴 + 价格刻度（SwiftUI overlay 简化版）
//
// 设计：
// - 纯 SwiftUI · 与 KLineMetalView 通过同一 viewport + bars + priceRange 同步
// - 不走 Metal text 渲染（PoC 阶段过度复杂 · 留 WP-40+ 完整图表引擎）
// - 5 等距标签 · 半透明背景 · 等宽字体 · 视觉风格与 K 线主区协调
//
// 跨平台：canImport(SwiftUI) 包裹 · Linux 端不参编

#if canImport(SwiftUI)

import SwiftUI
import Foundation
import Shared

public struct KLineAxisView: View {

    public enum Orientation: Sendable {
        case time   // 横向 · 底部 · 时间标签
        case price  // 纵向 · 右侧 · 价格标签
    }

    /// 标签数量（视觉密度 · 5 是文华/国信主流 · 默认值 · 可由调用方覆盖 init labelCount）
    /// v17.116 · sparse/dense 数值（3/7）已下放到 Shared/GridDensity.preferredAxisLabelCount · 不再硬编码到 ChartCore
    public static let labelCount = 5
    /// 同日内：仅 HH:mm（v15.33 session-aware · 跨日时智能切到 fullFormatter）
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    /// 跨交易日：MM-dd HH:mm（自动覆盖 · 不需要外部传 flag）
    private static let timeFormatterWithDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let priceRange: ClosedRange<Decimal>
    public let orientation: Orientation
    /// v15.x 主题切换支持 · 默认深色保兼容
    public let axisBackground: Color
    public let axisTextColor: Color
    /// v15.33 session-aware · 可选传入 · 提供时启用跨 session 智能避让标签
    public let sessionGaps: [SessionGap]
    /// v17.114 · 实例 labelCount（默认 Self.labelCount=5 · trader 偏好 GridDensity 时可传 3/5/7）
    public let labelCount: Int

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        orientation: Orientation,
        axisBackground: Color = Color.black.opacity(0.35),
        axisTextColor: Color = Color.white.opacity(0.78),
        sessionGaps: [SessionGap] = [],
        labelCount: Int = KLineAxisView.labelCount
    ) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.orientation = orientation
        self.axisBackground = axisBackground
        self.axisTextColor = axisTextColor
        self.sessionGaps = sessionGaps
        self.labelCount = labelCount
    }

    public var body: some View {
        GeometryReader { geom in
            ZStack(alignment: .topLeading) {
                axisBackground
                ForEach(0..<labelCount, id: \.self) { i in
                    Text(label(at: i))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(axisTextColor)
                        .position(position(at: i, in: geom.size))
                }
                // 视觉迭代第 7 项：价格轴最新 close 黄色高亮标签（仅 .price 模式）
                if orientation == .price, let tag = latestCloseTag(in: geom.size) {
                    tag
                }
            }
        }
    }

    /// 价格轴最新 close 高亮标签（黄底黑字 · 文华标准）
    private func latestCloseTag(in size: CGSize) -> AnyView? {
        guard let close = bars.last?.close else { return nil }
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let closeD = NSDecimalNumber(decimal: close).doubleValue
        guard hi > lo, closeD >= lo, closeD <= hi else { return nil }
        let yRatio = (hi - closeD) / (hi - lo)
        let y = CGFloat(yRatio) * size.height
        return AnyView(
            Text(String(format: "%.2f", closeD))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.yellow)
                .cornerRadius(2)
                .position(x: size.width / 2, y: y)
        )
    }

    /// 可视范围是否跨交易日（决定时间标签格式 · 跨日则带 MM-dd · 同日仅 HH:mm）
    private var visibleSpansMultipleDays: Bool {
        sessionGaps.contains { gap in
            gap.kind == .day &&
            gap.barIndex >= viewport.startIndex &&
            gap.barIndex < viewport.startIndex + viewport.visibleCount
        }
    }

    private func label(at i: Int) -> String {
        switch orientation {
        case .time:
            let visible = max(1, viewport.visibleCount)
            let step = visible / max(1, labelCount - 1)
            let raw = viewport.startIndex + step * i
            let idx = preferLabelIndex(near: raw)
            guard idx >= 0, idx < bars.count else { return "" }
            let formatter = visibleSpansMultipleDays ? Self.timeFormatterWithDate : Self.timeFormatter
            return formatter.string(from: bars[idx].openTime)
        case .price:
            // 顶 = upperBound · 底 = lowerBound · 5 等分（i=0 最上 · i=4 最下）
            let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
            let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
            let t = Double(labelCount - 1 - i) / Double(max(1, labelCount - 1))
            let value = lo + (hi - lo) * t
            return String(format: "%.1f", value)
        }
    }

    /// 标签智能避让：若 raw 索引正好落在 session/day gap 边界（前后 1 根内）·
    /// 把标签平移到 gap 之外的最近 bar · 避免显示跨段 bar 的时间引起视觉割裂
    private func preferLabelIndex(near raw: Int) -> Int {
        let lo = 0
        let hi = bars.count - 1
        let clamped = min(hi, max(lo, raw))
        guard !sessionGaps.isEmpty else { return clamped }
        // gap.barIndex = 跨段起点 · 标签位于 [barIndex - 1, barIndex] 处需平移
        for gap in sessionGaps {
            if abs(clamped - gap.barIndex) <= 1 {
                // 优先往 gap 后侧 · 落在新 session 起点（更直观 · 显示新段开盘时间）
                return min(hi, gap.barIndex)
            }
        }
        return clamped
    }

    private func position(at i: Int, in size: CGSize) -> CGPoint {
        let t = CGFloat(i) / CGFloat(max(1, labelCount - 1))
        switch orientation {
        case .time:
            return CGPoint(x: t * size.width, y: size.height / 2)
        case .price:
            return CGPoint(x: size.width / 2, y: t * size.height)
        }
    }
}

#endif
