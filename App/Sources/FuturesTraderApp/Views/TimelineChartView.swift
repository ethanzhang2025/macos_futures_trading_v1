import SwiftUI
import AppKit
import MarketData

/// 分时图
struct TimelineChartView: View {
    let points: [SinaTimelinePoint]
    let quote: SinaQuote?
    let preClose: Decimal  // 昨收/昨结算（分时图中轴线）
    @EnvironmentObject var vm: AppViewModel

    @State private var hoverIndex: Int?
    @State private var mouseLocation: CGPoint = .zero

    private let padding: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            GeometryReader { geo in
                let priceH = geo.size.height * 0.68
                let volH = geo.size.height * 0.25
                let gap: CGFloat = 4

                VStack(spacing: gap) {
                    // 分时价格图
                    ZStack {
                        Canvas { ctx, size in drawTimeline(context: ctx, size: size) }
                        Canvas { ctx, size in drawTimelineCrosshair(context: ctx, size: size) }
                            .allowsHitTesting(true)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    mouseLocation = loc
                                    let chartW = max(1, geo.size.width - 16 - padding * 2)
                                    let idx = Int((loc.x - padding) / chartW * CGFloat(points.count))
                                    hoverIndex = (idx >= 0 && idx < points.count) ? idx : nil
                                case .ended:
                                    hoverIndex = nil
                                }
                            }
                    }
                    .frame(height: priceH)
                    .background(Theme.chartBackground)
                    .cornerRadius(4)

