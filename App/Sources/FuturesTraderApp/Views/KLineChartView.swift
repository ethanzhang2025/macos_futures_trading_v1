import SwiftUI
import AppKit
import MarketData

/// 主图叠加指标类型
enum MainOverlay: String, CaseIterable {
    case ma = "MA"
    case boll = "BOLL"
    case maAndBoll = "MA+BOLL"
}

struct KLineChartView: View {
    let bars: [SinaKLineBar]
    let quote: SinaQuote?
    @EnvironmentObject var vm: AppViewModel

    @State private var hoverIndex: Int?
    @State private var mouseLocation: CGPoint = .zero
    @State private var visibleCount: Int = 80
    @State private var scrollOffset: Int = 0
    @State private var mainOverlay: MainOverlay = .maAndBoll

    private let padding: CGFloat = 50

    /// 用于指标计算的扩展数据（前面多取30根用于预热MA/BOLL等）
    private let preheat = 30

    private var displayRange: (start: Int, end: Int) {
        let count = min(bars.count, visibleCount)
        let end = bars.count - scrollOffset
        let start = max(0, end - count)
        return (start, min(end, bars.count))
    }

    private var displayBars: [SinaKLineBar] {
        let r = displayRange
        guard r.start < r.end else { return [] }
        return Array(bars[r.start..<r.end])
    }

    /// 包含预热数据的K线（用于指标计算，确保BOLL等有足够前置数据）
    private var extendedBars: [SinaKLineBar] {
        let r = displayRange
        let extStart = max(0, r.start - preheat)
        guard extStart < r.end else { return [] }
        return Array(bars[extStart..<r.end])
    }

