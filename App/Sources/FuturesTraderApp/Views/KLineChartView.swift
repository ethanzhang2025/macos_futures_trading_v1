import SwiftUI
import MarketData

struct KLineChartView: View {
    let bars: [SinaKLineBar]
    let quote: SinaQuote?

    @State private var hoverIndex: Int?
    @State private var mouseLocation: CGPoint = .zero
    // 缩放平移状态
    @State private var visibleCount: Int = 80      // 可见K线数量
    @State private var scrollOffset: Int = 0       // 向左滚动偏移量（0=最右端）

    private let padding: CGFloat = 50

    private var displayBars: [SinaKLineBar] {
        let count = min(bars.count, visibleCount)
        let end = bars.count - scrollOffset
        let start = max(0, end - count)
        guard start < end, start >= 0 else { return [] }
        return Array(bars[start..<min(end, bars.count)])
    }

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            GeometryReader { geo in
                let klineH = geo.size.height * 0.52
                let volH = geo.size.height * 0.16
                let macdH = geo.size.height * 0.22
                let gap: CGFloat = 4

                VStack(spacing: gap) {
                    // K线主图
                    ZStack {
                        Canvas { ctx, size in drawKLines(context: ctx, size: size, bars: displayBars) }
                        Canvas { ctx, size in drawCrosshair(context: ctx, size: size, bars: displayBars) }
                            .allowsHitTesting(true)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    mouseLocation = loc
                                    let chartW = max(1, geo.size.width - 16 - padding * 2)
                                    let barW = chartW / CGFloat(displayBars.count)
                                    let idx = Int((loc.x - padding) / barW)
                                    hoverIndex = (idx >= 0 && idx < displayBars.count) ? idx : nil
                                case .ended:
                                    hoverIndex = nil
                                }
                            }
                    }
                    .frame(height: klineH)
                    .background(Theme.chartBackground)
                    .cornerRadius(4)

                    // 成交量
                    Canvas { ctx, size in drawVolume(context: ctx, size: size, bars: displayBars) }
                        .frame(height: volH)
                        .background(Theme.chartBackground)
                        .cornerRadius(4)

