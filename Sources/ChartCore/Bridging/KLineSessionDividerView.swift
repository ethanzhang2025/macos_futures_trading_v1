// ChartCore · WP-40 P1 · session/day 分界竖线叠加
//
// 设计：
//   - 纯 SwiftUI · 与 KLineMetalView 同 ZStack 叠加 · 不进 Metal 渲染管线
//   - 与 KLineGridView 风格一致 · allowsHitTesting=false 不挡 gesture
//   - session gap：灰色短虚线（不打扰）
//   - day gap：橙色长虚线 + 顶部小日期标签（强提示交易日切换）
//
// 跨平台：canImport(SwiftUI) 包裹 · Linux 端不参编

#if canImport(SwiftUI)

import SwiftUI
import Foundation
import Shared

public struct KLineSessionDividerView: View {

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let gaps: [SessionGap]
    public let sessionColor: Color
    public let dayColor: Color
    public let showDayLabel: Bool

    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        gaps: [SessionGap],
        sessionColor: Color = Color.white.opacity(0.10),
        dayColor: Color = Color.orange.opacity(0.45),
        showDayLabel: Bool = true
    ) {
        self.bars = bars
        self.viewport = viewport
        self.gaps = gaps
        self.sessionColor = sessionColor
        self.dayColor = dayColor
        self.showDayLabel = showDayLabel
    }

    public var body: some View {
        GeometryReader { geom in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawDividers(ctx: ctx, size: size)
                }
                if showDayLabel {
                    ForEach(visibleDayGaps(), id: \.barIndex) { gap in
                        if let x = xPosition(barIndex: gap.barIndex, width: geom.size.width) {
                            Text(Self.dayLabelFormatter.string(from: bars[gap.barIndex].openTime))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(dayColor.opacity(0.90))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.30))
                                .cornerRadius(2)
                                .position(x: x + 14, y: 10)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 仅返回可视范围内的 day gap（避免 ForEach 全量遍历）
    private func visibleDayGaps() -> [SessionGap] {
        let lo = viewport.startIndex
        let hi = viewport.startIndex + viewport.visibleCount
        return gaps.filter { $0.kind == .day && $0.barIndex >= lo && $0.barIndex < hi }
    }

    private func xPosition(barIndex: Int, width: CGFloat) -> CGFloat? {
        let visible = max(1, viewport.visibleCount)
        let lo = viewport.startIndex
        guard barIndex >= lo, barIndex < lo + visible else { return nil }
        let xRatio = (CGFloat(barIndex - lo) + 0.5) / CGFloat(visible)
        return xRatio * width
    }

    private func drawDividers(ctx: GraphicsContext, size: CGSize) {
        for gap in gaps {
            guard let x = xPosition(barIndex: gap.barIndex, width: size.width) else { continue }
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            switch gap.kind {
            case .session:
                ctx.stroke(path, with: .color(sessionColor),
                           style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            case .day:
                ctx.stroke(path, with: .color(dayColor),
                           style: StrokeStyle(lineWidth: 1.0, dash: [5, 4]))
            }
        }
    }
}

#endif
