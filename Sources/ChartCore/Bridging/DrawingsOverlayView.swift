// WP-42 · 画线 SwiftUI Canvas 渲染层（v13.0 · 接 ChartScene drawings 状态）
//
// 职责：
//   - 接收 [Drawing] + bars + viewport + priceRange + 可选 selectedIDs
//   - 用 SwiftUI Canvas 绘制 6 种画线类型（trendLine / horizontalLine / rectangle / parallelChannel / fibonacci / text）
//   - 选中态高亮（线宽 +1.0 · 色彩饱和度提高）· v13.9 升级支持多选
//   - v13.8 渲染优先用 drawing.strokeColorHex / strokeWidth · 缺省回退到类型默认色 + 1.5
//   - allowsHitTesting false（鼠标事件在 ChartScene 内的 onTapGesture / DragGesture 处理 · 这里只渲染）
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
    /// 选中的画线 ID 集合（高亮显示 · 空集表示未选中 · v13.9 多选）
    public let selectedIDs: Set<UUID>
    /// 正在创建中的双点画线（第一点已落 · 第二点未确定 · hover 跟随用 cursorPoint 预览）
    public let pendingDrawing: Drawing?

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        drawings: [Drawing],
        selectedIDs: Set<UUID> = [],
        pendingDrawing: Drawing? = nil
    ) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.drawings = drawings
        self.selectedIDs = selectedIDs
        self.pendingDrawing = pendingDrawing
    }

    /// v13.0~v13.7 单选兼容入口（保留以减少调用方改动 · 内部转 Set）
    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        drawings: [Drawing],
        selectedID: UUID?,
        pendingDrawing: Drawing? = nil
    ) {
        self.init(
            bars: bars,
            viewport: viewport,
            priceRange: priceRange,
            drawings: drawings,
            selectedIDs: selectedID.map { [$0] } ?? [],
            pendingDrawing: pendingDrawing
        )
    }

    public var body: some View {
        Canvas { ctx, size in
            for drawing in drawings {
                draw(drawing, in: ctx, size: size, isSelected: selectedIDs.contains(drawing.id))
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
        // v13.8 优先用 drawing 自定义 · 缺省回退类型默认 · v13.15 叠加 strokeOpacity
        let baseColor = Self.effectiveColor(for: drawing)
        let baseWidth = CGFloat(drawing.strokeWidth ?? 1.5)
        let lineWidth: CGFloat = isSelected ? baseWidth + 1.0 : baseWidth
        let dash: [CGFloat] = isPending ? [4, 3] : []
        let baseOpacity = isPending ? 0.6 : 1.0
        let userOpacity = drawing.strokeOpacity ?? 1.0
        let opacity = baseOpacity * max(0.0, min(1.0, userOpacity))

        switch drawing.type {
        case .trendLine:        drawTrendLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .horizontalLine:   drawHorizontalLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .rectangle:        drawRectangle(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .parallelChannel:  drawParallelChannel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacci:        drawFibonacci(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .text:             drawText(drawing, ctx, size, baseColor, opacity)
        case .ellipse:          drawEllipse(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .ruler:            drawRuler(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .pitchfork:        drawPitchfork(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
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

    /// v13.17 Andrew's Pitchfork · 3 点定中线 + 上下平行轨
    /// 中线方向 = A → midpoint(B, C) · 上轨 = 平行中线过 B · 下轨 = 平行中线过 C
    /// 延伸：取 dx 与 dy 各自到边界的最小 t（确保不超出画布 · 同时包住可见区域）
    private func drawPitchfork(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let upper = d.endPoint,
              let extras = d.extraPoints, let lower = extras.first else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(upper.barIndex, size: size), y: yForPrice(upper.price, size: size))
        let c = CGPoint(x: xForBar(lower.barIndex, size: size), y: yForPrice(lower.price, size: size))
        let midX = (b.x + c.x) / 2
        let midY = (b.y + c.y) / 2
        let dx = midX - a.x
        let dy = midY - a.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return }
        let t = Self.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
        // 中线（粗）
        var centerPath = Path()
        centerPath.move(to: a)
        centerPath.addLine(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
        ctx.stroke(centerPath, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 上轨（次粗）
        var upperPath = Path()
        upperPath.move(to: b)
        upperPath.addLine(to: CGPoint(x: b.x + t * dx, y: b.y + t * dy))
        ctx.stroke(upperPath, with: .color(color.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
        // 下轨（次粗）
        var lowerPath = Path()
        lowerPath.move(to: c)
        lowerPath.addLine(to: CGPoint(x: c.x + t * dx, y: c.y + t * dy))
        ctx.stroke(lowerPath, with: .color(color.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
        // BC 连接线（虚线提示 · 视觉显示 B/C 锚点关系）
        var bcPath = Path()
        bcPath.move(to: b)
        bcPath.addLine(to: c)
        ctx.stroke(bcPath, with: .color(color.opacity(0.3 * opacity)), style: StrokeStyle(lineWidth: width * 0.5, dash: [3, 2]))
    }

    /// v13.14 测量工具渲染 · 两点定线段（虚线连接）+ 中点标签显示 价格差 / 百分比 / bar 数
    private func drawRuler(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let s = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let e = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        // 虚线连接（强制虚线 · 与 trendLine 区分 · 无论是否 pending）
        var path = Path()
        path.move(to: s)
        path.addLine(to: e)
        let rulerDash: [CGFloat] = dash.isEmpty ? [3, 2] : dash
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: rulerDash))
        // 中点标签（价格差 / 百分比 / bar 数）
        let startPrice = NSDecimalNumber(decimal: d.startPoint.price).doubleValue
        let endPrice = NSDecimalNumber(decimal: end.price).doubleValue
        let priceDiff = endPrice - startPrice
        let pct = startPrice > 0 ? priceDiff / startPrice * 100 : 0
        let bars = end.barIndex - d.startPoint.barIndex
        let label = String(format: "%+.2f (%+.2f%%) · %d bar", priceDiff, pct, bars)
        let mid = CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2 - 10)
        let text = Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(color.opacity(opacity))
        ctx.draw(text, at: mid)
    }

    /// v13.13 椭圆渲染 · 对角两点定外接矩形 · 内接椭圆 · 半透明填充 + 描边
    private func drawEllipse(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let x1 = xForBar(d.startPoint.barIndex, size: size)
        let x2 = xForBar(end.barIndex, size: size)
        let y1 = yForPrice(d.startPoint.price, size: size)
        let y2 = yForPrice(end.price, size: size)
        let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        let path = Path(ellipseIn: rect)
        ctx.fill(path, with: .color(color.opacity(0.08 * opacity)))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func drawText(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ opacity: Double) {
        let x = xForBar(d.startPoint.barIndex, size: size)
        let y = yForPrice(d.startPoint.price, size: size)
        // v13.12 字体大小 · v13.26 加粗 / 斜体（用 .system + weight + italic modifier）
        let fs = CGFloat(d.fontSize ?? 12)
        let weight: Font.Weight = (d.isBold == true) ? .bold : .regular
        var text = Text(d.text ?? "")
            .font(.system(size: fs, weight: weight, design: .monospaced))
            .foregroundColor(color.opacity(opacity))
        if d.isItalic == true {
            text = text.italic()
        }
        ctx.draw(text, at: CGPoint(x: x, y: y))
    }

    private func drawAnchorPoints(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color) {
        let s = d.startPoint
        let sx = xForBar(s.barIndex, size: size)
        let sy = yForPrice(s.price, size: size)
        drawAnchorMarker(at: CGPoint(x: sx, y: sy), in: ctx, color: color, locked: d.locked)
        if let e = d.endPoint {
            let ex = xForBar(e.barIndex, size: size)
            let ey = yForPrice(e.price, size: size)
            drawAnchorMarker(at: CGPoint(x: ex, y: ey), in: ctx, color: color, locked: d.locked)
        }
        // v13.17 extraPoints anchor 也画（Pitchfork 第 3 点 / 多边形其余点）
        if let extras = d.extraPoints {
            for p in extras {
                let px = xForBar(p.barIndex, size: size)
                let py = yForPrice(p.price, size: size)
                drawAnchorMarker(at: CGPoint(x: px, y: py), in: ctx, color: color, locked: d.locked)
            }
        }
    }

    /// v13.11 锁定的 anchor 用小锁图标 · 否则圆点
    private func drawAnchorMarker(at p: CGPoint, in ctx: GraphicsContext, color: Color, locked: Bool) {
        if locked {
            // SF Symbol "lock.fill" 居中绘制
            let lockText = Text(Image(systemName: "lock.fill"))
                .font(.system(size: 11))
                .foregroundColor(color)
            ctx.draw(lockText, at: p)
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                     with: .color(color))
        }
    }

    // MARK: - 配色

    /// v13.8 优先解析 drawing.strokeColorHex · 失败回退到 colorFor(type) 默认色
    public static func effectiveColor(for drawing: Drawing) -> Color {
        if let hex = drawing.strokeColorHex, let c = Self.colorFromHex(hex) {
            return c
        }
        return colorFor(drawing.type)
    }

    public static func colorFor(_ type: DrawingType) -> Color {
        switch type {
        case .trendLine:       return Color(red: 1.00, green: 0.78, blue: 0.18)  // 黄
        case .horizontalLine:  return Color(red: 0.30, green: 0.78, blue: 1.00)  // 蓝
        case .rectangle:       return Color(red: 0.63, green: 0.42, blue: 0.83)  // 紫
        case .parallelChannel: return Color(red: 0.96, green: 0.27, blue: 0.27)  // 红
        case .fibonacci:       return Color(red: 1.00, green: 0.55, blue: 0.18)  // 橙
        case .text:            return .white
        case .ellipse:         return Color(red: 0.18, green: 0.83, blue: 0.74)  // 青（v13.13）
        case .ruler:           return Color(red: 0.96, green: 0.69, blue: 0.18)  // 金（v13.14）
        case .pitchfork:       return Color(red: 0.45, green: 0.78, blue: 0.42)  // 草绿（v13.17）
        }
    }

    /// v13.17 Pitchfork 延伸 scale · 从 a 出发沿 (dx,dy) 找最近的 [0,size] 边界
    /// 至少返回 1.0（保证至少超过 mid 点 · 不向内缩）· 同时考虑 dx/dy 取先到边界者
    public static func pitchforkExtensionScale(a: CGPoint, dx: CGFloat, dy: CGFloat, size: CGSize) -> CGFloat {
        var candidates: [CGFloat] = []
        if abs(dx) > 0.0001 {
            candidates.append(dx > 0 ? (size.width - a.x) / dx : -a.x / dx)
        }
        if abs(dy) > 0.0001 {
            candidates.append(dy > 0 ? (size.height - a.y) / dy : -a.y / dy)
        }
        let bound = candidates.filter { $0 > 0 }.min() ?? 1
        return max(1, bound)
    }

    /// 解析 6 位 RGB hex（不含 # · 大小写均可）· 失败返回 nil
    public static func colorFromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func formatPrice(_ p: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: p).doubleValue)
    }
}

#endif