                    // 分时成交量
                    Canvas { ctx, size in drawTimelineVolume(context: ctx, size: size) }
                        .frame(height: volH)
                        .background(Theme.chartBackground)
                        .cornerRadius(4)
                }
                .padding(.horizontal, 8)
            }
        }
        .focusable().focusEffectDisabled()
    }

    // MARK: - 信息栏

    private var infoBar: some View {
        HStack(spacing: 12) {
            if let idx = hoverIndex, idx < points.count {
                let pt = points[idx]
                let change = pt.price - preClose
                let pct = preClose != 0 ? change / preClose * 100 : Decimal(0)
                let isUp = change >= 0
                Text(pt.time).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textSecondary)
                lbl("价", fmtP(pt.price), color: isUp ? Theme.up : Theme.down)
                lbl("均", fmtP(pt.avgPrice), color: Theme.ma5)
                lbl("涨跌", fmtC(change), color: isUp ? Theme.up : Theme.down)
                lbl("幅", fmtPct(pct), color: isUp ? Theme.up : Theme.down)
                lbl("量", "\(pt.volume)", color: Theme.textPrimary)
                Spacer()
            } else if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.textPrimary)
                Text(fmtP(q.lastPrice)).font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtC(q.change)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtPct(q.changePercent)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Spacer()
            } else {
                Text("分时图 · \(vm.selectedName)").foregroundColor(Theme.textSecondary); Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5).background(Theme.panelBackground)
    }

    // MARK: - 分时价格绘制

    private func drawTimeline(context: GraphicsContext, size: CGSize) {
        guard points.count >= 2 else { return }

        let chartW = size.width - padding * 2
        let chartH = size.height - 20
        let topPad: CGFloat = 10
        let preCloseD = NSDecimalNumber(decimal: preClose).doubleValue

        // 计算Y轴范围（以昨收为中心，上下对称）
        let allPrices = points.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let maxDiff = max(
            abs((allPrices.max() ?? preCloseD) - preCloseD),
            abs(preCloseD - (allPrices.min() ?? preCloseD)),
            preCloseD * 0.005 // 最小范围0.5%
        ) * 1.1
        let yMin = preCloseD - maxDiff
        let yMax = preCloseD + maxDiff
        let yRange = yMax - yMin

        let sY: (Double) -> CGFloat = { p in topPad + chartH * CGFloat(1 - (p - yMin) / yRange) }
        let sX: (Int) -> CGFloat = { i in padding + chartW * CGFloat(i) / CGFloat(points.count - 1) }

        // 昨收中轴线
        let midY = sY(preCloseD)
        var midLine = Path(); midLine.move(to: CGPoint(x: padding, y: midY)); midLine.addLine(to: CGPoint(x: size.width - padding, y: midY))
        context.stroke(midLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        // 网格
        for pct in [-2.0, -1.0, 1.0, 2.0] {
            let price = preCloseD * (1 + pct / 100)
            if price >= yMin && price <= yMax {
                let y = sY(price)
                var gl = Path(); gl.move(to: CGPoint(x: padding, y: y)); gl.addLine(to: CGPoint(x: size.width - padding, y: y))
                context.stroke(gl, with: .color(Theme.gridLine), lineWidth: 0.5)
            }
        }

        // Y轴标签（价格 + 涨跌幅）
        for pctVal in [-2.0, -1.0, 0.0, 1.0, 2.0] {
            let price = preCloseD * (1 + pctVal / 100)
            if price >= yMin && price <= yMax {
                let y = sY(price)
                let color: Color = pctVal > 0 ? Theme.up : (pctVal < 0 ? Theme.down : Theme.textMuted)
                context.draw(Text(String(format: "%.0f", price)).font(.system(size: 8, design: .monospaced)).foregroundColor(color),
                             at: CGPoint(x: size.width - padding + 5, y: y), anchor: .leading)
                context.draw(Text(String(format: "%+.1f%%", pctVal)).font(.system(size: 8, design: .monospaced)).foregroundColor(color),
                             at: CGPoint(x: padding - 5, y: y), anchor: .trailing)
            }
        }

        // 价格线下方填充
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: sX(0), y: midY))
        for (i, pt) in points.enumerated() {
            let p = NSDecimalNumber(decimal: pt.price).doubleValue
            fillPath.addLine(to: CGPoint(x: sX(i), y: sY(p)))
        }
        fillPath.addLine(to: CGPoint(x: sX(points.count - 1), y: midY))
        fillPath.closeSubpath()

        // 根据价格在中轴上下用不同颜色填充
        context.fill(fillPath, with: .color(Theme.up.opacity(0.08)))

        // 价格线
        var pricePath = Path()
        for (i, pt) in points.enumerated() {
            let p = NSDecimalNumber(decimal: pt.price).doubleValue
            let point = CGPoint(x: sX(i), y: sY(p))
            if i == 0 { pricePath.move(to: point) } else { pricePath.addLine(to: point) }
        }
        context.stroke(pricePath, with: .color(Color(red: 0.3, green: 0.6, blue: 1.0)), lineWidth: 1.5)

        // 均价线
        var avgPath = Path()
        for (i, pt) in points.enumerated() {
            let a = NSDecimalNumber(decimal: pt.avgPrice).doubleValue
            let point = CGPoint(x: sX(i), y: sY(a))
            if i == 0 { avgPath.move(to: point) } else { avgPath.addLine(to: point) }
        }
        context.stroke(avgPath, with: .color(Theme.ma5), lineWidth: 1)

        // 图例
        context.draw(Text("价格").font(.system(size: 9)).foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0)), at: CGPoint(x: padding + 20, y: 5))
        context.draw(Text("均价").font(.system(size: 9)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 55, y: 5))
    }

    // MARK: - 分时成交量

    private func drawTimelineVolume(context: GraphicsContext, size: CGSize) {
        guard !points.isEmpty else { return }
        let maxVol = Double(points.map(\.volume).max() ?? 1)
        let chartW = size.width - padding * 2
        let chartH = size.height - 6
        let barW = max(1, chartW / CGFloat(points.count) * 0.8)

        context.draw(Text("VOL").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 15, y: 5))

        for (i, pt) in points.enumerated() {
            let x = padding + chartW * CGFloat(i) / CGFloat(max(1, points.count - 1))
            let h = chartH * CGFloat(Double(pt.volume) / maxVol)
            let isUp = pt.price >= preClose
            context.fill(Path(CGRect(x: x - barW / 2, y: chartH - h + 3, width: barW, height: h)),
                         with: .color(isUp ? Theme.volumeUp : Theme.volumeDown))
        }

        // 十字光标
        if let idx = hoverIndex, idx >= 0, idx < points.count {
            let x = padding + chartW * CGFloat(idx) / CGFloat(max(1, points.count - 1))
            var vl = Path(); vl.move(to: CGPoint(x: x, y: 0)); vl.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vl, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        }
    }

    // MARK: - 十字光标

    private func drawTimelineCrosshair(context: GraphicsContext, size: CGSize) {
        guard let idx = hoverIndex, idx >= 0, idx < points.count else { return }

        let chartW = size.width - padding * 2
        let chartH = size.height - 20
        let topPad: CGFloat = 10
        let preCloseD = NSDecimalNumber(decimal: preClose).doubleValue
        let allPrices = points.map { NSDecimalNumber(decimal: $0.price).doubleValue }
        let maxDiff = max(abs((allPrices.max() ?? preCloseD) - preCloseD), abs(preCloseD - (allPrices.min() ?? preCloseD)), preCloseD * 0.005) * 1.1
        let yMin = preCloseD - maxDiff, yMax = preCloseD + maxDiff, yRange = yMax - yMin

        let x = padding + chartW * CGFloat(idx) / CGFloat(max(1, points.count - 1))
        let price = NSDecimalNumber(decimal: points[idx].price).doubleValue
        let y = topPad + chartH * CGFloat(1 - (price - yMin) / yRange)

        // 竖线
        var vLine = Path(); vLine.move(to: CGPoint(x: x, y: topPad)); vLine.addLine(to: CGPoint(x: x, y: topPad + chartH))
        context.stroke(vLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        // 横线
        var hLine = Path(); hLine.move(to: CGPoint(x: padding, y: y)); hLine.addLine(to: CGPoint(x: size.width - padding, y: y))
        context.stroke(hLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        // 价格圆点
        context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(Color(red: 0.3, green: 0.6, blue: 1.0)))

        // 价格标签
        let lr = CGRect(x: size.width - padding, y: y - 9, width: 48, height: 18)
        context.fill(Path(roundedRect: lr, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(Text(String(format: "%.0f", price)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(Theme.background),
                     at: CGPoint(x: size.width - padding + 24, y: y))

        // 时间标签
        let time = points[idx].time
        let tr = CGRect(x: x - 20, y: topPad + chartH + 2, width: 40, height: 14)
        context.fill(Path(roundedRect: tr, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(Text(time).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Theme.background),
                     at: CGPoint(x: x, y: topPad + chartH + 9))
    }

    // MARK: - 格式化

    private func lbl(_ t: String, _ v: String, color: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 2) {
            Text(t).font(.system(size: 10)).foregroundColor(Theme.textMuted)
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }

    private func fmtP(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }; if d >= 10 { return String(format: "%.1f", d) }; return String(format: "%.2f", d)
    }
    private func fmtC(_ c: Decimal) -> String { String(format: "%+.0f", NSDecimalNumber(decimal: c).doubleValue) }
    private func fmtPct(_ p: Decimal) -> String { String(format: "%+.2f%%", NSDecimalNumber(decimal: p).doubleValue) }
}
