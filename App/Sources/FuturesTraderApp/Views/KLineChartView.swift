import SwiftUI
import MarketData

struct KLineChartView: View {
    let bars: [SinaKLineBar]
    let quote: SinaQuote?

    @State private var visibleRange: Range<Int>?
    @State private var hoverIndex: Int?

    private var displayBars: [SinaKLineBar] {
        if let range = visibleRange {
            return Array(bars[range])
        }
        // 默认显示最近80根
        let count = min(bars.count, 80)
        let start = bars.count - count
        return Array(bars[start...])
    }

    var body: some View {
        VStack(spacing: 0) {
            // 信息栏
            infoBar
            // K线主图
            GeometryReader { geo in
                let chartHeight = geo.size.height * 0.7
                let volumeHeight = geo.size.height * 0.25
                let spacing: CGFloat = geo.size.height * 0.05

                VStack(spacing: spacing) {
                    Canvas { context, size in
                        drawKLines(context: context, size: size, bars: displayBars)
                    }
                    .frame(height: chartHeight)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)

                    Canvas { context, size in
                        drawVolume(context: context, size: size, bars: displayBars)
                    }
                    .frame(height: volumeHeight)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - 信息栏

    private var infoBar: some View {
        HStack(spacing: 16) {
            if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 14, weight: .bold))
                Text(formatPrice(q.lastPrice))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? .red : .green)
                Text(formatChange(q.change))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(q.isUp ? .red : .green)
                Text(formatPercent(q.changePercent))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(q.isUp ? .red : .green)

                Spacer()

                Group {
                    label("开", formatPrice(q.open))
                    label("高", formatPrice(q.high), color: .red)
                    label("低", formatPrice(q.low), color: .green)
                    label("量", "\(q.volume)")
                    label("仓", "\(q.openInterest)")
                }
            } else {
                Text("等待行情数据...").foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func label(_ title: String, _ value: String, color: Color = .primary) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - K线绘制

    private func drawKLines(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard bars.count >= 2 else { return }

        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minPrice = prices.min(), let maxPrice = prices.max(), maxPrice > minPrice else { return }

        let padding: CGFloat = 20
        let chartWidth = size.width - padding * 2
        let chartHeight = size.height - padding * 2
        let barWidth = chartWidth / CGFloat(bars.count)
        let candleWidth = max(1, barWidth * 0.7)
        let priceRange = maxPrice - minPrice
        let scaleY: (Double) -> CGFloat = { price in
            padding + chartHeight * CGFloat(1 - (price - minPrice) / priceRange)
        }

        // 计算MA5和MA20
        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let ma5 = movingAverage(closes, period: 5)
        let ma20 = movingAverage(closes, period: 20)

        // 绘制网格线
        for i in 0...4 {
            let y = padding + chartHeight * CGFloat(i) / 4
            let priceLabel = maxPrice - priceRange * Double(i) / 4
            var path = Path()
            path.move(to: CGPoint(x: padding, y: y))
            path.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            context.draw(
                Text(String(format: "%.0f", priceLabel)).font(.system(size: 9)).foregroundColor(.secondary),
                at: CGPoint(x: size.width - padding + 2, y: y),
                anchor: .leading
            )
        }

        // 绘制K线
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barWidth + barWidth / 2
            let o = NSDecimalNumber(decimal: bar.open).doubleValue
            let c = NSDecimalNumber(decimal: bar.close).doubleValue
            let h = NSDecimalNumber(decimal: bar.high).doubleValue
            let l = NSDecimalNumber(decimal: bar.low).doubleValue
            let isUp = c >= o
            let color: Color = isUp ? .red : .green

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

        // 绘制MA线
        drawMALine(context: context, values: ma5, color: .orange, barWidth: barWidth, padding: padding, scaleY: scaleY)
        drawMALine(context: context, values: ma20, color: .blue, barWidth: barWidth, padding: padding, scaleY: scaleY)

        // MA图例
        context.draw(Text("MA5").font(.system(size: 10)).foregroundColor(.orange), at: CGPoint(x: padding + 30, y: padding - 6))
        context.draw(Text("MA20").font(.system(size: 10)).foregroundColor(.blue), at: CGPoint(x: padding + 70, y: padding - 6))
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

    // MARK: - 成交量绘制

    private func drawVolume(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard !bars.isEmpty else { return }

        let maxVol = Double(bars.map(\.volume).max() ?? 1)
        let padding: CGFloat = 20
        let chartWidth = size.width - padding * 2
        let chartHeight = size.height - 10
        let barWidth = chartWidth / CGFloat(bars.count)
        let volWidth = max(1, barWidth * 0.7)

        // 标签
        context.draw(Text("VOL").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: padding + 15, y: 6))

        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barWidth + barWidth / 2
            let vol = Double(bar.volume)
            let h = chartHeight * CGFloat(vol / maxVol)
            let isUp = bar.close >= bar.open
            let color: Color = isUp ? .red.opacity(0.7) : .green.opacity(0.7)
            let rect = CGRect(x: x - volWidth / 2, y: chartHeight - h + 5, width: volWidth, height: h)
            context.fill(Path(rect), with: .color(color))
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
