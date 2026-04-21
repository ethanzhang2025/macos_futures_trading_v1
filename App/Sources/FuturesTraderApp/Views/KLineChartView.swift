import SwiftUI
import AppKit
import MarketData

/// 主图叠加指标类型
enum MainOverlay: String, CaseIterable {
    case ma = "MA"
    case boll = "BOLL"
    case maAndBoll = "MA+BOLL"
}

/// 图表类型
enum ChartStyle: String, CaseIterable {
    case candlestick = "蜡烛"
    case line = "线图"
    case area = "面积"
    case heikinAshi = "HA"
}

struct KLineChartView: View {
    let bars: [SinaKLineBar]
    let quote: SinaQuote?
    @EnvironmentObject var vm: AppViewModel

    @State private var hoverIndex: Int?
    @State private var mouseLocation: CGPoint = .zero
    @State private var hoverPrice: Double? = nil
    @State private var visibleCount: Int = 80
    @State private var scrollOffset: Int = 0
    @State private var mainOverlay: MainOverlay = .maAndBoll
    @State private var chartStyle: ChartStyle = .candlestick
    // 内联文字编辑
    @State private var editingTextId: UUID?
    @State private var editingText: String = ""
    @State private var editingPosition: CGPoint = .zero
    @State private var editingWidth: CGFloat = 200
    @State private var editingHeight: CGFloat = 60
    // 拖拽移动标注
    @State private var isDraggingObject: Bool = false
    @State private var dragStartIndex: Int = 0
    @State private var dragStartPrice: Double = 0
    @State private var dragEndIndex: Int = 0
    @State private var dragEndPrice: Double = 0
    // NSEvent 监听器句柄（onDisappear 时回收，避免 View 重建造成累积泄漏）
    @State private var keyMonitor: Any?
    @State private var wheelMonitor: Any?

    /// 指标结果记忆化。基于全局 bars 计算一次，滚动/缩放时按 displayRange 切片即可。
    @StateObject private var indicatorCache = IndicatorCache()

    private let padding: CGFloat = 50

