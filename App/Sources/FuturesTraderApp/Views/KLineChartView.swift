import SwiftUI
import MarketData

struct KLineChartView: View {
    let bars: [SinaKLineBar]
    let quote: SinaQuote?

    @State private var hoverIndex: Int?
    @State private var mouseLocation: CGPoint = .zero

    private var displayBars: [SinaKLineBar] {
        let count = min(bars.count, 80)
        let start = bars.count - count
        return Array(bars[start...])
    }

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            GeometryReader { geo in
                let chartHeight = geo.size.height * 0.72
                let volumeHeight = geo.size.height * 0.23
                let spacing: CGFloat = geo.size.height * 0.05

                VStack(spacing: spacing) {
                    ZStack {
                        Canvas { context, size in
                            drawKLines(context: context, size: size, bars: displayBars)
                        }
                        // 十字光标叠加层
                        Canvas { context, size in
                            drawCrosshair(context: context, size: size, bars: displayBars)
                        }
                        .allowsHitTesting(true)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                mouseLocation = location
                                let padding: CGFloat = 50
                                let chartWidth = max(1, geo.size.width - 16 - padding * 2)
                                let barWidth = chartWidth / CGFloat(displayBars.count)
                                let idx = Int((location.x - padding) / barWidth)
                                hoverIndex = (idx >= 0 && idx < displayBars.count) ? idx : nil
                            case .ended:
                                hoverIndex = nil
                            }
                        }
                    }
                    .frame(height: chartHeight)
                    .background(Theme.chartBackground)
                    .cornerRadius(4)

                    Canvas { context, size in
                        drawVolume(context: context, size: size, bars: displayBars)
                    }
                    .frame(height: volumeHeight)
                    .background(Theme.chartBackground)
                    .cornerRadius(4)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - 信息栏

