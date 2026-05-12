// WP-42 · 画线 SwiftUI Canvas 渲染层（v13.0 · 接 ChartScene drawings 状态）
//
// 职责：
//   - 接收 [Drawing] + bars + viewport + priceRange + 可选 selectedIDs
//   - 用 SwiftUI Canvas 绘制 22 种画线类型（v17.18 后）：
//     trendLine / horizontalLine / verticalLine / priceLabel / ray / arrow / rectangle / parallelChannel / channel / fibonacci / fibonacciExtension / fibonacciArc / fibonacciChannel / text /
//     ellipse / ruler / pitchfork / polygon /
//     fibonacciFan / priceZone / gannFan / fibonacciTimeZone
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
    /// v15.10 .text 类型缺省色（无 strokeColorHex 时跟主图主题切换）· 默认 .white 保旧调用兼容
    public let textDefaultColor: Color
    /// v17.100 · 价格小数位（PricePrecisionMode + 合约 priceTick · 默认 2 保旧兼容）
    public let priceDigits: Int

    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        drawings: [Drawing],
        selectedIDs: Set<UUID> = [],
        pendingDrawing: Drawing? = nil,
        textDefaultColor: Color = .white,
        priceDigits: Int = 2
    ) {
        self.bars = bars
        self.viewport = viewport
        self.priceRange = priceRange
        self.drawings = drawings
        self.selectedIDs = selectedIDs
        self.pendingDrawing = pendingDrawing
        self.textDefaultColor = textDefaultColor
        self.priceDigits = priceDigits
    }

    /// v13.0~v13.7 单选兼容入口（保留以减少调用方改动 · 内部转 Set）
    public init(
        bars: [KLine],
        viewport: RenderViewport,
        priceRange: ClosedRange<Decimal>,
        drawings: [Drawing],
        selectedID: UUID?,
        pendingDrawing: Drawing? = nil,
        textDefaultColor: Color = .white,
        priceDigits: Int = 2
    ) {
        self.init(
            bars: bars,
            viewport: viewport,
            priceRange: priceRange,
            drawings: drawings,
            selectedIDs: selectedID.map { [$0] } ?? [],
            pendingDrawing: pendingDrawing,
            textDefaultColor: textDefaultColor,
            priceDigits: priceDigits
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
        // 配色优先级：用户自定义 hex > .text 类型用主题色 > 类型默认（语义色）· 叠加 strokeOpacity
        let baseColor: Color = {
            if let hex = drawing.strokeColorHex, let c = Self.colorFromHex(hex) { return c }
            if drawing.type == .text { return textDefaultColor }
            return Self.colorFor(drawing.type)
        }()
        let baseWidth = CGFloat(drawing.strokeWidth ?? 1.5)
        let lineWidth: CGFloat = isSelected ? baseWidth + 1.0 : baseWidth
        let dash: [CGFloat] = isPending ? [4, 3] : []
        let baseOpacity = isPending ? 0.6 : 1.0
        let userOpacity = drawing.strokeOpacity ?? 1.0
        let opacity = baseOpacity * max(0.0, min(1.0, userOpacity))

        switch drawing.type {
        case .trendLine:        drawTrendLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .horizontalLine:   drawHorizontalLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .verticalLine:     drawVerticalLine(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .priceLabel:       drawPriceLabel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .ray:              drawRay(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .arrow:            drawArrow(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .rectangle:        drawRectangle(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .parallelChannel:  drawParallelChannel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .channel:          drawChannel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacci:        drawFibonacci(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacciExtension: drawFibonacciExtension(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacciArc:     drawFibonacciArc(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacciChannel: drawFibonacciChannel(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .text:             drawText(drawing, ctx, size, baseColor, opacity)
        case .ellipse:          drawEllipse(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .ruler:            drawRuler(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .pitchfork:        drawPitchfork(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .polygon:          drawPolygon(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacciFan:     drawFibonacciFan(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .priceZone:        drawPriceZone(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .gannFan:          drawGannFan(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .fibonacciTimeZone:drawFibonacciTimeZone(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .gannAngle:        drawGannAngle(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .gannSquare:       drawGannSquare(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .gannBox:          drawGannBox(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
        case .elliottImpulse:   drawElliottWave(drawing, ctx, size, baseColor, lineWidth, dash, opacity, labels: ["0", "1", "2", "3", "4", "5"])
        case .elliottCorrection:drawElliottWave(drawing, ctx, size, baseColor, lineWidth, dash, opacity, labels: ["0", "A", "B", "C"])
        case .fibonacciSpiral:  drawFibonacciSpiral(drawing, ctx, size, baseColor, lineWidth, dash, opacity)
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

    /// v17.8 A3.4 · 垂直线（时间锚点 · 单点 barIndex 决定位置 · 横跨整个价格区间）
    private func drawVerticalLine(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        let x = xForBar(d.startPoint.barIndex, size: size)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    /// v17.15 A5.3 · 价格标签（水平虚线 + 右侧填充 chip 显示价格 · 可选用户 label）
    /// 比 horizontalLine 视觉更醒目（chip 填充背景）· trader 一眼可见关键支撑/阻力价位
    private func drawPriceLabel(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        let y = yForPrice(d.startPoint.price, size: size)
        // 水平细虚线（视觉比 horizontalLine 弱 · 强调右侧 chip）
        let lineDash: [CGFloat] = dash.isEmpty ? [3, 3] : dash
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y))
        ctx.stroke(line, with: .color(color.opacity(0.65 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: lineDash))
        // chip 文字（价格 + 可选 label）· 估算宽度：每字 7pt + 8pt padding
        let priceStr = formatPrice(d.startPoint.price)
        let chipText: String = {
            if let label = d.text, !label.isEmpty { return "\(label) \(priceStr)" }
            return priceStr
        }()
        let textWidth = CGFloat(chipText.count) * 7 + 16
        let chipHeight: CGFloat = 18
        let chipRect = CGRect(x: size.width - textWidth - 4, y: y - chipHeight / 2, width: textWidth, height: chipHeight)
        let bg = Path(roundedRect: chipRect, cornerRadius: 3)
        ctx.fill(bg, with: .color(color.opacity(opacity)))
        let text = Text(chipText)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
        ctx.draw(text, at: CGPoint(x: chipRect.midX, y: chipRect.midY))
    }

    /// v17.14 A5.2 · 箭头（start → end 线段 + 末端实心三角头 · 信号标记 / 复盘标注）
    private func drawArrow(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return }
        let ux = dx / length, uy = dy / length
        let arrowSize: CGFloat = max(10, width * 6)
        let halfWidth: CGFloat = arrowSize * 0.45
        // 线段截短到三角底（避免线穿过箭头）
        let lineEnd = CGPoint(x: b.x - ux * arrowSize, y: b.y - uy * arrowSize)
        var linePath = Path()
        linePath.move(to: a)
        linePath.addLine(to: lineEnd)
        ctx.stroke(linePath, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 三角头：tip=b · base 两翼
        let px = -uy * halfWidth, py = ux * halfWidth
        let wing1 = CGPoint(x: lineEnd.x + px, y: lineEnd.y + py)
        let wing2 = CGPoint(x: lineEnd.x - px, y: lineEnd.y - py)
        var head = Path()
        head.move(to: b); head.addLine(to: wing1); head.addLine(to: wing2); head.closeSubpath()
        ctx.fill(head, with: .color(color.opacity(opacity)))
    }

    /// v17.10 A3.2 · 射线（两点定方向 · 从 start 出发经 end 延伸到画布边界 · 复用 pitchforkExtensionScale）
    private func drawRay(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return }
        let t = Self.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
        var path = Path()
        path.move(to: a)
        path.addLine(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
    }

    /// v17.11 A3.1 · 通道线（线性回归 + ±1σ 平行线 · 自动等距 · 主线实线 + 上下虚线 + 半透明填充）
    /// 两点 barIndex 定 range（价格忽略）· 内部对 bars[startBar..endBar].close 做最小二乘
    private func drawChannel(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let startBar = min(d.startPoint.barIndex, end.barIndex)
        let endBar = max(d.startPoint.barIndex, end.barIndex)
        guard endBar > startBar, startBar >= 0, endBar < bars.count else { return }
        let closes = bars[startBar...endBar].map { $0.close }
        guard let reg = DrawingGeometry.channelRegression(closes: closes) else { return }
        let n = closes.count
        let yStartPrice = reg.intercept
        let yEndPrice = reg.slope * Double(n - 1) + reg.intercept
        // 屏幕坐标
        let hi = NSDecimalNumber(decimal: priceRange.upperBound).doubleValue
        let lo = NSDecimalNumber(decimal: priceRange.lowerBound).doubleValue
        let span = max(0.0001, hi - lo)
        func yScreen(_ price: Double) -> CGFloat { CGFloat((hi - price) / span) * size.height }
        let xS = xForBar(startBar, size: size)
        let xE = xForBar(endBar, size: size)
        let mainS = CGPoint(x: xS, y: yScreen(yStartPrice))
        let mainE = CGPoint(x: xE, y: yScreen(yEndPrice))
        let upS = CGPoint(x: xS, y: yScreen(yStartPrice + reg.stdDev))
        let upE = CGPoint(x: xE, y: yScreen(yEndPrice + reg.stdDev))
        let dnS = CGPoint(x: xS, y: yScreen(yStartPrice - reg.stdDev))
        let dnE = CGPoint(x: xE, y: yScreen(yEndPrice - reg.stdDev))
        // 半透明填充（上下 1σ 之间）
        var fill = Path()
        fill.move(to: upS); fill.addLine(to: upE); fill.addLine(to: dnE); fill.addLine(to: dnS); fill.closeSubpath()
        ctx.fill(fill, with: .color(color.opacity(0.08 * opacity)))
        // 主线实线
        var mainPath = Path()
        mainPath.move(to: mainS); mainPath.addLine(to: mainE)
        ctx.stroke(mainPath, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 上下平行线（虚线 · 细 0.8x）
        let bandDash: [CGFloat] = dash.isEmpty ? [3, 2] : dash
        var bandPath = Path()
        bandPath.move(to: upS); bandPath.addLine(to: upE)
        bandPath.move(to: dnS); bandPath.addLine(to: dnE)
        ctx.stroke(bandPath, with: .color(color.opacity(0.75 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: bandDash))
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

    /// v17.18 A4.5 · 斐波通道 · 两点主轴 + offset 副线 · 内部 7 fib 比例平行线（含 0% 主线 / 100% 副线 + 5 内层）
    private func drawFibonacciChannel(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint, let offset = d.channelOffset else { return }
        let levels = FibonacciLevels.standard
        for (i, ratio) in levels.enumerated() {
            let priceShift = offset * ratio
            let lineS = CGPoint(x: xForBar(d.startPoint.barIndex, size: size),
                                y: yForPrice(d.startPoint.price + priceShift, size: size))
            let lineE = CGPoint(x: xForBar(end.barIndex, size: size),
                                y: yForPrice(end.price + priceShift, size: size))
            // 0% 和 100% 主轴 + 副线实线（端点）· 中间 fib 虚线
            let isEdge = (ratio == 0 || ratio == 1)
            let lineDash: [CGFloat] = isEdge ? dash : (dash.isEmpty ? [3, 2] : dash)
            let lineOpacity: Double = isEdge ? opacity : 0.65 * opacity
            let strokeWidth: CGFloat = isEdge ? width : width * 0.7
            var path = Path()
            path.move(to: lineS); path.addLine(to: lineE)
            ctx.stroke(path, with: .color(color.opacity(lineOpacity)), style: StrokeStyle(lineWidth: strokeWidth, dash: lineDash))
            // 右端 ratio 标签
            let pct = NSDecimalNumber(decimal: ratio).doubleValue * 100
            let label = Text(String(format: "%.1f%%", pct))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(label, at: CGPoint(x: lineE.x - 24, y: lineE.y - 8))
            _ = i
        }
    }

    /// v17.17 A4.3 · 斐波弧 · 圆心 = A · 基准半径 = ||AB||（屏幕距离）· 3 个 fib 比例的半圆弧
    /// 半圆方向：朝向 B 所在象限（沿 AB 方向延伸的 180°）· 用 Path.addArc
    private func drawFibonacciArc(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let center = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let endPt = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let baseR = ((endPt.x - center.x) * (endPt.x - center.x) + (endPt.y - center.y) * (endPt.y - center.y)).squareRoot()
        guard baseR > 0.5 else { return }
        // 半圆起止角：沿 AB 方向 · ±90°（180°半圆 · 朝 B 一侧展开）
        let baseAngle = atan2(endPt.y - center.y, endPt.x - center.x)
        let startAngle = baseAngle - .pi / 2
        let endAngle = baseAngle + .pi / 2
        let levels = FibonacciLevels.fanCore  // 38.2 / 50 / 61.8
        // 0% / 100% 中心虚线（视觉参考 · 短线段不绘 · 仅画 fib 弧）
        for (i, ratio) in levels.enumerated() {
            let r = baseR * CGFloat(NSDecimalNumber(decimal: ratio).doubleValue)
            var path = Path()
            path.addArc(center: center, radius: r, startAngle: Angle(radians: startAngle), endAngle: Angle(radians: endAngle), clockwise: false)
            ctx.stroke(path, with: .color(color.opacity(0.75 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
            // 弧顶 label（沿 baseAngle 方向）· r × (cos, sin)
            let labelX = center.x + r * CGFloat(cos(baseAngle))
            let labelY = center.y + r * CGFloat(sin(baseAngle))
            let pct = NSDecimalNumber(decimal: ratio).doubleValue * 100
            let label = Text(String(format: "%.1f%%", pct))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(label, at: CGPoint(x: labelX, y: labelY))
            _ = i
        }
        // AB 半径线（实线 · 视觉参考）
        var radialPath = Path()
        radialPath.move(to: center); radialPath.addLine(to: endPt)
        ctx.stroke(radialPath, with: .color(color.opacity(0.4 * opacity)), style: StrokeStyle(lineWidth: width * 0.6, dash: [3, 2]))
    }

    /// v17.136 · 斐波那契螺旋 / 黄金螺旋 · 5 段 1/4 弧按 fib 数列扩展（半径 1/1/2/3/5/8 单位）
    /// 中心 A = startPoint · 起始半径 r = ||AB|| 的屏幕距离 · 初始方向由 AB 角度决定（朝 B 那一象限作 1/4 弧起点）
    /// 5 段 1/4 弧依次扩展 · 每段半径 = 上段半径 + 上上段半径（fib 递推）· 起点首尾相连
    private func drawFibonacciSpiral(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let center = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let endPt = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let baseR = ((endPt.x - center.x) * (endPt.x - center.x) + (endPt.y - center.y) * (endPt.y - center.y)).squareRoot()
        guard baseR > 0.5 else { return }
        // 初始方向角（朝 B 方向）· 1/4 弧从此角度起 · 旋转 90° 到下一段
        // 标准 fib 螺旋：弧心按 1/1/2/3/5/8 顺时针/逆时针螺旋扩展 · 每段弧心是上段弧心 + (向上/向下/向左/向右) × prevR
        let baseAngle = atan2(endPt.y - center.y, endPt.x - center.x)
        // 6 段半径 fib · 第 0 段起始半径 = baseR · 后续按 fib 递推
        let radii: [CGFloat] = [1, 1, 2, 3, 5, 8].map { baseR * CGFloat($0) }
        // 弧心初始 = center · 每段后弧心沿当前 baseAngle + (i * 90°) 方向移动 prevR 距离（保持螺旋首尾相切）
        var arcCenter = center
        var path = Path()
        for i in 0..<radii.count {
            let r = radii[i]
            // 当前 1/4 弧的角度范围：从 (baseAngle + i*90°) 起 · 逆时针扩展 90°
            let segStart = baseAngle + CGFloat(i) * .pi / 2
            let segEnd = segStart + .pi / 2
            // 1/4 弧起点（与上段终点重合 · 保持首尾相切）
            let p0 = CGPoint(x: arcCenter.x + r * cos(segStart), y: arcCenter.y + r * sin(segStart))
            if i == 0 {
                path.move(to: p0)
            }
            // 绘制 1/4 弧 · 简化用 8 段 cubic 近似 SwiftUI Path.addArc
            var arc = Path()
            arc.move(to: p0)
            arc.addArc(center: arcCenter, radius: r, startAngle: Angle(radians: segStart), endAngle: Angle(radians: segEnd), clockwise: false)
            ctx.stroke(arc, with: .color(color.opacity(0.85 * opacity)), style: StrokeStyle(lineWidth: width, dash: dash, lineCap: .round))
            // 标号（弧中点）· 显示 fib 半径数
            let labelAngle = (segStart + segEnd) / 2
            let labelR = r * 0.7
            let labelPt = CGPoint(x: arcCenter.x + labelR * cos(labelAngle), y: arcCenter.y + labelR * sin(labelAngle))
            let fibNum = [1, 1, 2, 3, 5, 8][i]
            let label = Text("\(fibNum)").font(.system(size: 9, design: .monospaced)).foregroundColor(color)
            ctx.draw(label, at: labelPt)
            // 下段弧心：当前弧心沿 segEnd 方向移动 r（保证 segEnd 点在下段弧上 · 半径 = r * fib_next/fib_curr）
            // 但简化处理：弧心沿 segEnd 方向位移 r · 让下段弧起点 == 当前弧终点
            arcCenter = CGPoint(x: arcCenter.x + r * cos(segEnd), y: arcCenter.y + r * sin(segEnd))
        }
        // 中心点标识
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)),
                 with: .color(color.opacity(0.6 * opacity)))
    }

    /// v17.16 A4.1 · 斐波扩展 · 突破后目标位（all ratios > 1.0 · 1.0 = B 锚 · 1.272/1.414/1.618/2/2.618 = projection）
    private func drawFibonacciExtension(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard d.endPoint != nil else { return }
        let prices = DrawingGeometry.fibonacciExtensionPrices(for: d)
        let levels = FibonacciLevels.projection
        for (i, price) in prices.enumerated() {
            let y = yForPrice(price, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            // 1.0（B 锚）实线 · 其余虚线（区分主锚 / 外推目标）
            let isAnchor = (levels[i] == 1)
            let lineDash: [CGFloat] = isAnchor ? dash : (dash.isEmpty ? [4, 3] : dash)
            ctx.stroke(path, with: .color(color.opacity((isAnchor ? 0.9 : 0.7) * opacity)),
                       style: StrokeStyle(lineWidth: width * (isAnchor ? 1.0 : 0.8), dash: lineDash))
            let pct = NSDecimalNumber(decimal: levels[i]).doubleValue * 100
            let priceLabel = formatPrice(price)
            let text = Text(String(format: "%.1f%% %@", pct, priceLabel))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: 4, y: y - 8))
        }
    }

    /// v15.90 斐波那契时间区 · 8 条全图垂直线（F1/F2/F3/F5/F8/F13/F21/F34）· 顶部 label
    private func drawFibonacciTimeZone(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        let bars = DrawingGeometry.fibonacciTimeZoneBars(for: d)
        let sequence = FibonacciSequence.standard
        for (i, bar) in bars.enumerated() {
            let x = xForBar(bar, size: size)
            // 超出可见范围跳过（仍保留几何含义 · 仅不画）
            if x < 0 || x > size.width { continue }
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(path, with: .color(color.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
            let label = "F\(sequence[i])"
            let text = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: x + 12, y: 12))
        }
    }

    /// v15.89 江恩扇形 · 两点定 1×1 单位 · 9 角度射线（1×8 → 1×1 → 8×1）· 1×1 主线加粗
    private func drawGannFan(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let unitDx = b.x - a.x
        let unitDy = b.y - a.y
        guard abs(unitDx) > 0.0001 else { return }
        for angle in GannAngles.standard {
            let ratio = CGFloat(angle.num) / CGFloat(angle.den)
            let dx = unitDx
            let dy = unitDy * ratio
            guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { continue }
            let t = Self.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
            let rayEnd = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            var ray = Path()
            ray.move(to: a)
            ray.addLine(to: rayEnd)
            // 1×1 主线加粗 + 全不透明 · 其他细 + 半透明
            let isMain = (angle.num == 1 && angle.den == 1)
            let strokeWidth = isMain ? width : width * 0.7
            let strokeOpacity = isMain ? opacity : 0.55 * opacity
            ctx.stroke(ray, with: .color(color.opacity(strokeOpacity)), style: StrokeStyle(lineWidth: strokeWidth, dash: dash))
            // 角度标签（紧贴射线末端）
            let labelText = Text(angle.label)
                .font(.system(size: 9, weight: isMain ? .semibold : .regular, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(labelText, at: CGPoint(x: rayEnd.x - 14, y: rayEnd.y - 6))
        }
    }

    /// v17.126 · 江恩 1×1 单角度线 · 两点定 1×1 单位（dx bar = dy price）· 单条主角度射线从 start 延伸到画布边界
    private func drawGannAngle(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { return }
        let t = Self.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
        let rayEnd = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        var path = Path()
        path.move(to: a)
        path.addLine(to: rayEnd)
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 1×1 标签紧贴射线末端
        let label = Text("1×1")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
        ctx.draw(label, at: CGPoint(x: rayEnd.x - 14, y: rayEnd.y - 6))
    }

    /// v17.128 · 艾略特浪 · N 点开口折线 + 锚点圆 + 标号（0/1/2/3/4/5 或 0/A/B/C）· 复用 5 浪 + ABC 同一渲染
    private func drawElliottWave(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double, labels: [String]) {
        guard let extras = d.extraPoints, !extras.isEmpty else { return }
        let allPoints = [d.startPoint] + extras
        let screenPts = allPoints.map { CGPoint(x: xForBar($0.barIndex, size: size), y: yForPrice($0.price, size: size)) }
        guard screenPts.count >= 2 else { return }
        // 开口折线（不闭合 · 不连首尾）
        var linePath = Path()
        linePath.move(to: screenPts[0])
        for i in 1..<screenPts.count {
            linePath.addLine(to: screenPts[i])
        }
        ctx.stroke(linePath, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 各锚点小圆 + 标号
        for (idx, pt) in screenPts.enumerated() {
            let r: CGFloat = 3
            let circle = Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            ctx.fill(circle, with: .color(color.opacity(opacity)))
            // 标号（idx 内取 labels[idx] 或回退 idx 字符串）
            let label = idx < labels.count ? labels[idx] : String(idx)
            // 标号偏移：奇数点上偏 / 偶数点下偏（避免与折线重叠）
            let yOffset: CGFloat = (idx % 2 == 0) ? -14 : 10
            let text = Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: pt.x, y: pt.y + yOffset))
        }
    }

    /// v17.127 · 江恩盒 · 两点定对角矩形 · 矩形 + 内部 5×5 等分网格（4 横 + 4 竖）+ 2 对角线 · 江恩派 time-price 分析核心框架
    private func drawGannBox(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let xMin = min(a.x, b.x), xMax = max(a.x, b.x)
        let yMin = min(a.y, b.y), yMax = max(a.y, b.y)
        let rect = CGRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin)
        // 外框
        ctx.stroke(Path(rect), with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 内部 5×5 均分线（1/5 ~ 4/5）
        var gridPath = Path()
        for k in 1...4 {
            let x = xMin + (xMax - xMin) * CGFloat(k) / 5
            let y = yMin + (yMax - yMin) * CGFloat(k) / 5
            gridPath.move(to: CGPoint(x: x, y: yMin))
            gridPath.addLine(to: CGPoint(x: x, y: yMax))
            gridPath.move(to: CGPoint(x: xMin, y: y))
            gridPath.addLine(to: CGPoint(x: xMax, y: y))
        }
        ctx.stroke(gridPath, with: .color(color.opacity(0.45 * opacity)), style: StrokeStyle(lineWidth: width * 0.6, dash: dash))
        // 2 对角线（trader 看 time × price 角度）
        var diagPath = Path()
        diagPath.move(to: CGPoint(x: xMin, y: yMin))
        diagPath.addLine(to: CGPoint(x: xMax, y: yMax))
        diagPath.move(to: CGPoint(x: xMin, y: yMax))
        diagPath.addLine(to: CGPoint(x: xMax, y: yMin))
        ctx.stroke(diagPath, with: .color(color.opacity(0.75 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
    }

    /// v17.126 · 江恩九方 · 两点定对角矩形 · 矩形边 + 内部 2 横 + 2 竖（1/3, 2/3）= 3×3 网格 · time×price 均分
    private func drawGannSquare(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let b = CGPoint(x: xForBar(end.barIndex, size: size), y: yForPrice(end.price, size: size))
        let xMin = min(a.x, b.x), xMax = max(a.x, b.x)
        let yMin = min(a.y, b.y), yMax = max(a.y, b.y)
        let rect = CGRect(x: xMin, y: yMin, width: xMax - xMin, height: yMax - yMin)
        // 外框
        ctx.stroke(Path(rect), with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, dash: dash))
        // 内部 3×3 均分线 · 1/3 + 2/3
        let xs = [xMin + (xMax - xMin) / 3, xMin + (xMax - xMin) * 2 / 3]
        let ys = [yMin + (yMax - yMin) / 3, yMin + (yMax - yMin) * 2 / 3]
        var gridPath = Path()
        for x in xs {
            gridPath.move(to: CGPoint(x: x, y: yMin))
            gridPath.addLine(to: CGPoint(x: x, y: yMax))
        }
        for y in ys {
            gridPath.move(to: CGPoint(x: xMin, y: y))
            gridPath.addLine(to: CGPoint(x: xMax, y: y))
        }
        ctx.stroke(gridPath, with: .color(color.opacity(0.55 * opacity)), style: StrokeStyle(lineWidth: width * 0.7, dash: dash))
    }

    /// v15.88 价格区域 · 上下两价格定带宽 · 全图横跨 · 半透明填充 + 上下边线 + 双价格标签
    private func drawPriceZone(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let bounds = DrawingGeometry.priceZoneBounds(of: d) else { return }
        let yUpper = yForPrice(bounds.upper, size: size)
        let yLower = yForPrice(bounds.lower, size: size)
        // 半透明填充
        let rect = CGRect(x: 0, y: yUpper, width: size.width, height: yLower - yUpper)
        ctx.fill(Path(rect), with: .color(color.opacity(0.12 * opacity)))
        // 上下边线
        var path = Path()
        path.move(to: CGPoint(x: 0, y: yUpper)); path.addLine(to: CGPoint(x: size.width, y: yUpper))
        path.move(to: CGPoint(x: 0, y: yLower)); path.addLine(to: CGPoint(x: size.width, y: yLower))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
        // 双价格标签（左上 / 左下）
        let upperText = Text(formatPrice(bounds.upper))
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(color)
        let lowerText = Text(formatPrice(bounds.lower))
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(color)
        ctx.draw(upperText, at: CGPoint(x: 4, y: yUpper - 8))
        ctx.draw(lowerText, at: CGPoint(x: 4, y: yLower + 8))
    }

    /// v15.87 斐波那契扇形 · 从 startPoint 发射 3 条核心 fib 射线（38.2/50/61.8）
    /// 每条射线终点 = (end.barIndex, p0 + level × span) · 复用 pitchforkExtensionScale 延伸到画布边界
    private func drawFibonacciFan(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let end = d.endPoint else { return }
        let a = CGPoint(x: xForBar(d.startPoint.barIndex, size: size), y: yForPrice(d.startPoint.price, size: size))
        let endX = xForBar(end.barIndex, size: size)
        let levels = FibonacciLevels.fanCore
        let prices = DrawingGeometry.fibonacciFanTargetPrices(for: d, levels: levels)
        // 0% / 100% 锚虚线（视觉提示双锚 · 不画 0 和 100 射线 · 因等同 trendLine）
        var basePath = Path()
        basePath.move(to: a)
        basePath.addLine(to: CGPoint(x: endX, y: yForPrice(end.price, size: size)))
        ctx.stroke(basePath, with: .color(color.opacity(0.35 * opacity)), style: StrokeStyle(lineWidth: width * 0.6, dash: [3, 2]))
        // 3 条核心 fib 射线 · 起点 a · 经过 (endX, levelPrice) · 延伸到画布边界
        for (i, price) in prices.enumerated() {
            let target = CGPoint(x: endX, y: yForPrice(price, size: size))
            let dx = target.x - a.x
            let dy = target.y - a.y
            guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else { continue }
            let t = Self.pitchforkExtensionScale(a: a, dx: dx, dy: dy, size: size)
            var ray = Path()
            ray.move(to: a)
            ray.addLine(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
            ctx.stroke(ray, with: .color(color.opacity(0.75 * opacity)), style: StrokeStyle(lineWidth: width * 0.8, dash: dash))
            // level 标签 · 紧挨射线 endX 处（target 点旁）
            let pct = NSDecimalNumber(decimal: levels[i]).doubleValue * 100
            let label = String(format: "%.1f%%", pct)
            let text = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color)
            ctx.draw(text, at: CGPoint(x: target.x + 18, y: target.y))
        }
    }

    /// v13.31 多边形渲染 · 闭合 N 点 + 半透明填充 + 描边
    /// startPoint = 第 1 点 · extraPoints = 第 2~N 点 · 闭合到 startPoint
    private func drawPolygon(_ d: Drawing, _ ctx: GraphicsContext, _ size: CGSize, _ color: Color, _ width: CGFloat, _ dash: [CGFloat], _ opacity: Double) {
        guard let extras = d.extraPoints, !extras.isEmpty else { return }
        let allPoints = [d.startPoint] + extras
        var path = Path()
        let first = CGPoint(x: xForBar(allPoints[0].barIndex, size: size), y: yForPrice(allPoints[0].price, size: size))
        path.move(to: first)
        for p in allPoints.dropFirst() {
            path.addLine(to: CGPoint(x: xForBar(p.barIndex, size: size), y: yForPrice(p.price, size: size)))
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(color.opacity(0.10 * opacity)))
        ctx.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineJoin: .round, dash: dash))
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
        let label = String(format: "%+.\(priceDigits)f (%+.2f%%) · %d bar", priceDiff, pct, bars)
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
        // v13.12 字体大小 · v13.26 加粗 / 斜体 · v13.35 下划线
        let fs = CGFloat(d.fontSize ?? 12)
        let weight: Font.Weight = (d.isBold == true) ? .bold : .regular
        var text = Text(d.text ?? "")
            .font(.system(size: fs, weight: weight, design: .monospaced))
            .foregroundColor(color.opacity(opacity))
        if d.isItalic == true {
            text = text.italic()
        }
        if d.isUnderline == true {
            text = text.underline()
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

    public static func colorFor(_ type: DrawingType) -> Color {
        switch type {
        case .trendLine:       return Color(red: 1.00, green: 0.78, blue: 0.18)  // 黄
        case .horizontalLine:  return Color(red: 0.30, green: 0.78, blue: 1.00)  // 蓝
        case .verticalLine:    return Color(red: 0.30, green: 0.78, blue: 1.00)  // 蓝（v17.8 · 与 horizontalLine 同色 · 概念对称）
        case .priceLabel:      return Color(red: 0.20, green: 0.60, blue: 0.95)  // 深蓝（v17.15 · chip 填充醒目）
        case .ray:             return Color(red: 0.72, green: 0.93, blue: 0.30)  // 嫩绿（v17.10 · 与 trendLine 黄区分）
        case .arrow:           return Color(red: 1.00, green: 0.45, blue: 0.20)  // 橙红（v17.14 · 信号醒目 · 与 fibonacci 橙区分）
        case .rectangle:       return Color(red: 0.63, green: 0.42, blue: 0.83)  // 紫
        case .parallelChannel: return Color(red: 0.96, green: 0.27, blue: 0.27)  // 红
        case .channel:         return Color(red: 0.95, green: 0.55, blue: 0.85)  // 粉紫（v17.11 · 回归通道 · 与 parallelChannel 红区分）
        case .fibonacci:       return Color(red: 1.00, green: 0.55, blue: 0.18)  // 橙
        case .fibonacciExtension: return Color(red: 0.95, green: 0.78, blue: 0.30)  // 金黄（v17.16 · 与 fibonacci 橙互补 · 同语义不同方向）
        case .fibonacciArc:    return Color(red: 1.00, green: 0.70, blue: 0.35)     // 杏橙（v17.17 · fib 系族同色调 · 偏暖）
        case .fibonacciChannel: return Color(red: 0.95, green: 0.45, blue: 0.55)    // 桃红（v17.18 · fib 系族 · 与 parallelChannel 红/橙系区分）
        case .text:            return .white
        case .ellipse:         return Color(red: 0.18, green: 0.83, blue: 0.74)  // 青（v13.13）
        case .ruler:           return Color(red: 0.96, green: 0.69, blue: 0.18)  // 金（v13.14）
        case .pitchfork:       return Color(red: 0.45, green: 0.78, blue: 0.42)  // 草绿（v13.17）
        case .polygon:         return Color(red: 0.85, green: 0.40, blue: 0.65)  // 玫红（v13.31）
        case .fibonacciFan:    return Color(red: 1.00, green: 0.42, blue: 0.42)  // 珊瑚红（v15.87 · 与 fibonacci 橙区分）
        case .priceZone:       return Color(red: 0.55, green: 0.85, blue: 0.65)  // 薄荷绿（v15.88 · 关键支撑/阻力区域）
        case .gannFan:         return Color(red: 0.40, green: 0.60, blue: 0.95)  // 靛蓝（v15.89 · 与 horizontalLine 蓝区分）
        case .fibonacciTimeZone: return Color(red: 0.65, green: 0.55, blue: 0.95)  // 紫罗兰（v15.90 · 时间维度 fib）
        case .gannAngle:       return Color(red: 0.30, green: 0.75, blue: 0.95)  // 天蓝（v17.126 · 江恩系 · 较 gannFan 靛蓝更亮 · 单角度醒目）
        case .gannSquare:      return Color(red: 0.55, green: 0.70, blue: 0.85)  // 雾蓝（v17.126 · 江恩系 · 网格类用较冷低饱和度 · 不抢矩形/通道）
        case .gannBox:         return Color(red: 0.45, green: 0.65, blue: 0.90)  // 钢蓝（v17.127 · 江恩系 · gannSquare 与 gannFan 之间 · 5×5 分析核心）
        case .elliottImpulse:  return Color(red: 0.95, green: 0.55, blue: 0.20)  // 橙红（v17.128 · 艾略特冲击浪 · 趋势波 · 与 fibonacci 橙系协调但更暖）
        case .elliottCorrection: return Color(red: 0.55, green: 0.40, blue: 0.85) // 紫罗兰（v17.128 · 艾略特调整浪 · 反向调整 · 冷色与 elliottImpulse 暖橙对比）
        case .fibonacciSpiral: return Color(red: 0.98, green: 0.78, blue: 0.30)  // 金黄（v17.136 · 黄金螺旋 · fib 系族暖金色 · 与 fibonacciExtension 金黄同调）
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
        String(format: "%.\(priceDigits)f", NSDecimalNumber(decimal: p).doubleValue)
    }
}

#endif
