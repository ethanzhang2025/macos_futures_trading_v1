// WP-42 · 画线 SwiftUI Canvas 渲染层（v13.0 · 接 ChartScene drawings 状态）
//
// 职责：
//   - 接收 [Drawing] + bars + viewport + priceRange + 可选 selectedID
//   - 用 SwiftUI Canvas 绘制 6 种画线类型（trendLine / horizontalLine / rectangle / parallelChannel / fibonacci / text）
//   - 选中态高亮（线宽 2.5 vs 默认 1.5 · 色彩饱和度提高）
//   - allowsHitTesting false（鼠标事件在 ChartScene 内的 onTapGesture 处理 · 这里只渲染）
//
// 数据空间 → 屏幕坐标转换：
//   x = (barIndex - viewport.startIndex) * barWidth
//   y = (priceRange.upperBound - price) / priceSpan * size.height

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared

public struct DrawingsOverlayView: View {

    public let bars: [KLine]
    public let viewport: RenderViewport
    public let priceRange: ClosedRange<Decimal>
    public let drawings: [Drawing]
    /// 选中的画线 ID（高亮显示 · nil 表示未选中）
    public let selectedID: UUID?
    /// 正在创建中的双点画线（第一点已落 · 第二点未确定 · hover 跟随用 cursorPoint 预览）
    public let pendingDrawing: Drawing?

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        drawings: [Drawing],
        selectedID: UUID? = nil,
        pendingDrawing: Drawing? = nil
    ) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.drawings = drawings
        self.selectedID = selectedID
        self.pendingDrawing = pendingDrawing
    }

    public var body: some View {
        Canvas { ctx, size in
            for drawing in drawings {
                draw(drawing, in: ctx, size: size, isSelected: drawing.id == selectedID)
            }
            // pending（创建中的）画线用半透明虚线预览
            if let p = pendingDrawing {
                draw(p, in: ctx, size: size, isPending: true)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 数据空间 → 屏幕坐标

    private func xForBar(_ barIndex: Int, size: CGSize) -> CGFloat {
        let visibleCount = max(1, viewport.visibleCount)
        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)
        return (CGFloat(barIndex - viewport.startIndex) + 0.5 - xOffset) * barWidth
    }

    private func yForPrice(_ price: Decimal, size: CGSize) -> CGFloat {
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let p = NSDecimalNumber(decimal: price).doubleValue
        let span = max(0.0001, hi - lo)
        return CGFloat((hi - p) / span) * size.height
    }

    // MARK: - 画线分发

    private func draw(_ drawing: Drawing, in ctx: GraphicsContext, size: CGSize, isSelected: Bool = false, isPending: Bool = false) {
        let baseColor = Self.colorFor(drawing.type)
        let lineWidth: CGFloat = isSelected ? 2.5 : 1.5
        let dash: [CGFloat] = isPending ? [4, 3] : []
        let opacity = isPending ? 0.6 : 1.0

        switch drawing.type {
        case .trendLine:        drawTrendLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .horizontalLine:   drawHorizontalLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .rectangle:        drawRectangle(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .parallelChannel:  drawParallelChannel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacci:        drawFibonacci(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .text:             drawText(drawing, ctx, size, baseColor, opacity)
        }

        if isSelected, !isPending {
            drawAnchorPoints(drawing, ctx, size, baseColor)
        }
    }

    // MARK: - 类型分发渲染

    private func drawTrendLine(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        var path = Path()
        path.move(to: CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size)))
        path.addLine(to: CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size)))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func drawHorizontalLine(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        let y = yForPrice(d.startPoint.price, size: size)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 价格标签
        let label = formatPrice(d.startPoint.price)
        let text = Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(color)
        ctx.draw(text, at: CGPoint(x: size.width - 30, y: y - 8))
    }

    private func drawRectangle(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let x1 = xForBar(d.startPoint.barIndex, size: size)
        let x2 = xForBar(end.barIndex, size: size)
        let y1 = yForPrice(d.startPoint.price, size: size)
        let y2 = yForPrice(end.price, size: size)
        let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        ctx.fill(Path(rect), with: .color(color.opacity(0.08 * opacity)))
        ctx.stroke(Path(rect), with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func drawParallelChannel(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint, let offset = d.channelOffset else { return }
        let mainStart = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let mainEnd = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let offsetStart = CGPoint(x: mainStart.x, y: yForPrice(d.startPoint.price + offset, size: size))
        let offsetEnd = CGPoint(x: mainEnd.x, y: yForPrice(end.price + offset, size: size))
        var path = Path()
        path.move(to: mainStart); path.addLine(to: mainEnd)
        path.move(to: offsetStart); path.addLine(to: offsetEnd)
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func drawFibonacci(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard d.endPoint != nil else { return }
        let prices = DrawingGeometry.fibonacciPrices(for: d)
        let levels = FibonacciLevels.standard
        for (i, price) in prices.enumerated() {
            let y = yForPrice(price, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(path, with: .color(color.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
            let pct = NSDecimalNumber(decimal: levels[i]).doubleValue * 100
            let priceLabel = formatPrice(price)
            let text = Text(String(format: "%.1f%% %@", pct, priceLabel))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: 4, y: y - 8))
        }
    }

    private func drawText(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ opacity: Double) {
        let x = xForBar(d.startPoint.barIndex, size: size)
        let y = yForPrice(d.startPoint.price, size: size)
        let text = Text(d.text ?? "")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color.opacity(opacity))
        ctx.draw(text, at: CGPoint(x: x, y: y))
    }

    private func drawAnchorPoints(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color) {
        let s = d.startPoint
        let sx = xForBar(s.barIndex, size: size)
        let sy = yForPrice(s.price, size: size)
        ctx.fill(Path(ellipseIn: CGRect(x: sx - 4, y: sy - 4, width: 8, height: 8)),
                 with: .color(color))
        if let e = d.endPoint {
            let ex = xForBar(e.barIndex, size: size)
            let ey = yForPrice(e.price, size: size)
            ctx.fill(Path(ellipseIn: CGRect(x: ex - 4, y: ey - 4, width: 8, height: 8)),
                     with: .color(color))
        }
    }

    // MARK: - 配色

    private static func colorFor(_ type: DrawingType) -> Color {
        switch type {
        case .trendLine:       return Color(red: 1.00, green: 0.78, blue: 0.18)  // 黄
        case .horizontalLine:  return Color(red: 0.30, green: 0.78, blue: 1.00)  // 蓝
        case .rectangle:       return Color(red: 0.63, green: 0.42, blue: 0.83)  // 紫
        case .parallelChannel: return Color(red: 0.96, green: 0.27, blue: 0.27)  // 红
        case .fibonacci:       return Color(red: 1.00, green: 0.55, blue: 0.18)  // 橙
        case .text:            return .white
        }
    }

    private func formatPrice(_ p: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: p).doubleValue)
    }
}

#endif