    private var infoBar: some View {
        HStack(spacing: 16) {
            // 如果有十字光标悬浮，显示悬浮K线信息
            if let idx = hoverIndex, idx < displayBars.count {
                let bar = displayBars[idx]
                let isUp = bar.close >= bar.open
                Text(bar.date).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.textSecondary)
                label("开", formatPrice(bar.open), color: isUp ? Theme.up : Theme.down)
                label("高", formatPrice(bar.high), color: Theme.up)
                label("低", formatPrice(bar.low), color: Theme.down)
                label("收", formatPrice(bar.close), color: isUp ? Theme.up : Theme.down)
                label("量", "\(bar.volume)", color: Theme.textPrimary)
                Spacer()
            } else if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.textPrimary)
                Text(formatPrice(q.lastPrice))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(formatChange(q.change))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(formatPercent(q.changePercent))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                Spacer()
                label("开", formatPrice(q.open))
                label("高", formatPrice(q.high), color: Theme.up)
                label("低", formatPrice(q.low), color: Theme.down)
                label("量", "\(q.volume)")
                label("仓", "\(q.openInterest)")
            } else {
                Text("等待行情数据...").foregroundColor(Theme.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panelBackground)
    }

    private func label(_ title: String, _ value: String, color: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundColor(Theme.textMuted)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - K线绘制

    private func drawKLines(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard bars.count >= 2 else { return }

        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minPrice = prices.min(), let maxPrice = prices.max(), maxPrice > minPrice else { return }

        let padding: CGFloat = 50
        let chartWidth = size.width - padding * 2
        let chartHeight = size.height - 30
        let topPad: CGFloat = 20
        let barWidth = chartWidth / CGFloat(bars.count)
        let candleWidth = max(1, barWidth * 0.65)
        let priceRange = maxPrice - minPrice
        let margin = priceRange * 0.05
        let adjMin = minPrice - margin
        let adjRange = priceRange + margin * 2
        let scaleY: (Double) -> CGFloat = { price in
            topPad + chartHeight * CGFloat(1 - (price - adjMin) / adjRange)
        }

        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let ma5 = movingAverage(closes, period: 5)
        let ma20 = movingAverage(closes, period: 20)

        // 网格
        for i in 0...4 {
            let y = topPad + chartHeight * CGFloat(i) / 4
            let priceLabel = (adjMin + adjRange) - adjRange * Double(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: padding, y: y))
            path.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(path, with: .color(Theme.gridLine), lineWidth: 0.5)
            context.draw(
                Text(String(format: "%.0f", priceLabel)).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textMuted),
                at: CGPoint(x: size.width - padding + 5, y: y),
                anchor: .leading
            )
        }

        // K线
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barWidth + barWidth / 2
            let o = NSDecimalNumber(decimal: bar.open).doubleValue
            let c = NSDecimalNumber(decimal: bar.close).doubleValue
            let h = NSDecimalNumber(decimal: bar.high).doubleValue
            let l = NSDecimalNumber(decimal: bar.low).doubleValue
            let isUp = c >= o
            let color = isUp ? Theme.up : Theme.down

            // 影线
            var shadow = Path()
            shadow.move(to: CGPoint(x: x, y: scaleY(h)))
            shadow.addLine(to: CGPoint(x: x, y: scaleY(l)))
            context.stroke(shadow, with: .color(color), lineWidth: 1)

            // 实体
            let bodyTop = scaleY(max(o, c))
            let bodyBottom = scaleY(min(o, c))
            let bodyHeight = max(1, bodyBottom - bodyTop)
            let bodyRect = CGRect(x: x - candleWidth / 2, y: bodyTop, width: candleWidth, height: bodyHeight)
            if isUp {
                context.stroke(Path(bodyRect), with: .color(color), lineWidth: 1)
            } else {
                context.fill(Path(bodyRect), with: .color(color))
            }
        }

        // MA线
        drawMALine(context: context, values: ma5, color: Theme.ma5, barWidth: barWidth, padding: padding, scaleY: scaleY)
        drawMALine(context: context, values: ma20, color: Theme.ma20, barWidth: barWidth, padding: padding, scaleY: scaleY)

        // 图例
        context.draw(Text("MA5").font(.system(size: 10)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 20, y: 8))
        context.draw(Text("MA20").font(.system(size: 10)).foregroundColor(Theme.ma20), at: CGPoint(x: padding + 60, y: 8))
    }

    // MARK: - 十字光标

    private func drawCrosshair(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }

        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minPrice = prices.min(), let maxPrice = prices.max(), maxPrice > minPrice else { return }

        let padding: CGFloat = 50
        let chartWidth = size.width - padding * 2
        let chartHeight = size.height - 30
        let topPad: CGFloat = 20
        let barWidth = chartWidth / CGFloat(bars.count)
        let priceRange = maxPrice - minPrice
        let margin = priceRange * 0.05
        let adjMin = minPrice - margin
        let adjRange = priceRange + margin * 2

        let bar = bars[idx]
        let x = padding + CGFloat(idx) * barWidth + barWidth / 2
        let closePrice = NSDecimalNumber(decimal: bar.close).doubleValue
        let y = topPad + chartHeight * CGFloat(1 - (closePrice - adjMin) / adjRange)

        // 竖线
        var vLine = Path()
        vLine.move(to: CGPoint(x: x, y: topPad))
        vLine.addLine(to: CGPoint(x: x, y: topPad + chartHeight))
        context.stroke(vLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        // 横线
        let clampedY = max(topPad, min(topPad + chartHeight, mouseLocation.y))
        var hLine = Path()
        hLine.move(to: CGPoint(x: padding, y: clampedY))
        hLine.addLine(to: CGPoint(x: size.width - padding, y: clampedY))
        context.stroke(hLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        // 右侧价格标签
        let hoverPrice = (adjMin + adjRange) - adjRange * Double(clampedY - topPad) / Double(chartHeight)
        let labelRect = CGRect(x: size.width - padding, y: clampedY - 9, width: 48, height: 18)
        context.fill(Path(roundedRect: labelRect, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(
            Text(String(format: "%.0f", hoverPrice))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.background),
            at: CGPoint(x: size.width - padding + 24, y: clampedY)
        )

        // 底部日期标签
        let dateLabelRect = CGRect(x: x - 35, y: topPad + chartHeight + 2, width: 70, height: 16)
        context.fill(Path(roundedRect: dateLabelRect, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(
            Text(bar.date.suffix(10))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.background),
            at: CGPoint(x: x, y: topPad + chartHeight + 10)
        )
    }

    private func drawMALine(context: GraphicsContext, values: [Double?], color: Color, barWidth: CGFloat, padding: CGFloat, scaleY: (Double) -> CGFloat) {
        var path = Path()
        var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barWidth + barWidth / 2
            let y = scaleY(v)
            if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - 成交量

    private func drawVolume(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard !bars.isEmpty else { return }

        let maxVol = Double(bars.map(\.volume).max() ?? 1)
        let padding: CGFloat = 50
        let chartWidth = size.width - padding * 2
        let chartHeight = size.height - 10
        let barWidth = chartWidth / CGFloat(bars.count)
        let volWidth = max(1, barWidth * 0.65)

        // 标签
        context.draw(Text("VOL").font(.system(size: 10)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 15, y: 6))

        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barWidth + barWidth / 2
            let vol = Double(bar.volume)
            let h = chartHeight * CGFloat(vol / maxVol)
            let isUp = bar.close >= bar.open
            let color = isUp ? Theme.volumeUp : Theme.volumeDown
            let rect = CGRect(x: x - volWidth / 2, y: chartHeight - h + 5, width: volWidth, height: h)
            context.fill(Path(rect), with: .color(color))
        }

        // 十字光标竖线延伸到成交量区域
        if let idx = hoverIndex, idx >= 0, idx < bars.count {
            let x = padding + CGFloat(idx) * barWidth + barWidth / 2
            var vLine = Path()
            vLine.move(to: CGPoint(x: x, y: 0))
            vLine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
        }
    }

    // MARK: - Helpers

    private func movingAverage(_ values: [Double], period: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        for i in (period - 1)..<values.count {
            let sum = values[(i - period + 1)...i].reduce(0, +)
            result[i] = sum / Double(period)
        }
        return result
    }

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func formatChange(_ c: Decimal) -> String {
        let d = NSDecimalNumber(decimal: c).doubleValue
        return String(format: "%+.0f", d)
    }

    private func formatPercent(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        return String(format: "%+.2f%%", d)
    }
}