    /// 预热偏移量（extendedBars比displayBars多出的前置K线数）
    private var preheatOffset: Int {
        let r = displayRange
        return r.start - max(0, r.start - preheat)
    }

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            GeometryReader { geo in
                let klineH = geo.size.height * 0.52
                let volH = geo.size.height * 0.16
                let subH = geo.size.height * 0.22
                let gap: CGFloat = 4

                VStack(spacing: gap) {
                    // K线主图
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            Canvas { ctx, size in drawKLines(context: ctx, size: size, bars: displayBars) }
                            // 绘图对象层
                            Canvas { ctx, size in drawDrawingObjects(context: ctx, size: size, bars: displayBars) }
                            // 十字光标 + 交互层
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
                                .onTapGesture(count: 2) { location in
                                    handleChartDoubleTap(location: location, geoWidth: geo.size.width - 16, chartHeight: klineH)
                                }
                                .onTapGesture { location in
                                    handleChartTap(location: location, geoWidth: geo.size.width - 16, chartHeight: klineH)
                                }
                        }
                        // 主图指标切换按钮
                        HStack(spacing: 2) {
                            ForEach(MainOverlay.allCases, id: \.self) { overlay in
                                Button(action: { mainOverlay = overlay }) {
                                    Text(overlay.rawValue)
                                        .font(.system(size: 9, weight: mainOverlay == overlay ? .bold : .regular))
                                        .foregroundColor(mainOverlay == overlay ? Theme.ma5 : Theme.textMuted)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(mainOverlay == overlay ? Theme.ma5.opacity(0.15) : Color.clear)
                                        .cornerRadius(3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 55).padding(.top, 1)
                    }
                    .frame(height: klineH)
                    .background(Theme.chartBackground)
                    .cornerRadius(4)

                    // 成交量
                    Canvas { ctx, size in drawVolume(context: ctx, size: size, bars: displayBars) }
                        .frame(height: volH).background(Theme.chartBackground).cornerRadius(4)

                    // 副图
                    ZStack(alignment: .topTrailing) {
                        Canvas { ctx, size in
                            switch vm.subChartType {
                            case .macd: SubChartRenderer.drawMACD(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex)
                            case .kdj:  SubChartRenderer.drawKDJ(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex)
                            case .rsi:  SubChartRenderer.drawRSI(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex)
                            }
                        }
                        HStack(spacing: 2) {
                            ForEach(SubChartType.allCases, id: \.self) { type in
                                Button(action: { vm.subChartType = type }) {
                                    Text(type.rawValue)
                                        .font(.system(size: 9, weight: vm.subChartType == type ? .bold : .regular))
                                        .foregroundColor(vm.subChartType == type ? Theme.ma5 : Theme.textMuted)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(vm.subChartType == type ? Theme.ma5.opacity(0.15) : Color.clear)
                                        .cornerRadius(3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 55).padding(.top, 1)
                    }
                    .frame(height: subH).background(Theme.chartBackground).cornerRadius(4)
                }
                .padding(.horizontal, 8)
                .contextMenu { ChartContextMenu(mainOverlay: $mainOverlay) }
                .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                    let dx = Int(-value.translation.width / 8)
                    scrollOffset = max(0, min(bars.count - visibleCount, scrollOffset + dx))
                })
                .gesture(MagnificationGesture().onChanged { scale in
                    if scale > 1 { visibleCount = max(20, visibleCount - 2) }
                    else { visibleCount = min(bars.count, visibleCount + 2) }
                })
            }
        }
        .focusable().focusEffectDisabled()
        .onAppear { setupKeyboardMonitor(); setupScrollWheelMonitor() }
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
                // BOLL值
                if mainOverlay == .boll || mainOverlay == .maAndBoll {
                    let extC = extendedBars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
                    let fullBoll = calcBOLL(extC, period: 20)
                    let slicedMid = Array(fullBoll.mid.dropFirst(preheatOffset))
                    let slicedUp = Array(fullBoll.upper.dropFirst(preheatOffset))
                    let slicedDn = Array(fullBoll.lower.dropFirst(preheatOffset))
                    if idx < slicedMid.count, let m = slicedMid[idx], let u = slicedUp[idx], let l = slicedDn[idx] {
                        Text("|").foregroundColor(Theme.textMuted).font(.system(size: 11))
                        lbl("MID", String(format: "%.0f", m), color: Color.white)
                        lbl("UP", String(format: "%.0f", u), color: Color.yellow)
                        lbl("DN", String(format: "%.0f", l), color: Color.cyan)
                    }
                }
                // 副图值
                let items = SubChartRenderer.hoverText(type: vm.subChartType, bars: displayBars, index: idx)
                if !items.isEmpty {
                    Text("|").foregroundColor(Theme.textMuted).font(.system(size: 11))
                    ForEach(items, id: \.0) { item in lbl(item.0, item.1, color: item.2) }
                }
                Spacer()
            } else if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.textPrimary)
                Text(fmtP(q.lastPrice)).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtC(q.change)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(fmtPct(q.changePercent)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Spacer()
                lbl("开", fmtP(q.open)); lbl("高", fmtP(q.high), color: Theme.up)
                lbl("低", fmtP(q.low), color: Theme.down); lbl("量", "\(q.volume)"); lbl("仓", "\(q.openInterest)")
            } else {
                Text("等待行情数据...").foregroundColor(Theme.textSecondary); Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5).background(Theme.panelBackground)
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

        let chartW = size.width - padding * 2, chartH = size.height - 30, topPad: CGFloat = 16
        let barW = chartW / CGFloat(bars.count), candleW = max(1, barW * 0.65)
        let range = maxP - minP, margin = range * 0.08
        let adjMin = minP - margin, adjRange = range + margin * 2
        let sY: (Double) -> CGFloat = { p in topPad + chartH * CGFloat(1 - (p - adjMin) / adjRange) }

        // 用扩展数据计算指标，然后截取显示范围
        let extCloses = extendedBars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let phOffset = preheatOffset
        let dispCount = bars.count

        // 网格
        for i in 0...4 {
            let y = topPad + chartH * CGFloat(i) / 4
            let pl = (adjMin + adjRange) - adjRange * Double(i) / 4
            var p = Path(); p.move(to: CGPoint(x: padding, y: y)); p.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(p, with: .color(Theme.gridLine), lineWidth: 0.5)
            context.draw(Text(String(format: "%.0f", pl)).font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: size.width - padding + 5, y: y), anchor: .leading)
        }

        // BOLL带（先画，在K线下层）
        if vm.showBoll && (mainOverlay == .boll || mainOverlay == .maAndBoll) {
            let fullBoll = calcBOLL(extCloses, period: 20)
            let boll = BOLLData(
                mid: Array(fullBoll.mid.dropFirst(phOffset).prefix(dispCount)),
                upper: Array(fullBoll.upper.dropFirst(phOffset).prefix(dispCount)),
                lower: Array(fullBoll.lower.dropFirst(phOffset).prefix(dispCount))
            )
            // 填充带
            drawBollFill(context: context, upper: boll.upper, lower: boll.lower, barW: barW, sY: sY)
            drawLine(context: context, values: boll.upper, color: Color.yellow.opacity(0.7), barW: barW, sY: sY, lineWidth: 1)
            drawLine(context: context, values: boll.mid, color: Color.white.opacity(0.5), barW: barW, sY: sY, lineWidth: 1)
            drawLine(context: context, values: boll.lower, color: Color.cyan.opacity(0.7), barW: barW, sY: sY, lineWidth: 1)
        }

        // K线
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let o = NSDecimalNumber(decimal: bar.open).doubleValue, c = NSDecimalNumber(decimal: bar.close).doubleValue
            let h = NSDecimalNumber(decimal: bar.high).doubleValue, l = NSDecimalNumber(decimal: bar.low).doubleValue
            let isUp = c >= o, color = isUp ? Theme.up : Theme.down
            var shadow = Path(); shadow.move(to: CGPoint(x: x, y: sY(h))); shadow.addLine(to: CGPoint(x: x, y: sY(l)))
            context.stroke(shadow, with: .color(color), lineWidth: 1)
            let bTop = sY(max(o, c)), bBot = sY(min(o, c)), bH = max(1, bBot - bTop)
            context.fill(Path(CGRect(x: x - candleW / 2, y: bTop, width: candleW, height: bH)), with: .color(color))
        }

        // MA线（可配置）
        if mainOverlay == .ma || mainOverlay == .maAndBoll {
            var legendX: CGFloat = padding + 18
            for maLine in vm.maConfig.enabledLines {
                let maValues = Array(ma(extCloses, maLine.period).dropFirst(phOffset).prefix(dispCount))
                drawLine(context: context, values: maValues, color: maLine.color, barW: barW, sY: sY)
                context.draw(Text("MA\(maLine.period)").font(.system(size: 9)).foregroundColor(maLine.color), at: CGPoint(x: legendX, y: 6))
                legendX += 45
            }
        }
        if vm.showBoll && (mainOverlay == .boll || mainOverlay == .maAndBoll) {
            let legendX: CGFloat = (mainOverlay == .maAndBoll) ? padding + 18 + CGFloat(vm.maConfig.enabledLines.count) * 45 : padding + 18
            context.draw(Text("BOLL(20,2)").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: legendX, y: 6))
        }
    }

    // MARK: - BOLL计算

    private struct BOLLData {
        let mid: [Double?], upper: [Double?], lower: [Double?]
    }

    private func calcBOLL(_ closes: [Double], period: Int, mult: Double = 2) -> BOLLData {
        let count = closes.count
        var mid = [Double?](repeating: nil, count: count)
        var upper = [Double?](repeating: nil, count: count)
        var lower = [Double?](repeating: nil, count: count)
        for i in (period - 1)..<count {
            let slice = Array(closes[(i - period + 1)...i])
            let avg = slice.reduce(0, +) / Double(period)
            let variance = slice.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(period)
            let std = sqrt(variance)
            mid[i] = avg
            upper[i] = avg + mult * std
            lower[i] = avg - mult * std
        }
        return BOLLData(mid: mid, upper: upper, lower: lower)
    }

    private func drawBollFill(context: GraphicsContext, upper: [Double?], lower: [Double?], barW: CGFloat, sY: (Double) -> CGFloat) {
        var fillPath = Path()
        var points: [(CGFloat, CGFloat)] = []
        for (i, u) in upper.enumerated() {
            guard let u, let l = lower[i] else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            points.append((x, sY(u)))
        }
        guard points.count >= 2 else { return }
        fillPath.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { fillPath.addLine(to: CGPoint(x: p.0, y: p.1)) }
        // 下轨（反向）
        var lowerPoints: [(CGFloat, CGFloat)] = []
        for (i, l) in lower.enumerated() {
            guard l != nil, upper[i] != nil else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            lowerPoints.append((x, sY(l!)))
        }
        for p in lowerPoints.reversed() { fillPath.addLine(to: CGPoint(x: p.0, y: p.1)) }
        fillPath.closeSubpath()
        context.fill(fillPath, with: .color(Color.blue.opacity(0.06)))
    }

    // MARK: - 成交量

    private func drawVolume(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard !bars.isEmpty else { return }
        let maxVol = Double(bars.map(\.volume).max() ?? 1)
        let chartW = size.width - padding * 2, chartH = size.height - 6
        let barW = chartW / CGFloat(bars.count), vW = max(1, barW * 0.65)
        context.draw(Text("VOL").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 15, y: 5))
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let h = chartH * CGFloat(Double(bar.volume) / maxVol)
            context.fill(Path(CGRect(x: x - vW / 2, y: chartH - h + 3, width: vW, height: h)),
                         with: .color(bar.close >= bar.open ? Theme.volumeUp : Theme.volumeDown))
        }
        drawCrosshairVLine(context: context, size: size, bars: bars)
    }

    // MARK: - 十字光标

    private func drawCrosshair(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }
        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return }
        let chartH = size.height - 30, topPad: CGFloat = 16
        let barW = (size.width - padding * 2) / CGFloat(bars.count)
        let range = maxP - minP, margin = range * 0.08, adjMin = minP - margin, adjRange = range + margin * 2
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
        let barW = (size.width - padding * 2) / CGFloat(bars.count)
        let x = padding + CGFloat(idx) * barW + barW / 2
        var vl = Path(); vl.move(to: CGPoint(x: x, y: 0)); vl.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(vl, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
    }

    // MARK: - 通用

    private func drawLine(context: GraphicsContext, values: [Double?], color: Color, barW: CGFloat, sY: (Double) -> CGFloat, lineWidth: CGFloat = 1.2) {
        var path = Path(); var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            if !started { path.move(to: CGPoint(x: x, y: sY(v))); started = true }
            else { path.addLine(to: CGPoint(x: x, y: sY(v))) }
        }
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func ma(_ values: [Double], _ period: Int) -> [Double?] {
        var r = [Double?](repeating: nil, count: values.count)
        for i in (period - 1)..<values.count { r[i] = values[(i - period + 1)...i].reduce(0, +) / Double(period) }
        return r
    }

    // MARK: - 绘图对象渲染

    private func chartGeometry(size: CGSize, bars: [SinaKLineBar]) -> (sX: (Int) -> CGFloat, sY: (Double) -> CGFloat, adjMin: Double, adjRange: Double, chartH: CGFloat, topPad: CGFloat, barW: CGFloat)? {
        guard bars.count >= 2 else { return nil }
        let prices = bars.flatMap { [NSDecimalNumber(decimal: $0.high).doubleValue, NSDecimalNumber(decimal: $0.low).doubleValue] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return nil }
        let chartH = size.height - 30, topPad: CGFloat = 16
        let barW = (size.width - padding * 2) / CGFloat(bars.count)
        let range = maxP - minP, margin = range * 0.08, adjMin = minP - margin, adjRange = range + margin * 2
        let sY: (Double) -> CGFloat = { p in topPad + chartH * CGFloat(1 - (p - adjMin) / adjRange) }
        let sX: (Int) -> CGFloat = { i in self.padding + CGFloat(i) * barW + barW / 2 }
        return (sX, sY, adjMin, adjRange, chartH, topPad, barW)
    }

    private func drawDrawingObjects(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let g = chartGeometry(size: size, bars: bars) else { return }
        let (sX, sY, adjMin, adjRange, chartH, topPad, _) = g

        for obj in vm.drawingState.objects {
            let lw: CGFloat = obj.isSelected ? 2 : 1
            let st = StrokeStyle(lineWidth: lw)
            let dot = { (x: CGFloat, y: CGFloat, c: Color) in
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(c))
            }

            switch obj.type {
            case .horizontalLine:
                let y = sY(obj.startPrice)
                var p = Path(); p.move(to: CGPoint(x: padding, y: y)); p.addLine(to: CGPoint(x: size.width - padding, y: y))
                context.stroke(p, with: .color(obj.color), style: st)
                context.draw(Text(String(format: "%.0f", obj.startPrice)).font(.system(size: 8, design: .monospaced)).foregroundColor(obj.color),
                             at: CGPoint(x: padding - 5, y: y), anchor: .trailing)
                if obj.isSelected { dot(padding, y, obj.color); dot(size.width - padding, y, obj.color) }

            case .verticalLine:
                let x = sX(obj.startIndex)
                var p = Path(); p.move(to: CGPoint(x: x, y: topPad)); p.addLine(to: CGPoint(x: x, y: topPad + chartH))
                context.stroke(p, with: .color(obj.color), style: st)
                if obj.isSelected { dot(x, topPad, obj.color); dot(x, topPad + chartH, obj.color) }

            case .trendLine:
                let x1 = sX(obj.startIndex), y1 = sY(obj.startPrice), x2 = sX(obj.endIndex), y2 = sY(obj.endPrice)
                let dx = x2 - x1
                var eX1 = x1, eY1 = y1, eX2 = x2, eY2 = y2
                if abs(dx) > 0.001 { let s = (y2 - y1) / dx; eX1 = padding; eY1 = y1 + s * (eX1 - x1); eX2 = size.width - padding; eY2 = y1 + s * (eX2 - x1) }
                var p = Path(); p.move(to: CGPoint(x: eX1, y: eY1)); p.addLine(to: CGPoint(x: eX2, y: eY2))
                context.stroke(p, with: .color(obj.color), style: st)
                if obj.isSelected { dot(x1, y1, obj.color); dot(x2, y2, obj.color) }

            case .ray:
                let x1 = sX(obj.startIndex), y1 = sY(obj.startPrice), x2 = sX(obj.endIndex), y2 = sY(obj.endPrice)
                let dx = x2 - x1
                var eX2 = x2, eY2 = y2
                if abs(dx) > 0.001 { let s = (y2 - y1) / dx; eX2 = size.width - padding; eY2 = y1 + s * (eX2 - x1) }
                var p = Path(); p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: eX2, y: eY2))
                context.stroke(p, with: .color(obj.color), style: st)
                if obj.isSelected { dot(x1, y1, obj.color); dot(x2, y2, obj.color) }

            case .fibonacci:
                let x1 = sX(obj.startIndex), x2 = sX(obj.endIndex)
                let highP = max(obj.startPrice, obj.endPrice), lowP = min(obj.startPrice, obj.endPrice)
                let fibRange = highP - lowP
                let left = min(x1, x2), right = max(x1, x2)
                for (li, level) in FibonacciLevels.levels.enumerated() {
                    let price = highP - fibRange * level.ratio
                    let y = sY(price)
                    let color = li < FibonacciLevels.colors.count ? FibonacciLevels.colors[li] : obj.color
                    var lp = Path(); lp.move(to: CGPoint(x: left, y: y)); lp.addLine(to: CGPoint(x: right, y: y))
                    context.stroke(lp, with: .color(color), lineWidth: lw)
                    context.draw(Text("\(level.label) \(String(format: "%.0f", price))").font(.system(size: 8, design: .monospaced)).foregroundColor(color),
                                 at: CGPoint(x: right + 5, y: y), anchor: .leading)
                }
                // 竖线边框
                var vl = Path(); vl.move(to: CGPoint(x: left, y: sY(highP))); vl.addLine(to: CGPoint(x: left, y: sY(lowP)))
                var vr = Path(); vr.move(to: CGPoint(x: right, y: sY(highP))); vr.addLine(to: CGPoint(x: right, y: sY(lowP)))
                context.stroke(vl, with: .color(obj.color.opacity(0.3)), lineWidth: 0.5)
                context.stroke(vr, with: .color(obj.color.opacity(0.3)), lineWidth: 0.5)
                // 半透明填充各层
                for li in 0..<FibonacciLevels.levels.count - 1 {
                    let p1 = highP - fibRange * FibonacciLevels.levels[li].ratio
                    let p2 = highP - fibRange * FibonacciLevels.levels[li + 1].ratio
                    let color = li < FibonacciLevels.colors.count ? FibonacciLevels.colors[li] : obj.color
                    var fp = Path()
                    fp.addRect(CGRect(x: left, y: sY(p1), width: right - left, height: sY(p2) - sY(p1)))
                    context.fill(fp, with: .color(color.opacity(0.05)))
                }
                if obj.isSelected { dot(x1, sY(obj.startPrice), obj.color); dot(x2, sY(obj.endPrice), obj.color) }

            case .parallelChannel:
                let x1 = sX(obj.startIndex), y1 = sY(obj.startPrice), x2 = sX(obj.endIndex), y2 = sY(obj.endPrice)
                let offsetY = sY(obj.startPrice - obj.channelWidth) - y1
                // 上沿
                var p1 = Path(); p1.move(to: CGPoint(x: x1, y: y1)); p1.addLine(to: CGPoint(x: x2, y: y2))
                context.stroke(p1, with: .color(obj.color), style: st)
                // 下沿
                var p2 = Path(); p2.move(to: CGPoint(x: x1, y: y1 + offsetY)); p2.addLine(to: CGPoint(x: x2, y: y2 + offsetY))
                context.stroke(p2, with: .color(obj.color), style: st)
                // 中线虚线
                var pm = Path(); pm.move(to: CGPoint(x: x1, y: y1 + offsetY / 2)); pm.addLine(to: CGPoint(x: x2, y: y2 + offsetY / 2))
                context.stroke(pm, with: .color(obj.color.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                // 填充
                var fp = Path()
                fp.move(to: CGPoint(x: x1, y: y1)); fp.addLine(to: CGPoint(x: x2, y: y2))
                fp.addLine(to: CGPoint(x: x2, y: y2 + offsetY)); fp.addLine(to: CGPoint(x: x1, y: y1 + offsetY)); fp.closeSubpath()
                context.fill(fp, with: .color(obj.color.opacity(0.06)))
                if obj.isSelected { dot(x1, y1, obj.color); dot(x2, y2, obj.color) }

            case .rectangle:
                let x1 = sX(obj.startIndex), y1 = sY(obj.startPrice), x2 = sX(obj.endIndex), y2 = sY(obj.endPrice)
                let rect = CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
                context.stroke(Path(rect), with: .color(obj.color), style: st)
                context.fill(Path(rect), with: .color(obj.color.opacity(0.06)))
                if obj.isSelected { dot(x1, y1, obj.color); dot(x2, y2, obj.color) }

            case .arrow:
                let x = sX(obj.startIndex), y = sY(obj.startPrice)
                // 向上箭头（大号）
                var ap = Path()
                ap.move(to: CGPoint(x: x, y: y - 20))
                ap.addLine(to: CGPoint(x: x - 10, y: y))
                ap.addLine(to: CGPoint(x: x - 3, y: y))
                ap.addLine(to: CGPoint(x: x - 3, y: y + 12))
                ap.addLine(to: CGPoint(x: x + 3, y: y + 12))
                ap.addLine(to: CGPoint(x: x + 3, y: y))
                ap.addLine(to: CGPoint(x: x + 10, y: y))
                ap.closeSubpath()
                context.fill(ap, with: .color(obj.color))
                if obj.isSelected { dot(x, y + 12, obj.color) }

            case .text:
                let x = sX(obj.startIndex), y = sY(obj.startPrice)
                let text = obj.label.isEmpty ? "标注" : obj.label
                // 背景框
                let bgRect = CGRect(x: x - 30, y: y - 10, width: 60, height: 20)
                context.fill(Path(roundedRect: bgRect, cornerRadius: 3), with: .color(Theme.panelBackground.opacity(0.8)))
                context.stroke(Path(roundedRect: bgRect, cornerRadius: 3), with: .color(obj.color.opacity(0.5)), lineWidth: 0.5)
                context.draw(Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(obj.color), at: CGPoint(x: x, y: y))
                if obj.isSelected { dot(x, y + 8, obj.color) }

            case .none: break
            }
        }

        // 实时预览线
        if vm.drawingState.isDrawing {
            let pvStyle = StrokeStyle(lineWidth: 1, dash: [6, 4])
            let pvColor = Color.yellow.opacity(0.8)
            let mouseY = max(topPad, min(topPad + chartH, mouseLocation.y))
            let mousePrice = (adjMin + adjRange) - adjRange * Double(mouseY - topPad) / Double(chartH)
            let mouseIdx = Int((mouseLocation.x - padding) / g.barW)
            let ds = vm.drawingState

            switch ds.activeTool {
            case .horizontalLine:
                var hp = Path(); hp.move(to: CGPoint(x: padding, y: mouseY)); hp.addLine(to: CGPoint(x: size.width - padding, y: mouseY))
                context.stroke(hp, with: .color(pvColor), style: pvStyle)
                context.draw(Text(String(format: "%.0f", mousePrice)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(pvColor),
                             at: CGPoint(x: padding - 5, y: mouseY), anchor: .trailing)
            case .verticalLine:
                var vp = Path(); vp.move(to: CGPoint(x: mouseLocation.x, y: topPad)); vp.addLine(to: CGPoint(x: mouseLocation.x, y: topPad + chartH))
                context.stroke(vp, with: .color(pvColor), style: pvStyle)
            case .trendLine, .ray, .parallelChannel, .rectangle, .fibonacci:
                if let si = ds.tempStartIndex, let sp = ds.tempStartPrice {
                    let sx = sX(si), sy = sY(sp)
                    switch ds.activeTool {
                    case .rectangle, .fibonacci:
                        let rect = CGRect(x: min(sx, mouseLocation.x), y: min(sy, mouseY), width: abs(mouseLocation.x - sx), height: abs(mouseY - sy))
                        context.stroke(Path(rect), with: .color(pvColor), style: pvStyle)
                    case .parallelChannel:
                        var tp = Path(); tp.move(to: CGPoint(x: sx, y: sy)); tp.addLine(to: CGPoint(x: mouseLocation.x, y: mouseY))
                        context.stroke(tp, with: .color(pvColor), style: pvStyle)
                        // 平行线预览（通道宽度默认为价格范围的5%）
                        let chW = (adjRange) * 0.05
                        let offY = sY(sp - chW) - sy
                        var tp2 = Path(); tp2.move(to: CGPoint(x: sx, y: sy + offY)); tp2.addLine(to: CGPoint(x: mouseLocation.x, y: mouseY + offY))
                        context.stroke(tp2, with: .color(pvColor.opacity(0.5)), style: pvStyle)
                    default:
                        var tp = Path(); tp.move(to: CGPoint(x: sx, y: sy)); tp.addLine(to: CGPoint(x: mouseLocation.x, y: mouseY))
                        context.stroke(tp, with: .color(pvColor), style: pvStyle)
                    }
                    context.fill(Path(ellipseIn: CGRect(x: sx - 4, y: sy - 4, width: 8, height: 8)), with: .color(pvColor))
                    context.fill(Path(ellipseIn: CGRect(x: mouseLocation.x - 3, y: mouseY - 3, width: 6, height: 6)), with: .color(pvColor.opacity(0.5)))
                } else {
                    var vp = Path(); vp.move(to: CGPoint(x: mouseLocation.x, y: topPad)); vp.addLine(to: CGPoint(x: mouseLocation.x, y: topPad + chartH))
                    var hp = Path(); hp.move(to: CGPoint(x: padding, y: mouseY)); hp.addLine(to: CGPoint(x: size.width - padding, y: mouseY))
                    context.stroke(vp, with: .color(pvColor.opacity(0.3)), style: pvStyle)
                    context.stroke(hp, with: .color(pvColor.opacity(0.3)), style: pvStyle)
                }
            case .arrow:
                let mx = mouseLocation.x
                var ap = Path()
                ap.move(to: CGPoint(x: mx, y: mouseY - 20))
                ap.addLine(to: CGPoint(x: mx - 10, y: mouseY))
                ap.addLine(to: CGPoint(x: mx - 3, y: mouseY))
                ap.addLine(to: CGPoint(x: mx - 3, y: mouseY + 12))
                ap.addLine(to: CGPoint(x: mx + 3, y: mouseY + 12))
                ap.addLine(to: CGPoint(x: mx + 3, y: mouseY))
                ap.addLine(to: CGPoint(x: mx + 10, y: mouseY))
                ap.closeSubpath()
                context.fill(ap, with: .color(pvColor))
            case .text:
                context.draw(Text("点击放置文字").font(.system(size: 11)).foregroundColor(pvColor), at: CGPoint(x: mouseLocation.x, y: mouseY))
            case .none: break
            }

            let toolName = ds.activeTool.rawValue
            let hint = ds.tempStartIndex != nil ? "点击第二个点完成\(toolName)" : "点击设置\(toolName) · ESC取消"
            context.draw(Text(hint).font(.system(size: 11, weight: .medium)).foregroundColor(Theme.ma5),
                         at: CGPoint(x: size.width / 2, y: topPad + chartH + 16))
        }
    }

    // MARK: - 图表点击处理

    private func handleChartTap(location: CGPoint, geoWidth: CGFloat, chartHeight: CGFloat) {
        let bars = displayBars
        guard let g = chartGeometry(size: CGSize(width: geoWidth, height: chartHeight), bars: bars) else { return }
        let (_, _, adjMin, adjRange, chartH, topPad, barW) = g

        let clickIndex = Int((location.x - padding) / barW)
        let clickPrice = (adjMin + adjRange) - adjRange * Double(location.y - topPad) / Double(chartH)
        let ds = vm.drawingState

        if ds.isDrawing {
            let tool = ds.activeTool
            if tool.needsTwoClicks {
                if let si = ds.tempStartIndex, let sp = ds.tempStartPrice {
                    // 第二次点击
                    switch tool {
                    case .trendLine:   ds.addObject(.trend(si: si, sp: sp, ei: clickIndex, ep: clickPrice))
                    case .ray:         ds.addObject(.ray(si: si, sp: sp, ei: clickIndex, ep: clickPrice))
                    case .fibonacci:   ds.addObject(.fib(si: si, sp: sp, ei: clickIndex, ep: clickPrice))
                    case .rectangle:   ds.addObject(.rect(si: si, sp: sp, ei: clickIndex, ep: clickPrice))
                    case .parallelChannel:
                        let chWidth = adjRange * 0.05
                        ds.addObject(.channel(si: si, sp: sp, ei: clickIndex, ep: clickPrice, width: chWidth))
                    default: break
                    }
                } else {
                    ds.tempStartIndex = clickIndex; ds.tempStartPrice = clickPrice
                }
            } else {
                switch tool {
                case .horizontalLine: ds.addObject(.horizontal(price: clickPrice, index: clickIndex))
                case .verticalLine:   ds.addObject(.vertical(index: clickIndex, price: clickPrice))
                case .arrow:          ds.addObject(.arrowMark(index: clickIndex, price: clickPrice))
                case .text:
                    let input = showTextInput()
                    if !input.isEmpty { ds.addObject(.textMark(index: clickIndex, price: clickPrice, text: input)) }
                    else { ds.cancelDrawing() }
                default: break
                }
            }
        } else {
            let tolerance = (adjRange) * 0.02
            _ = ds.selectNearby(index: clickIndex, price: clickPrice, tolerance: tolerance)
        }
    }

    // MARK: - 双击编辑

    private func handleChartDoubleTap(location: CGPoint, geoWidth: CGFloat, chartHeight: CGFloat) {
        let bars = displayBars
        guard let g = chartGeometry(size: CGSize(width: geoWidth, height: chartHeight), bars: bars) else { return }
        let (_, _, adjMin, adjRange, chartH, topPad, barW) = g

        let clickIndex = Int((location.x - padding) / barW)
        let clickPrice = (adjMin + adjRange) - adjRange * Double(location.y - topPad) / Double(chartH)
        let tolerance = adjRange * 0.02
        let ds = vm.drawingState

        // 找到被双击的文字标注
        for i in ds.objects.indices {
            let obj = ds.objects[i]
            guard obj.type == .text else { continue }
            if abs(Double(obj.startIndex - clickIndex)) < 2 && abs(obj.startPrice - clickPrice) < tolerance {
                let newText = showTextInput(current: obj.label)
                if !newText.isEmpty {
                    ds.objects[i].label = newText
                }
                return
            }
        }
    }

    private func fmtP(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }; if d >= 10 { return String(format: "%.1f", d) }; return String(format: "%.2f", d)
    }
    private func fmtC(_ c: Decimal) -> String { String(format: "%+.0f", NSDecimalNumber(decimal: c).doubleValue) }
    private func fmtPct(_ p: Decimal) -> String { String(format: "%+.2f%%", NSDecimalNumber(decimal: p).doubleValue) }

    // MARK: - 文字输入弹窗

    private func showTextInput(current: String = "") -> String {
        let alert = NSAlert()
        alert.messageText = current.isEmpty ? "添加文字标注" : "编辑文字标注"
        alert.informativeText = "请输入标注内容："
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = current
        textField.placeholderString = "输入标注文字"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return textField.stringValue
        }
        return ""
    }

    // MARK: - 键盘监听

    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: vm.selectPrevSymbol(); return nil    // ↑
            case 125: vm.selectNextSymbol(); return nil    // ↓
            case 123: scrollOffset = min(bars.count - visibleCount, scrollOffset + 3); return nil  // ←
            case 124: scrollOffset = max(0, scrollOffset - 3); return nil  // →
            case 18: vm.selectPeriodByKey(1); return nil   // 1 分时
            case 19: vm.selectPeriodByKey(2); return nil   // 2 日线
            case 20: vm.selectPeriodByKey(3); return nil   // 3 60分
            case 21: vm.selectPeriodByKey(4); return nil   // 4 15分
            case 23: vm.selectPeriodByKey(5); return nil   // 5 5分
            case 24: visibleCount = max(20, visibleCount - 5); return nil   // =
            case 27: visibleCount = min(bars.count, visibleCount + 5); return nil  // -
            case 48: vm.cycleSubChart(); return nil        // Tab
            case 53: vm.drawingState.cancelDrawing(); return nil  // ESC
            case 51: vm.drawingState.deleteSelected(); return nil // Delete
            default: return event
            }
        }
    }

    // MARK: - 滚轮缩放

    private func setupScrollWheelMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let dy = event.scrollingDeltaY
            if abs(dy) > abs(event.scrollingDeltaX) {
                // 垂直滚动 = 缩放
                if dy > 0 { visibleCount = max(20, visibleCount - 3) }  // 向上滚 = 放大
                else { visibleCount = min(bars.count, visibleCount + 3) } // 向下滚 = 缩小
            } else {
                // 水平滚动 = 平移
                let dx = Int(-event.scrollingDeltaX / 2)
                scrollOffset = max(0, min(bars.count - visibleCount, scrollOffset + dx))
            }
            return nil
        }
    }
}
