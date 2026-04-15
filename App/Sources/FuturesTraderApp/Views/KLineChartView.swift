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
        let offset = preheatOffset
        func sliceIndicator(_ full: [Double?]) -> [Double?] {
            guard offset < full.count else { return [] }
            return Array(full[offset..<min(offset + bars.count, full.count)])
        }

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
        if mainOverlay == .boll || mainOverlay == .maAndBoll {
            let fullBoll = calcBOLL(extCloses, period: 20)
            let boll = BOLLData(mid: sliceIndicator(fullBoll.mid), upper: sliceIndicator(fullBoll.upper), lower: sliceIndicator(fullBoll.lower))
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

        // MA线
        if mainOverlay == .ma || mainOverlay == .maAndBoll {
            let ma5 = sliceIndicator(ma(extCloses, 5)), ma20 = sliceIndicator(ma(extCloses, 20))
            drawLine(context: context, values: ma5, color: Theme.ma5, barW: barW, sY: sY)
            drawLine(context: context, values: ma20, color: Theme.ma20, barW: barW, sY: sY)
            context.draw(Text("MA5").font(.system(size: 9)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 18, y: 6))
            context.draw(Text("MA20").font(.system(size: 9)).foregroundColor(Theme.ma20), at: CGPoint(x: padding + 55, y: 6))
        }
        if mainOverlay == .boll || mainOverlay == .maAndBoll {
            let xOff: CGFloat = (mainOverlay == .maAndBoll) ? 100 : 18
            context.draw(Text("BOLL(20,2)").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + xOff, y: 6))
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

    private func fmtP(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if d >= 1000 { return String(format: "%.0f", d) }; if d >= 10 { return String(format: "%.1f", d) }; return String(format: "%.2f", d)
    }
    private func fmtC(_ c: Decimal) -> String { String(format: "%+.0f", NSDecimalNumber(decimal: c).doubleValue) }
    private func fmtPct(_ p: Decimal) -> String { String(format: "%+.2f%%", NSDecimalNumber(decimal: p).doubleValue) }

    // MARK: - 键盘监听

    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: vm.selectPrevSymbol(); return nil    // ↑
            case 125: vm.selectNextSymbol(); return nil    // ↓
            case 123: scrollOffset = min(bars.count - visibleCount, scrollOffset + 3); return nil  // ←
            case 124: scrollOffset = max(0, scrollOffset - 3); return nil  // →
            case 18: vm.selectPeriodByKey(1); return nil   // 1
            case 19: vm.selectPeriodByKey(2); return nil   // 2
            case 20: vm.selectPeriodByKey(3); return nil   // 3
            case 21: vm.selectPeriodByKey(4); return nil   // 4
            case 24: visibleCount = max(20, visibleCount - 5); return nil   // =
            case 27: visibleCount = min(bars.count, visibleCount + 5); return nil  // -
            case 48: vm.cycleSubChart(); return nil        // Tab
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
