// MainApp · v17.53-55 TradingView 对齐 A1.3-A1.5
//
// 非 candle 渲染类型集中 SwiftUI Canvas overlay：
//   - line / area / baseline      （A1.3 · close 单值路径）
//   - hollow / barsOHLC           （A1.4 · OHLC 变体 SwiftUI 自绘）
//   - pointFigure / kagi          （A1.5 · 算法图 · close-based）
//
// 设计要点：
//   - 仅 chartType.usesCandleRenderer == false 时由 ChartScene 实例化
//   - 共用 viewport / priceRange · 与 Metal candle 同坐标映射 · hover/indicators/overlay 仍走 ChartScene
//   - 算法阈值（Renko brickSize / PnF boxSize / Kagi reversal）启发式：first close × 0.5%-1%
//   - 不持有 @State · 纯函数式 Canvas · 切换图表类型即时生效

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import ChartCore

struct AlternativeChartCanvas: View {

    let bars: [KLine]
    let viewport: RenderViewport
    let priceRange: ClosedRange<Decimal>
    let chartType: ChartType
    let theme: ChartTheme
    /// v17.60 · Renko / P&F / Kagi 算法参数（trader 可调 · 默认 hardcoded）
    var options: ChartTypeOptions = .default

    var body: some View {
        Canvas { ctx, size in
            guard !bars.isEmpty else { return }
            let start = max(0, min(viewport.startIndex, bars.count))
            let end = min(bars.count, start + viewport.visibleCount)
            guard start < end else { return }
            let slice = Array(bars[start..<end])
            let hi = (priceRange.upperBound as NSDecimalNumber).doubleValue
            let lo = (priceRange.lowerBound as NSDecimalNumber).doubleValue
            let span = max(hi - lo, 1e-9)
            let yFor: (Decimal) -> CGFloat = { v in
                let d = (v as NSDecimalNumber).doubleValue
                return CGFloat(size.height) * CGFloat((hi - d) / span)
            }
            let barW = size.width / CGFloat(max(1, viewport.visibleCount))
            let xCenter: (Int) -> CGFloat = { i in (CGFloat(i) + 0.5) * barW }

            switch chartType {
            case .line:
                drawPath(ctx: ctx, slice: slice, size: size,
                         yFor: yFor, xCenter: xCenter, mode: .line)
            case .area:
                drawPath(ctx: ctx, slice: slice, size: size,
                         yFor: yFor, xCenter: xCenter, mode: .area)
            case .baseline:
                drawPath(ctx: ctx, slice: slice, size: size,
                         yFor: yFor, xCenter: xCenter, mode: .baseline)
            case .hollow:
                drawHollow(ctx: ctx, slice: slice, yFor: yFor, xCenter: xCenter, barW: barW)
            case .barsOHLC:
                drawBarsOHLC(ctx: ctx, slice: slice, yFor: yFor, xCenter: xCenter, barW: barW)
            case .pointFigure:
                drawPointFigure(ctx: ctx, slice: slice, size: size)
            case .kagi:
                drawKagi(ctx: ctx, slice: slice, size: size, yFor: yFor)
            default:
                break
            }
        }
    }

    // MARK: - A1.3 · Line / Area / Baseline

    private enum PathMode { case line, area, baseline }