                    // MACD
                    Canvas { ctx, size in drawMACD(context: ctx, size: size, bars: displayBars) }
                        .frame(height: macdH)
                        .background(Theme.chartBackground)
                        .cornerRadius(4)
                }
                .padding(.horizontal, 8)
                .gesture(scrollGesture)
                .gesture(magnifyGesture)
            }
        }
    }

    // MARK: - 缩放平移手势

    private var scrollGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let dx = Int(-value.translation.width / 8)
                scrollOffset = max(0, min(bars.count - visibleCount, scrollOffset + dx))
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let newCount: Int
                if scale > 1 {
                    newCount = max(20, visibleCount - 2)
                } else {
                    newCount = min(bars.count, visibleCount + 2)
                }
                visibleCount = newCount
            }
    }

    // MARK: - 信息栏

    private var infoBar: some View {
        HStack(spacing: 12) {
            if let idx = hoverIndex, idx < displayBars.count {
                let bar = displayBars[idx]
                let isUp = bar.close >= bar.open
                Text(bar.date).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textSecondary)
                lbl("开", fmtP(bar.open), color: isUp ? Theme.up : Theme.down)
                lbl("高", fmtP(bar.high), color: Theme.up)
                lbl("低", fmtP(bar.low), color: Theme.down)
                lbl("收", fmtP(bar.close), color: isUp ? Theme.up : Theme.down)
                lbl("量", "\(bar.volume)", color: Theme.textPrimary)
                // MACD值
                let macdData = calcMACD(displayBars.map { NSDecimalNumber(decimal: $0.close).doubleValue })
                if idx < macdData.dif.count, let d = macdData.dif[idx], let e = macdData.dea[idx], let m = macdData.macd[idx] {
                    Text("|").foregroundColor(Theme.textMuted).font(.system(size: 11))
                    lbl("DIF", String(format: "%.1f", d), color: Theme.ma5)
                    lbl("DEA", String(format: "%.1f", e), color: Theme.ma20)
                    lbl("MACD", String(format: "%.1f", m), color: m >= 0 ? Theme.up : Theme.down)
                }
                Spacer()
            } else if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.textPrimary)
                Text(fmtP(q.lastPrice))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtC(q.change)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtPct(q.changePercent)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Spacer()
                lbl("开", fmtP(q.open)); lbl("高", fmtP(q.high), color: Theme.up)
                lbl("低", fmtP(q.low), color: Theme.down); lbl("量", "\(q.volume)"); lbl("仓", "\(q.openInterest)")
            } else {
                Text("等待行情数据...").foregroundColor(Theme.textSecondary); Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.panelBackground)
    }

    private func lbl(_ t: String, _ v: String, color: Color = Theme.textSecondary) -> some View {
        HStack(spacing: 2) {
            Text(t).font(.system(size: 10)).foregroundColor(Theme.textMuted)
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - K线绘制

    private func drawKLines(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard bars.count >= 2 else { return }
        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return }

        let chartW = size.width - padding * 2
        let chartH = size.height - 30
        let topPad: CGFloat = 16
        let barW = chartW / CGFloat(bars.count)
        let candleW = max(1, barW * 0.65)
        let range = maxP - minP
        let margin = range * 0.05
        let adjMin = minP - margin
        let adjRange = range + margin * 2
        let sY: (Double) -> CGFloat = { p in topPad + chartH * CGFloat(1 - (p - adjMin) / adjRange) }

        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let ma5 = ma(closes, 5), ma20 = ma(closes, 20)

        // 网格
        for i in 0...4 {
            let y = topPad + chartH * CGFloat(i) / 4
            let pl = (adjMin + adjRange) - adjRange * Double(i) / 4
            var p = Path(); p.move(to: CGPoint(x: padding, y: y)); p.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(p, with: .color(Theme.gridLine), lineWidth: 0.5)
            context.draw(Text(String(format: "%.0f", pl)).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: size.width - padding + 5, y: y), anchor: .leading)
        }

        // K线
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let o = NSDecimalNumber(decimal: bar.open).doubleValue
            let c = NSDecimalNumber(decimal: bar.close).doubleValue
            let h = NSDecimalNumber(decimal: bar.high).doubleValue
            let l = NSDecimalNumber(decimal: bar.low).doubleValue
            let isUp = c >= o
            let color = isUp ? Theme.up : Theme.down
            var shadow = Path(); shadow.move(to: CGPoint(x: x, y: sY(h))); shadow.addLine(to: CGPoint(x: x, y: sY(l)))
            context.stroke(shadow, with: .color(color), lineWidth: 1)
            let bTop = sY(max(o, c)), bBot = sY(min(o, c)), bH = max(1, bBot - bTop)
            context.fill(Path(CGRect(x: x - candleW / 2, y: bTop, width: candleW, height: bH)), with: .color(color))
        }

        drawLine(context: context, values: ma5, color: Theme.ma5, barW: barW, sY: sY)
        drawLine(context: context, values: ma20, color: Theme.ma20, barW: barW, sY: sY)
        context.draw(Text("MA5").font(.system(size: 9)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 18, y: 6))
        context.draw(Text("MA20").font(.system(size: 9)).foregroundColor(Theme.ma20), at: CGPoint(x: padding + 55, y: 6))
    }

    // MARK: - 成交量

    private func drawVolume(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard !bars.isEmpty else { return }
        let maxVol = Double(bars.map(\.volume).max() ?? 1)
        let chartW = size.width - padding * 2
        let chartH = size.height - 6
        let barW = chartW / CGFloat(bars.count)
        let vW = max(1, barW * 0.65)

        context.draw(Text("VOL").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 15, y: 5))

        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let h = chartH * CGFloat(Double(bar.volume) / maxVol)
            let color = bar.close >= bar.open ? Theme.volumeUp : Theme.volumeDown
            context.fill(Path(CGRect(x: x - vW / 2, y: chartH - h + 3, width: vW, height: h)), with: .color(color))
        }
        drawCrosshairVLine(context: context, size: size, bars: bars)
    }

    // MARK: - MACD

    private func drawMACD(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard bars.count >= 2 else { return }
        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let data = calcMACD(closes)

        let chartW = size.width - padding * 2
        let chartH = size.height - 10
        let topPad: CGFloat = 14
        let barW = chartW / CGFloat(bars.count)
        let stickW = max(1, barW * 0.55)

        // 计算范围
        var allVals: [Double] = []
        for i in 0..<bars.count {
            if let d = data.dif[i] { allVals.append(d) }
            if let e = data.dea[i] { allVals.append(e) }
            if let m = data.macd[i] { allVals.append(m) }
        }
        guard let maxV = allVals.max(), let minV = allVals.min() else { return }
        let absMax = max(abs(maxV), abs(minV), 0.01)
        let midY = topPad + (chartH - topPad) / 2
        let scale = (chartH - topPad) / 2 / CGFloat(absMax)

        // 零轴
        var zeroLine = Path()
        zeroLine.move(to: CGPoint(x: padding, y: midY))
        zeroLine.addLine(to: CGPoint(x: size.width - padding, y: midY))
        context.stroke(zeroLine, with: .color(Theme.gridLine), lineWidth: 0.5)

        // MACD柱状图
        for i in 0..<bars.count {
            guard let m = data.macd[i] else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            let h = CGFloat(abs(m)) * scale
            let y = m >= 0 ? midY - h : midY
            let color = m >= 0 ? Theme.up : Theme.down
            context.fill(Path(CGRect(x: x - stickW / 2, y: y, width: stickW, height: max(1, h))), with: .color(color))
        }

        // DIF线
        drawLine(context: context, values: data.dif, color: Theme.ma5, barW: barW, midY: midY, scale: scale)
        // DEA线
        drawLine(context: context, values: data.dea, color: Theme.ma20, barW: barW, midY: midY, scale: scale)

        // 图例
        context.draw(Text("MACD(12,26,9)").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 40, y: 5))
        context.draw(Text("DIF").font(.system(size: 9)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 100, y: 5))
        context.draw(Text("DEA").font(.system(size: 9)).foregroundColor(Theme.ma20), at: CGPoint(x: padding + 125, y: 5))

        drawCrosshairVLine(context: context, size: size, bars: bars)
    }

    // MARK: - MACD 计算

    private struct MACDData {
        let dif: [Double?]
        let dea: [Double?]
        let macd: [Double?]
    }

    private func calcMACD(_ closes: [Double]) -> MACDData {
        let ema12 = ema(closes, 12)
        let ema26 = ema(closes, 26)
        var dif = [Double?](repeating: nil, count: closes.count)
        for i in 0..<closes.count {
            if let e12 = ema12[i], let e26 = ema26[i] { dif[i] = e12 - e26 }
        }
        let difValues = dif.compactMap { $0 }
        let deaAll = ema(difValues, 9)
        var dea = [Double?](repeating: nil, count: closes.count)
        var deaIdx = 0
        for i in 0..<closes.count {
            if dif[i] != nil {
                dea[i] = deaIdx < deaAll.count ? deaAll[deaIdx] : nil
                deaIdx += 1
            }
        }
        var macd = [Double?](repeating: nil, count: closes.count)
        for i in 0..<closes.count {
            if let d = dif[i], let e = dea[i] { macd[i] = 2 * (d - e) }
        }
        return MACDData(dif: dif, dea: dea, macd: macd)
    }

    // MARK: - 十字光标

    private func drawCrosshair(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }
        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return }

        let chartW = size.width - padding * 2
        let chartH = size.height - 30
        let topPad: CGFloat = 16
        let barW = chartW / CGFloat(bars.count)
        let range = maxP - minP
        let margin = range * 0.05
        let adjMin = minP - margin
        let adjRange = range + margin * 2

        let x = padding + CGFloat(idx) * barW + barW / 2

        var vLine = Path(); vLine.move(to: CGPoint(x: x, y: topPad)); vLine.addLine(to: CGPoint(x: x, y: topPad + chartH))
        context.stroke(vLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        let clampedY = max(topPad, min(topPad + chartH, mouseLocation.y))
        var hLine = Path(); hLine.move(to: CGPoint(x: padding, y: clampedY)); hLine.addLine(to: CGPoint(x: size.width - padding, y: clampedY))
        context.stroke(hLine, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

        let hoverPrice = (adjMin + adjRange) - adjRange * Double(clampedY - topPad) / Double(chartH)
        let lr = CGRect(x: size.width - padding, y: clampedY - 9, width: 48, height: 18)
        context.fill(Path(roundedRect: lr, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(Text(String(format: "%.0f", hoverPrice)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(Theme.background),
                     at: CGPoint(x: size.width - padding + 24, y: clampedY))

        let bar = bars[idx]
        let dr = CGRect(x: x - 35, y: topPad + chartH + 2, width: 70, height: 14)
        context.fill(Path(roundedRect: dr, cornerRadius: 3), with: .color(Theme.crosshair))
        context.draw(Text(String(bar.date.suffix(10))).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Theme.background),
                     at: CGPoint(x: x, y: topPad + chartH + 9))
    }

    private func drawCrosshairVLine(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }
        let chartW = size.width - padding * 2
        let barW = chartW / CGFloat(bars.count)
        let x = padding + CGFloat(idx) * barW + barW / 2
        var vl = Path(); vl.move(to: CGPoint(x: x, y: 0)); vl.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(vl, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
    }

    // MARK: - 通用绘线

    private func drawLine(context: GraphicsContext, values: [Double?], color: Color, barW: CGFloat, sY: (Double) -> CGFloat) {
        var path = Path(); var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            if !started { path.move(to: CGPoint(x: x, y: sY(v))); started = true }
            else { path.addLine(to: CGPoint(x: x, y: sY(v))) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    // MACD用的drawLine（以midY为零轴）
    private func drawLine(context: GraphicsContext, values: [Double?], color: Color, barW: CGFloat, midY: CGFloat, scale: CGFloat) {
        var path = Path(); var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            let y = midY - CGFloat(v) * scale
            if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    // MARK: - 数学

    private func ma(_ values: [Double], _ period: Int) -> [Double?] {
        var r = [Double?](repeating: nil, count: values.count)
        for i in (period - 1)..<values.count { r[i] = values[(i - period + 1)...i].reduce(0, +) / Double(period) }
        return r
    }

    private func ema(_ values: [Double], _ period: Int) -> [Double?] {
        var r = [Double?](repeating: nil, count: values.count)
        let k = 2.0 / Double(period + 1)
        var prev: Double?
        for i in 0..<values.count {
            if prev == nil { prev = values[i] } else { prev = k * values[i] + (1 - k) * prev! }
            r[i] = prev
        }
        return r
    }

    // MARK: - 格式化

    private func fmtP(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }
        if d >= 10 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }
    private func fmtC(_ c: Decimal) -> String { String(format: "%+.0f", NSDecimalNumber(decimal: c).doubleValue) }
    private func fmtPct(_ p: Decimal) -> String { String(format: "%+.2f%%", NSDecimalNumber(decimal: p).doubleValue) }
}