    private var contextID: String { "\(vm.selectedSymbol)_\(vm.selectedPeriod)" }

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
                                        hoverPrice = computeHoverPrice(y: loc.y, chartH: klineH - 30)
                                    case .ended:
                                        hoverIndex = nil
                                        hoverPrice = nil
                                    }
                                }
                                .onTapGesture(count: 2) { location in
                                    handleChartDoubleTap(location: location, geoWidth: geo.size.width - 16, chartHeight: klineH)
                                }
                                .onTapGesture { location in
                                    handleChartTap(location: location, geoWidth: geo.size.width - 16, chartHeight: klineH)
                                }
                            // 内联文字编辑器
                            if editingTextId != nil {
                                InlineTextEditor(
                                    text: $editingText,
                                    editorWidth: $editingWidth,
                                    editorHeight: $editingHeight,
                                    position: editingPosition,
                                    onCommit: { commitTextEdit() },
                                    onCancel: { cancelTextEdit() }
                                )
                            }
                        }
                        // 主图按钮区
                        VStack(alignment: .trailing, spacing: 2) {
                            // 图表类型
                            HStack(spacing: 2) {
                                ForEach(ChartStyle.allCases, id: \.self) { style in
                                    Button(action: { chartStyle = style }) {
                                        Text(style.rawValue)
                                            .font(.system(size: 9, weight: chartStyle == style ? .bold : .regular))
                                            .foregroundColor(chartStyle == style ? Theme.ma5 : Theme.textMuted)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(chartStyle == style ? Theme.ma5.opacity(0.15) : Color.clear)
                                            .cornerRadius(3)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            // 指标叠加
                            HStack(spacing: 2) {
                                ForEach(MainOverlay.allCases, id: \.self) { overlay in
                                    Button(action: { mainOverlay = overlay }) {
                                        Text(overlay.rawValue)
                                            .font(.system(size: 9, weight: mainOverlay == overlay ? .bold : .regular))
                                            .foregroundColor(mainOverlay == overlay ? Theme.ma5 : Theme.textMuted)
                                            .padding(.horizontal, 4).padding(.vertical, 2)
                                            .background(mainOverlay == overlay ? Theme.ma5.opacity(0.15) : Color.clear)
                                            .cornerRadius(3)
                                    }
                                    .buttonStyle(.plain)
                                }
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
                            case .macd: SubChartRenderer.drawMACD(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex, fast: vm.indicatorParams.macdFast, slow: vm.indicatorParams.macdSlow, signal: vm.indicatorParams.macdSignal)
                            case .kdj:  SubChartRenderer.drawKDJ(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex, n: vm.indicatorParams.kdjN, m1: vm.indicatorParams.kdjM1, m2: vm.indicatorParams.kdjM2)
                            case .rsi:  SubChartRenderer.drawRSI(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex, periods: vm.indicatorParams.rsiPeriods)
                            case .oi:   SubChartRenderer.drawOI(context: ctx, size: size, bars: displayBars, padding: padding, hoverIndex: hoverIndex)
                            }
                        }
                        .onContinuousHover { phase in
                            // 鼠标在副图时同步 hoverIndex，让主图顶部 infoBar 显示该 bar 的副图指标值
                            switch phase {
                            case .active(let loc):
                                let chartW = max(1, geo.size.width - 16 - padding * 2)
                                let barW = chartW / CGFloat(displayBars.count)
                                let idx = Int((loc.x - padding) / barW)
                                hoverIndex = (idx >= 0 && idx < displayBars.count) ? idx : nil
                            case .ended:
                                hoverIndex = nil
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
                .contextMenu {
                    ChartContextMenu(
                        mainOverlay: $mainOverlay,
                        chartStyle: $chartStyle,
                        hoverPrice: hoverPrice.flatMap { $0 > 0 ? Decimal($0) : nil }
                    )
                }
                .gesture(DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if let selIdx = vm.drawingState.objects.firstIndex(where: { $0.isSelected }) {
                            if !isDraggingObject {
                                // 拖拽开始：记录初始位置
                                isDraggingObject = true
                                dragStartIndex = vm.drawingState.objects[selIdx].startIndex
                                dragStartPrice = vm.drawingState.objects[selIdx].startPrice
                                dragEndIndex = vm.drawingState.objects[selIdx].endIndex
                                dragEndPrice = vm.drawingState.objects[selIdx].endPrice
                            }
                            let chartW = max(1, geo.size.width - 16 - padding * 2)
                            let barW = chartW / CGFloat(displayBars.count)
                            let dxIdx = Int(value.translation.width / barW)
                            let prices = displayBars.flatMap { [$0.highD, $0.lowD] }
                            if let minP = prices.min(), let maxP = prices.max(), maxP > minP {
                                let range = maxP - minP
                                let dyPrice = -Double(value.translation.height) / Double(klineH) * range
                                vm.drawingState.objects[selIdx].startIndex = dragStartIndex + dxIdx
                                vm.drawingState.objects[selIdx].endIndex = dragEndIndex + dxIdx
                                vm.drawingState.objects[selIdx].startPrice = dragStartPrice + dyPrice
                                vm.drawingState.objects[selIdx].endPrice = dragEndPrice + dyPrice
                            }
                        } else {
                            let dx = Int(-value.translation.width / 8)
                            scrollOffset = max(0, min(bars.count - visibleCount, scrollOffset + dx))
                        }
                    }
                    .onEnded { _ in
                        if isDraggingObject { vm.drawingState.commitSave() }
                        isDraggingObject = false
                    }
                )
                .gesture(MagnificationGesture().onChanged { scale in
                    if scale > 1 { visibleCount = max(20, visibleCount - 2) }
                    else { visibleCount = min(bars.count, visibleCount + 2) }
                })
            }
        }
        .focusable().focusEffectDisabled()
        .onAppear { setupKeyboardMonitor(); setupScrollWheelMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            if let m = wheelMonitor { NSEvent.removeMonitor(m); wheelMonitor = nil }
        }
    }

    // MARK: - 信息栏

    private var infoBar: some View {
        HStack(spacing: 12) {
            if let idx = hoverIndex, idx < displayBars.count {
                let bar = displayBars[idx]
                let isUp = bar.close >= bar.open
                Text(bar.date).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.textSecondary)
                lbl("开", Formatters.price(bar.open), color: isUp ? Theme.up : Theme.down)
                lbl("高", Formatters.price(bar.high), color: Theme.up)
                lbl("低", Formatters.price(bar.low), color: Theme.down)
                lbl("收", Formatters.price(bar.close), color: isUp ? Theme.up : Theme.down)
                lbl("量", "\(bar.volume)", color: Theme.textPrimary)
                // BOLL值（顺便修复原先 period 写死 20 不读用户配置的 bug）
                if mainOverlay == .boll || mainOverlay == .maAndBoll {
                    let fullBoll = indicatorCache.boll(contextID: contextID, bars: bars,
                                                        period: vm.indicatorParams.bollPeriod,
                                                        mult: vm.indicatorParams.bollMultiplier)
                    let gIdx = displayRange.start + idx
                    if gIdx < fullBoll.mid.count,
                       let m = fullBoll.mid[gIdx], let u = fullBoll.upper[gIdx], let l = fullBoll.lower[gIdx] {
                        Text("|").foregroundColor(Theme.textMuted).font(.system(size: 11))
                        lbl("MID", String(format: "%.0f", m), color: Color.white)
                        lbl("UP", String(format: "%.0f", u), color: Color.yellow)
                        lbl("DN", String(format: "%.0f", l), color: Color.cyan)
                    }
                }
                // 副图值
                let items = SubChartRenderer.hoverText(type: vm.subChartType, bars: displayBars, index: idx, params: vm.indicatorParams)
                if !items.isEmpty {
                    Text("|").foregroundColor(Theme.textMuted).font(.system(size: 11))
                    ForEach(items, id: \.0) { item in lbl(item.0, item.1, color: item.2) }
                }
                Spacer()
            } else if let q = quote, q.lastPrice > 0 {
                Text(q.name).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.textPrimary)
                Text(Formatters.price(q.lastPrice)).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(Formatters.change(q.change)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Text(Formatters.percent(q.changePercent)).font(.system(size: 12, design: .monospaced)).foregroundColor(q.isUp ? Theme.up : Theme.down)
                Spacer()
                lbl("开", Formatters.price(q.open)); lbl("高", Formatters.price(q.high), color: Theme.up)
                lbl("低", Formatters.price(q.low), color: Theme.down); lbl("量", "\(q.volume)"); lbl("仓", "\(q.openInterest)")
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
        let prices = bars.flatMap { [$0.highD, $0.lowD] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return }

        let chartW = size.width - padding * 2, chartH = size.height - 30, topPad: CGFloat = 16
        let barW = chartW / CGFloat(bars.count), candleW = max(1, barW * 0.65)
        let range = maxP - minP, margin = range * 0.08
        let adjMin = minP - margin, adjRange = range + margin * 2
        let sY: (Double) -> CGFloat = { p in topPad + chartH * CGFloat(1 - (p - adjMin) / adjRange) }

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
            let r = displayRange
            let fullBoll = indicatorCache.boll(contextID: contextID, bars: self.bars,
                                                period: vm.indicatorParams.bollPeriod,
                                                mult: vm.indicatorParams.bollMultiplier)
            let upper = Array(fullBoll.upper[r.start..<r.end])
            let mid = Array(fullBoll.mid[r.start..<r.end])
            let lower = Array(fullBoll.lower[r.start..<r.end])
            drawBollFill(context: context, upper: upper, lower: lower, barW: barW, sY: sY)
            drawLine(context: context, values: upper, color: Color.yellow.opacity(0.7), barW: barW, sY: sY, lineWidth: 1)
            drawLine(context: context, values: mid, color: Color.white.opacity(0.5), barW: barW, sY: sY, lineWidth: 1)
            drawLine(context: context, values: lower, color: Color.cyan.opacity(0.7), barW: barW, sY: sY, lineWidth: 1)
        }

        // 图表主体
        switch chartStyle {
        case .candlestick: drawCandles(context: context, bars: bars, barW: barW, candleW: candleW, sY: sY)
        case .heikinAshi:  drawHeikinAshi(context: context, bars: bars, barW: barW, candleW: candleW, sY: sY)
        case .line:        drawLineChart(context: context, bars: bars, barW: barW, sY: sY)
        case .area:        drawAreaChart(context: context, bars: bars, barW: barW, sY: sY, baseY: sY(adjMin))
        }

        // MA线（可配置）
        let maColors: [Color] = [Theme.ma5, Color(red: 0.3, green: 0.7, blue: 1.0), Theme.ma20, Color(red: 0.2, green: 0.9, blue: 0.6)]
        if mainOverlay == .ma || mainOverlay == .maAndBoll {
            let r = displayRange
            var legendX: CGFloat = padding + 18
            var enabledCount = 0
            for (idx, period) in vm.indicatorParams.maPeriods.enumerated() {
                guard idx < vm.indicatorParams.maEnabled.count, vm.indicatorParams.maEnabled[idx] else { continue }
                let c = maColors[idx % maColors.count]
                let fullMA = indicatorCache.ma(contextID: contextID, bars: self.bars, period: period)
                let maValues = Array(fullMA[r.start..<r.end])
                drawLine(context: context, values: maValues, color: c, barW: barW, sY: sY)
                context.draw(Text("MA\(period)").font(.system(size: 9)).foregroundColor(c), at: CGPoint(x: legendX, y: 6))
                legendX += 45; enabledCount += 1
            }
        }
        if vm.showBoll && (mainOverlay == .boll || mainOverlay == .maAndBoll) {
            let enabledCount = vm.indicatorParams.maEnabled.filter { $0 }.count
            let legendX: CGFloat = (mainOverlay == .maAndBoll) ? padding + 18 + CGFloat(enabledCount) * 45 : padding + 18
            context.draw(Text("BOLL(\(vm.indicatorParams.bollPeriod),\(String(format: "%.0f", vm.indicatorParams.bollMultiplier)))").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: legendX, y: 6))
        }
    }

    // MARK: - 图表样式

    private func drawCandles(context: GraphicsContext, bars: [SinaKLineBar],
                             barW: CGFloat, candleW: CGFloat, sY: (Double) -> CGFloat) {
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let o = bar.openD, c = bar.closeD, h = bar.highD, l = bar.lowD
            let color = c >= o ? Theme.up : Theme.down
            var shadow = Path()
            shadow.move(to: CGPoint(x: x, y: sY(h)))
            shadow.addLine(to: CGPoint(x: x, y: sY(l)))
            context.stroke(shadow, with: .color(color), lineWidth: 1)
            let bTop = sY(max(o, c)), bBot = sY(min(o, c)), bH = max(1, bBot - bTop)
            context.fill(Path(CGRect(x: x - candleW / 2, y: bTop, width: candleW, height: bH)),
                         with: .color(color))
        }
    }

    private func drawHeikinAshi(context: GraphicsContext, bars: [SinaKLineBar],
                                barW: CGFloat, candleW: CGFloat, sY: (Double) -> CGFloat) {
        // Heikin Ashi 依赖前一根的 haOpen/haClose，递推计算
        var prevHAClose = 0.0, prevHAOpen = 0.0
        for (i, bar) in bars.enumerated() {
            let o = bar.openD, c = bar.closeD, h = bar.highD, l = bar.lowD
            let haClose = (o + h + l + c) / 4
            let haOpen = i == 0 ? (o + c) / 2 : (prevHAOpen + prevHAClose) / 2
            let haHigh = max(h, max(haOpen, haClose))
            let haLow = min(l, min(haOpen, haClose))
            prevHAClose = haClose; prevHAOpen = haOpen
            let x = padding + CGFloat(i) * barW + barW / 2
            let color = haClose >= haOpen ? Theme.up : Theme.down
            var shadow = Path()
            shadow.move(to: CGPoint(x: x, y: sY(haHigh)))
            shadow.addLine(to: CGPoint(x: x, y: sY(haLow)))
            context.stroke(shadow, with: .color(color), lineWidth: 1)
            let bTop = sY(max(haOpen, haClose)), bBot = sY(min(haOpen, haClose)), bH = max(1, bBot - bTop)
            context.fill(Path(CGRect(x: x - candleW / 2, y: bTop, width: candleW, height: bH)),
                         with: .color(color))
        }
    }

    private func drawLineChart(context: GraphicsContext, bars: [SinaKLineBar],
                               barW: CGFloat, sY: (Double) -> CGFloat) {
        var path = Path()
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let pt = CGPoint(x: x, y: sY(bar.closeD))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        context.stroke(path, with: .color(Color(red: 0.3, green: 0.6, blue: 1.0)), lineWidth: 1.5)
    }

    private func drawAreaChart(context: GraphicsContext, bars: [SinaKLineBar],
                               barW: CGFloat, sY: (Double) -> CGFloat, baseY: CGFloat) {
        var fillPath = Path()
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let pt = CGPoint(x: x, y: sY(bar.closeD))
            if i == 0 { fillPath.move(to: CGPoint(x: x, y: baseY)); fillPath.addLine(to: pt) }
            else { fillPath.addLine(to: pt) }
        }
        let lastX = padding + CGFloat(bars.count - 1) * barW + barW / 2
        fillPath.addLine(to: CGPoint(x: lastX, y: baseY))
        fillPath.closeSubpath()
        context.fill(fillPath, with: .color(Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.15)))

        var linePath = Path()
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let pt = CGPoint(x: x, y: sY(bar.closeD))
            if i == 0 { linePath.move(to: pt) } else { linePath.addLine(to: pt) }
        }
        context.stroke(linePath, with: .color(Color(red: 0.3, green: 0.6, blue: 1.0)), lineWidth: 1.5)
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
        if let idx = hoverIndex, idx >= 0, idx < bars.count {
            context.draw(Text("\(bars[idx].volume)").font(.system(size: 9, design: .monospaced)).foregroundColor(Theme.textSecondary),
                         at: CGPoint(x: padding + 55, y: 5))
        }
        for (i, bar) in bars.enumerated() {
            let x = padding + CGFloat(i) * barW + barW / 2
            let h = chartH * CGFloat(Double(bar.volume) / maxVol)
            context.fill(Path(CGRect(x: x - vW / 2, y: chartH - h + 3, width: vW, height: h)),
                         with: .color(bar.close >= bar.open ? Theme.volumeUp : Theme.volumeDown))
        }
        drawCrosshairVLine(context: context, size: size, bars: bars)
    }

    /// Y 坐标 → 价格（和 drawCrosshair 同算法：加 8% margin）。给右键菜单复用。
    private func computeHoverPrice(y: CGFloat, chartH: CGFloat) -> Double? {
        let prices = displayBars.flatMap { [$0.highD, $0.lowD] }
        guard let minP = prices.min(), let maxP = prices.max(), maxP > minP else { return nil }
        let topPad: CGFloat = 16
        let range = maxP - minP, margin = range * 0.08
        let adjMin = minP - margin, adjRange = range + margin * 2
        let clampedY = max(topPad, min(topPad + chartH, y))
        return (adjMin + adjRange) - adjRange * Double(clampedY - topPad) / Double(chartH)
    }

    // MARK: - 十字光标

    private func drawCrosshair(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar]) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }
        let prices = bars.flatMap { [$0.highD, $0.lowD] }
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

    // MARK: - 绘图对象渲染

    private func chartGeometry(size: CGSize, bars: [SinaKLineBar]) -> (sX: (Int) -> CGFloat, sY: (Double) -> CGFloat, adjMin: Double, adjRange: Double, chartH: CGFloat, topPad: CGFloat, barW: CGFloat)? {
        guard bars.count >= 2 else { return nil }
        let prices = bars.flatMap { [$0.highD, $0.lowD] }
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
                let anchorX = sX(obj.startIndex), anchorY = sY(obj.startPrice)
                let text = obj.label.isEmpty ? "..." : obj.label
                let bw = obj.boxWidth, bh = obj.boxHeight
                // 框以锚点为中心
                let bx = anchorX - bw / 2, by = anchorY - bh / 2
                let bgRect = CGRect(x: bx, y: by, width: bw, height: bh)
                context.fill(Path(roundedRect: bgRect, cornerRadius: 4), with: .color(Theme.panelBackground.opacity(0.9)))
                context.stroke(Path(roundedRect: bgRect, cornerRadius: 4), with: .color(obj.color.opacity(obj.isSelected ? 0.8 : 0.4)), lineWidth: obj.isSelected ? 1.5 : 0.5)
                // 逐行绘制文字（左对齐，按像素宽度换行）
                let lineH: CGFloat = 15
                let maxPixelWidth = bw - 16
                let wrappedLines = wrapTextByPixelWidth(text, maxWidth: maxPixelWidth)
                let maxLines = max(1, Int((bh - 8) / lineH))
                for (li, line) in wrappedLines.prefix(maxLines).enumerated() {
                    context.draw(
                        Text(line).font(.system(size: 11, weight: .medium)).foregroundColor(obj.color),
                        at: CGPoint(x: bx + 8, y: by + 6 + CGFloat(li) * lineH + lineH / 2),
                        anchor: .leading
                    )
                }
                if obj.isSelected {
                    dot(bx, by, obj.color); dot(bx + bw, by, obj.color)
                    dot(bx, by + bh, obj.color); dot(bx + bw, by + bh, obj.color)
                }

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
                    // 创建空文字标注并直接进入内联编辑
                    let obj = DrawingObject.textMark(index: clickIndex, price: clickPrice, text: "")
                    ds.addObject(obj)
                    startInlineEdit(id: obj.id, currentText: "", location: location)
                default: break
                }
            }
        } else {
            // 非绘图模式：先提交正在编辑的文字
            if editingTextId != nil { commitTextEdit() }

            // 先检查文字标注（用像素区域检测）
            let (sXf, sYf, _, _, _, _, _) = g
            for i in ds.objects.indices {
                let obj = ds.objects[i]
                if obj.type == .text {
                    let ax = sXf(obj.startIndex), ay = sYf(obj.startPrice)
                    let hitRect = CGRect(x: ax - obj.boxWidth / 2, y: ay - obj.boxHeight / 2, width: obj.boxWidth, height: obj.boxHeight)
                    if hitRect.contains(location) {
                        ds.deselectAll()
                        ds.objects[i].isSelected = true
                        return
                    }
                }
            }

            // 再检查其他绘图对象
            for i in ds.objects.indices {
                let obj = ds.objects[i]
                guard obj.type != .text else { continue }
                let bigTolerance = (adjRange) * 0.03
                if abs(Double(obj.startIndex - clickIndex)) < 5 && abs(obj.startPrice - clickPrice) < bigTolerance {
                    ds.deselectAll()
                    ds.objects[i].isSelected = true
                    return
                }
            }
            // 否则正常选中/取消
            if editingTextId != nil { commitTextEdit() }
            let tolerance = (adjRange) * 0.02
            _ = ds.selectNearby(index: clickIndex, price: clickPrice, tolerance: tolerance)
        }
    }

    // MARK: - 双击编辑

    private func handleChartDoubleTap(location: CGPoint, geoWidth: CGFloat, chartHeight: CGFloat) {
        let bars = displayBars
        guard let g = chartGeometry(size: CGSize(width: geoWidth, height: chartHeight), bars: bars) else { return }
        let (sX, sY, _, _, _, _, _) = g
        let ds = vm.drawingState

        // 用像素坐标检测文字框区域
        for i in ds.objects.indices {
            let obj = ds.objects[i]
            guard obj.type == .text else { continue }
            let anchorX = sX(obj.startIndex), anchorY = sY(obj.startPrice)
            let bx = anchorX - obj.boxWidth / 2, by = anchorY - obj.boxHeight / 2
            let hitRect = CGRect(x: bx, y: by, width: obj.boxWidth, height: obj.boxHeight)
            if hitRect.contains(location) {
                ds.deselectAll()
                ds.objects[i].isSelected = true
                startInlineEdit(id: obj.id, currentText: obj.label, location: CGPoint(x: anchorX, y: anchorY))
                return
            }
        }
    }

    // MARK: - 内联编辑

    private func startInlineEdit(id: UUID, currentText: String, location: CGPoint) {
        editingTextId = id
        editingText = currentText
        editingPosition = location
        // 从DrawingObject读取框大小
        if let obj = vm.drawingState.objects.first(where: { $0.id == id }) {
            editingWidth = obj.boxWidth
            editingHeight = obj.boxHeight
        }
    }

    private func commitTextEdit() {
        guard let id = editingTextId else { return }
        if let idx = vm.drawingState.objects.firstIndex(where: { $0.id == id }) {
            if editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                vm.drawingState.objects.remove(at: idx)
            } else {
                vm.drawingState.objects[idx].label = editingText
                vm.drawingState.objects[idx].boxWidth = editingWidth
                vm.drawingState.objects[idx].boxHeight = editingHeight
            }
            vm.drawingState.commitSave()
        }
        editingTextId = nil
        editingText = ""
    }

    private func cancelTextEdit() {
        if let id = editingTextId, let idx = vm.drawingState.objects.firstIndex(where: { $0.id == id }) {
            if vm.drawingState.objects[idx].label.isEmpty {
                vm.drawingState.objects.remove(at: idx)
                vm.drawingState.commitSave()
            }
        }
        editingTextId = nil
        editingText = ""
    }

    /// 按像素宽度换行（中文约11px，英文/数字约7px）
    private func wrapTextByPixelWidth(_ text: String, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            if paragraph.isEmpty { lines.append(""); continue }
            var currentLine = ""
            var currentWidth: CGFloat = 0
            for char in paragraph {
                let charWidth: CGFloat = char.isASCII ? 7 : 12
                if currentWidth + charWidth > maxWidth && !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = String(char)
                    currentWidth = charWidth
                } else {
                    currentLine.append(char)
                    currentWidth += charWidth
                }
            }
            if !currentLine.isEmpty { lines.append(currentLine) }
        }
        return lines
    }

    // MARK: - 键盘监听

    private func setupKeyboardMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 文本输入中（TextField/TextEditor 内的 NSTextView fieldEditor）不拦截，
            // 否则 backspace/方向键/数字键等都会被全局 monitor 吞掉
            if event.window?.firstResponder is NSTextView { return event }
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
            case 53:  // ESC
                if editingTextId != nil { cancelTextEdit() }
                else { vm.drawingState.cancelDrawing() }
                return nil
            case 51: vm.drawingState.deleteSelected(); return nil // Delete
            default: return event
            }
        }
    }

    // MARK: - 滚轮缩放

    private func setupScrollWheelMonitor() {
        if let m = wheelMonitor { NSEvent.removeMonitor(m) }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
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