    private func drawPath(
        ctx: GraphicsContext, slice: [KLine], size: CGSize,
        yFor: (Decimal) -> CGFloat, xCenter: (Int) -> CGFloat, mode: PathMode
    ) {
        guard !slice.isEmpty else { return }
        var path = Path()
        path.move(to: CGPoint(x: xCenter(0), y: yFor(slice[0].close)))
        for i in 1..<slice.count {
            path.addLine(to: CGPoint(x: xCenter(i), y: yFor(slice[i].close)))
        }
        let bullColor = theme.candleBull
        let bearColor = theme.candleBear

        switch mode {
        case .line:
            ctx.stroke(path, with: .color(bullColor), lineWidth: 1.6)

        case .area:
            var area = path
            area.addLine(to: CGPoint(x: xCenter(slice.count - 1), y: size.height))
            area.addLine(to: CGPoint(x: xCenter(0), y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [bullColor.opacity(0.32), bullColor.opacity(0.04)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            ctx.stroke(path, with: .color(bullColor), lineWidth: 1.6)

        case .baseline:
            let baselineY = yFor(slice[0].close)
            // 上方阳色区
            var up = Path()
            up.move(to: CGPoint(x: xCenter(0), y: baselineY))
            for i in 0..<slice.count {
                let y = min(yFor(slice[i].close), baselineY)
                up.addLine(to: CGPoint(x: xCenter(i), y: y))
            }
            up.addLine(to: CGPoint(x: xCenter(slice.count - 1), y: baselineY))
            up.closeSubpath()
            ctx.fill(up, with: .color(bullColor.opacity(0.20)))
            // 下方阴色区
            var dn = Path()
            dn.move(to: CGPoint(x: xCenter(0), y: baselineY))
            for i in 0..<slice.count {
                let y = max(yFor(slice[i].close), baselineY)
                dn.addLine(to: CGPoint(x: xCenter(i), y: y))
            }
            dn.addLine(to: CGPoint(x: xCenter(slice.count - 1), y: baselineY))
            dn.closeSubpath()
            ctx.fill(dn, with: .color(bearColor.opacity(0.20)))
            // 基线（横虚线）
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: baselineY))
            baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
            ctx.stroke(baseline, with: .color(theme.gridLine),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // 折线（最后 vs 起点决定整体涨跌色）
            let trendUp = slice.last!.close >= slice.first!.close
            ctx.stroke(path, with: .color(trendUp ? bullColor : bearColor), lineWidth: 1.6)
        }
    }

    // MARK: - A1.4 · Hollow / Bars OHLC

    private func drawHollow(
        ctx: GraphicsContext, slice: [KLine],
        yFor: (Decimal) -> CGFloat, xCenter: (Int) -> CGFloat, barW: CGFloat
    ) {
        let w = max(1, barW * 0.7)
        for (i, bar) in slice.enumerated() {
            let cx = xCenter(i)
            let yOpen = yFor(bar.open)
            let yClose = yFor(bar.close)
            let yHigh = yFor(bar.high)
            let yLow = yFor(bar.low)
            let bullish = bar.close >= bar.open
            let color = bullish ? theme.candleBull : theme.candleBear
            // 影线
            var wick = Path()
            wick.move(to: CGPoint(x: cx, y: yHigh))
            wick.addLine(to: CGPoint(x: cx, y: yLow))
            ctx.stroke(wick, with: .color(color), lineWidth: 1)
            // 实体（阳线空心 · 阴线实心）
            let bodyTop = min(yOpen, yClose)
            let bodyH = max(1, abs(yClose - yOpen))
            let bodyRect = CGRect(x: cx - w / 2, y: bodyTop, width: w, height: bodyH)
            if bullish {
                ctx.stroke(Path(bodyRect), with: .color(color), lineWidth: 1.2)
            } else {
                ctx.fill(Path(bodyRect), with: .color(color))
            }
        }
    }

    private func drawBarsOHLC(
        ctx: GraphicsContext, slice: [KLine],
        yFor: (Decimal) -> CGFloat, xCenter: (Int) -> CGFloat, barW: CGFloat
    ) {
        let tickLen = max(2, barW * 0.4)
        for (i, bar) in slice.enumerated() {
            let cx = xCenter(i)
            let yOpen = yFor(bar.open)
            let yClose = yFor(bar.close)
            let yHigh = yFor(bar.high)
            let yLow = yFor(bar.low)
            let bullish = bar.close >= bar.open
            let color = bullish ? theme.candleBull : theme.candleBear
            // 主竖线（high-low）
            var hi = Path()
            hi.move(to: CGPoint(x: cx, y: yHigh))
            hi.addLine(to: CGPoint(x: cx, y: yLow))
            ctx.stroke(hi, with: .color(color), lineWidth: 1.2)
            // 左侧 open tick
            var openTick = Path()
            openTick.move(to: CGPoint(x: cx - tickLen, y: yOpen))
            openTick.addLine(to: CGPoint(x: cx, y: yOpen))
            ctx.stroke(openTick, with: .color(color), lineWidth: 1.2)
            // 右侧 close tick
            var closeTick = Path()
            closeTick.move(to: CGPoint(x: cx, y: yClose))
            closeTick.addLine(to: CGPoint(x: cx + tickLen, y: yClose))
            ctx.stroke(closeTick, with: .color(color), lineWidth: 1.2)
        }
    }

    // MARK: - A1.5 · Point & Figure（经典 · boxSize=first×0.5% · reversal=3 boxes）

    private struct PnFColumn { var isX: Bool; var low: Int; var high: Int }

    private func drawPointFigure(ctx: GraphicsContext, slice: [KLine], size: CGSize) {
        guard let firstClose = slice.first?.close, firstClose > 0 else { return }
        let pctD = Decimal(options.pnfBoxPercent) / 100
        let boxSizeD = firstClose * pctD
        guard boxSizeD > 0 else { return }
        let boxSize = (boxSizeD as NSDecimalNumber).doubleValue
        let base = (firstClose as NSDecimalNumber).doubleValue
        let reversal = max(1, options.pnfReversalBoxes)

        func boxFor(_ p: Decimal) -> Int {
            let d = (p as NSDecimalNumber).doubleValue
            return Int(floor((d - base) / boxSize))
        }

        var cols: [PnFColumn] = []
        var curHigh = boxFor(slice[0].high)
        var curLow = boxFor(slice[0].low)
        if curHigh < curLow { swap(&curHigh, &curLow) }
        var isX = true
        for bar in slice.dropFirst() {
            let hb = boxFor(bar.high)
            let lb = boxFor(bar.low)
            if isX {
                if hb > curHigh { curHigh = hb }
                else if curLow - lb >= reversal {
                    cols.append(PnFColumn(isX: true, low: curLow, high: curHigh))
                    isX = false
                    curHigh = curLow - 1
                    curLow = lb
                }
            } else {
                if lb < curLow { curLow = lb }
                else if hb - curHigh >= reversal {
                    cols.append(PnFColumn(isX: false, low: curLow, high: curHigh))
                    isX = true
                    curLow = curHigh + 1
                    curHigh = hb
                }
            }
        }
        cols.append(PnFColumn(isX: isX, low: curLow, high: curHigh))

        guard !cols.isEmpty else { return }
        let minBox = cols.map(\.low).min() ?? 0
        let maxBox = cols.map(\.high).max() ?? 0
        let totalBoxes = max(1, maxBox - minBox + 1)
        let boxH = size.height / CGFloat(totalBoxes)
        let colW = size.width / CGFloat(cols.count)

        for (i, c) in cols.enumerated() {
            let color = c.isX ? theme.candleBull : theme.candleBear
            let cx = (CGFloat(i) + 0.5) * colW
            for b in c.low...c.high {
                let yMid = size.height - (CGFloat(b - minBox) + 0.5) * boxH
                let radius = max(2, min(colW, boxH) * 0.4)
                if c.isX {
                    var x1 = Path()
                    x1.move(to: CGPoint(x: cx - radius, y: yMid - radius))
                    x1.addLine(to: CGPoint(x: cx + radius, y: yMid + radius))
                    var x2 = Path()
                    x2.move(to: CGPoint(x: cx + radius, y: yMid - radius))
                    x2.addLine(to: CGPoint(x: cx - radius, y: yMid + radius))
                    ctx.stroke(x1, with: .color(color), lineWidth: 1.4)
                    ctx.stroke(x2, with: .color(color), lineWidth: 1.4)
                } else {
                    let rect = CGRect(x: cx - radius, y: yMid - radius,
                                      width: radius * 2, height: radius * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.4)
                }
            }
        }
    }

    // MARK: - A1.5 · Kagi（reversal=1% · zigzag · 阳粗 / 阴细）

    private struct KagiSeg { var price: Decimal; var dir: Int }  // +1 / -1 / 0

    private func drawKagi(
        ctx: GraphicsContext, slice: [KLine], size: CGSize,
        yFor: (Decimal) -> CGFloat
    ) {
        guard let firstClose = slice.first?.close, firstClose > 0 else { return }
        let pctD = Decimal(options.kagiReversalPercent) / 100
        let reversalD = firstClose * pctD
        guard reversalD > 0 else { return }
        let reversal = (reversalD as NSDecimalNumber).doubleValue
        var segs: [KagiSeg] = [KagiSeg(price: slice[0].close, dir: 0)]
        var dir = 0
        var anchor = (slice[0].close as NSDecimalNumber).doubleValue
        for bar in slice.dropFirst() {
            let p = (bar.close as NSDecimalNumber).doubleValue
            if dir == 0 {
                if p - anchor >= reversal {
                    dir = 1; segs.append(KagiSeg(price: bar.close, dir: 1)); anchor = p
                } else if anchor - p >= reversal {
                    dir = -1; segs.append(KagiSeg(price: bar.close, dir: -1)); anchor = p
                }
            } else if dir == 1 {
                if p > anchor {
                    segs[segs.count - 1].price = bar.close; anchor = p
                } else if anchor - p >= reversal {
                    dir = -1
                    segs.append(KagiSeg(price: bar.close, dir: -1))
                    anchor = p
                }
            } else {
                if p < anchor {
                    segs[segs.count - 1].price = bar.close; anchor = p
                } else if p - anchor >= reversal {
                    dir = 1
                    segs.append(KagiSeg(price: bar.close, dir: 1))
                    anchor = p
                }
            }
        }
        guard segs.count >= 2 else {
            let y = yFor(segs[0].price)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(theme.candleBull), lineWidth: 1.4)
            return
        }
        let stepX = size.width / CGFloat(segs.count - 1)
        for i in 1..<segs.count {
            let x0 = CGFloat(i - 1) * stepX
            let x1 = CGFloat(i) * stepX
            let y0 = yFor(segs[i - 1].price)
            let y1 = yFor(segs[i].price)
            let isUp = segs[i].dir >= 0
            let color = isUp ? theme.candleBull : theme.candleBear
            let lw: CGFloat = isUp ? 2.0 : 1.2
            // 垂直段（前点 → 当前价）
            var v = Path()
            v.move(to: CGPoint(x: x0, y: y0))
            v.addLine(to: CGPoint(x: x0, y: y1))
            ctx.stroke(v, with: .color(color), lineWidth: lw)
            // 水平段（zigzag 连接）
            var h = Path()
            h.move(to: CGPoint(x: x0, y: y1))
            h.addLine(to: CGPoint(x: x1, y: y1))
            ctx.stroke(h, with: .color(color), lineWidth: lw)
        }
    }
}

#endif
