// 跨期套利窗口（v15.50 · ⌘⌥X · 同品种不同月份合约价差分析）
//
// 与 ⌘⌥S 跨品种套利的区别：
//   - ⌘⌥S：rb-hc / m-y / au-ag 等不同品种之间的价差
//   - ⌘⌥X（本窗口）：RB05-RB10 / M05-M09 等同品种近月-远月的价差（contango/backwardation）
//
// 视觉复用 SpreadWindow 风格（cyan 折线 + 均值 + ±2σ + 滚动 Z 副图）
// 增强：contango/backwardation 标识 · 持有成本均值 HUD · 移仓提示
//
// trader 用法：
//   - 跨期 mean-reverting 套利：spread 偏离历史均值 ±2σ 反向开仓
//   - 移仓预警：临近交割月时近月升水/贴水加剧
//   - 季节性研究：黑色系（旺季-淡季） / 农产品（种植-收割）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore
import ChartCore

struct CalendarSpreadWindow: View {

    @State private var selectedPairID: String = CalendarSpreadPresets.all.first?.id ?? "rb-05-10"
    @State private var spreadValues: [SpreadValue] = []
    @State private var statistics: SpreadStatistics = .empty
    @State private var rollingZScores: [Double] = []
    @State private var rollingWindow: Int = 30
    @State private var showSubChart: Bool = true
    @State private var hoverPoint: CGPoint?
    @Environment(\.openWindow) private var openWindow

    private var selectedPair: CalendarSpreadPair {
        CalendarSpreadPresets.byID[selectedPairID] ?? CalendarSpreadPresets.all.first!
    }

    /// 当前是 contango 还是 backwardation
    private var spreadStructure: SpreadStructure {
        guard !spreadValues.isEmpty else { return .neutral }
        let last = NSDecimalNumber(decimal: spreadValues.last!.value).doubleValue
        if last > 1 { return .contango }
        if last < -1 { return .backwardation }
        return .neutral
    }

    enum SpreadStructure: String {
        case contango = "Contango（升水）"
        case backwardation = "Backwardation（贴水）"
        case neutral = "中性"

        var color: Color {
            switch self {
            case .contango:        return ChartTheme.chartLoss      // 远 > 近 · 红
            case .backwardation:   return ChartTheme.chartProfit    // 远 < 近 · 绿
            case .neutral:         return .secondary
            }
        }

        var description: String {
            switch self {
            case .contango: return "远月 > 近月 · 持有成本主导 · 仓储 + 利息"
            case .backwardation: return "远月 < 近月 · 现货紧张 · 旺季供应不足"
            case .neutral: return "结构平衡 · 远近月几乎持平"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            structureHUD
            Divider()
            statisticsHUD
            Divider()
            if showSubChart {
                VStack(spacing: 0) {
                    spreadChart
                        .frame(maxHeight: .infinity)
                    Divider()
                    rollingZChart
                        .frame(height: 140)
                }
            } else {
                spreadChart
            }
        }
        .frame(minWidth: 980, minHeight: 720)
        .task(id: selectedPairID) { reload() }
        .onChange(of: rollingWindow) { _ in recomputeRollingZ() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("跨期对").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $selectedPairID) {
                    ForEach(CalendarSpreadPair.Category.allCases, id: \.self) { cat in
                        if let pairs = CalendarSpreadPresets.byCategory[cat], !pairs.isEmpty {
                            Section(cat.rawValue) {
                                ForEach(pairs) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }
                        }
                    }
                }
                .frame(width: 220)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("Z 窗口").font(.callout).foregroundColor(.secondary)
                Stepper(value: $rollingWindow, in: 5...100, step: 5) {
                    Text("\(rollingWindow)").font(.callout.monospaced()).frame(minWidth: 28)
                }
                .frame(width: 110)
            }

            Toggle("Z 副图", isOn: $showSubChart)
                .toggleStyle(.checkbox)

            Spacer()

            // 近月 / 远月 → 主图按钮
            HStack(spacing: 6) {
                Button {
                    openWindow(id: "chart")
                    NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: selectedPair.nearMonthID)
                } label: {
                    Text("近月\(selectedPair.nearMonthID) →").font(.caption.monospaced())
                }
                Button {
                    openWindow(id: "chart")
                    NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: selectedPair.farMonthID)
                } label: {
                    Text("远月\(selectedPair.farMonthID) →").font(.caption.monospaced())
                }
            }
            .controlSize(.small)
            .padding(.trailing, 8)

            Button {
                reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 结构 HUD（contango / backwardation 一眼定位）

    private var structureHUD: some View {
        let last = spreadValues.last
        let lastSpread = last.map { NSDecimalNumber(decimal: $0.value).doubleValue } ?? 0
        let lastNear = last.map { NSDecimalNumber(decimal: $0.leg1Close).doubleValue } ?? 0
        let lastFar = last.map { NSDecimalNumber(decimal: $0.leg2Close).doubleValue } ?? 0
        let costPct = lastNear > 0 ? lastSpread / lastNear * 100 : 0
        return HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("结构").font(.caption2).foregroundColor(.secondary)
                Text(spreadStructure.rawValue)
                    .font(.callout.bold())
                    .foregroundColor(spreadStructure.color)
            }
            statBlock("近月", String(format: "%.2f", lastNear), color: .primary)
            statBlock("远月", String(format: "%.2f", lastFar), color: .primary)
            statBlock("价差", String(format: "%+.2f", lastSpread), color: spreadStructure.color)
            statBlock("年化成本", String(format: "%+.2f%%", costPct * 12), color: .secondary)
            Spacer()
            Text(spreadStructure.description)
                .font(.caption2).foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(spreadStructure.color.opacity(0.08))
    }

    // MARK: - 统计 HUD（复用 SpreadStatistics）

    private var statisticsHUD: some View {
        let s = statistics
        let zColor: Color = abs(NSDecimalNumber(decimal: s.zScore).doubleValue) > 2 ? .orange : .secondary
        return HStack(spacing: 22) {
            statBlock("点数", "\(s.count)", color: .secondary)
            statBlock("均值", fmt(s.mean), color: .secondary)
            statBlock("σ", fmt(s.stdDev), color: .secondary)
            statBlock("Z", String(format: "%.2f", NSDecimalNumber(decimal: s.zScore).doubleValue), color: zColor)
            statBlock("分位", String(format: "%.0f%%", s.percentile * 100), color: .secondary)
            Divider().frame(height: 24)
            statBlock("最低", fmt(s.min), color: .red)
            statBlock("最高", fmt(s.max), color: .green)
            Divider().frame(height: 24)
            statBlock("+2σ", fmt(s.upperBand2σ), color: ChartTheme.chartBandLineEmphasized)
            statBlock("-2σ", fmt(s.lowerBand2σ), color: ChartTheme.chartBandLineEmphasized)
            Spacer()
            Text(selectedPair.description).font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    // MARK: - 价差图

    private var spreadChart: some View {
        GeometryReader { geom in
            ZStack {
                Canvas { ctx, size in
                    drawSpread(ctx, size: size)
                }
                .background(ChartTheme.dark.background)

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let pt): hoverPoint = pt
                        case .ended: hoverPoint = nil
                        }
                    }

                if let pt = hoverPoint, spreadValues.count >= 2,
                   let info = hoverInfo(at: pt, in: geom.size) {
                    crosshair(at: pt, snapX: info.snapX, in: geom.size)
                    hoverTooltip(info: info)
                        .position(tooltipPosition(near: pt, in: geom.size,
                                                   tooltipSize: CGSize(width: 220, height: 180)))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func drawSpread(_ ctx: GraphicsContext, size: CGSize) {
        guard spreadValues.count >= 2 else {
            let text = Text("等待数据 · \(spreadValues.count) 点")
                .font(ChartTheme.fontValue).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let values = spreadValues.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        let mean = NSDecimalNumber(decimal: statistics.mean).doubleValue
        let upper = NSDecimalNumber(decimal: statistics.upperBand2σ).doubleValue
        let lower = NSDecimalNumber(decimal: statistics.lowerBand2σ).doubleValue
        guard let minV = values.min(), let maxV = values.max() else { return }
        let vMin = min(minV, lower)
        let vMax = max(maxV, upper)
        let pad = max(0.01, (vMax - vMin) * 0.08)
        let viewMin = vMin - pad
        let viewMax = vMax + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let n = values.count
        let step = (n > 1) ? size.width / CGFloat(n - 1) : size.width

        func yFor(_ v: Double) -> CGFloat {
            (1 - (v - viewMin) / viewRange) * size.height
        }

        // 0 线（区分 contango/backwardation 的关键参考 · 白虚）
        if viewMin < 0 && viewMax > 0 {
            var z = Path()
            z.move(to: CGPoint(x: 0, y: yFor(0)))
            z.addLine(to: CGPoint(x: size.width, y: yFor(0)))
            ctx.stroke(z, with: .color(.white.opacity(0.50)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }

        // ±2σ 通道（橙虚）
        for level in [upper, lower] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: yFor(level)))
            line.addLine(to: CGPoint(x: size.width, y: yFor(level)))
            ctx.stroke(line, with: .color(ChartTheme.chartBandLine),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // 均值线（白虚）
        var meanLine = Path()
        meanLine.move(to: CGPoint(x: 0, y: yFor(mean)))
        meanLine.addLine(to: CGPoint(x: size.width, y: yFor(mean)))
        ctx.stroke(meanLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 价差折线 · 分段染色（contango 红 / backwardation 绿）
        for i in 0..<(values.count - 1) {
            let v1 = values[i]
            let v2 = values[i + 1]
            let x1 = CGFloat(i) * step
            let x2 = CGFloat(i + 1) * step
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(v1)))
            seg.addLine(to: CGPoint(x: x2, y: yFor(v2)))
            let color: Color = (v1 >= 0 && v2 >= 0) ? ChartTheme.chartLoss
                              : (v1 < 0 && v2 < 0) ? ChartTheme.chartProfit
                              : ChartTheme.chartTransition
            ctx.stroke(seg, with: .color(color.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // 终点圆点
        let lastIdx = values.count - 1
        let lastPt = CGPoint(x: CGFloat(lastIdx) * step, y: yFor(values[lastIdx]))
        let dot = Path(ellipseIn: CGRect(x: lastPt.x - 4, y: lastPt.y - 4, width: 8, height: 8))
        ctx.fill(dot, with: .color(spreadStructure.color))
    }

    // MARK: - 滚动 Z 副图

    private var rollingZChart: some View {
        Canvas { ctx, size in
            drawRollingZ(ctx: ctx, size: size)
        }
        .background(ChartTheme.dark.background)
    }

    private func drawRollingZ(ctx: GraphicsContext, size: CGSize) {
        guard rollingZScores.count >= 2 else {
            let text = Text("滚动 Z 不足（窗口 \(rollingWindow)）")
                .font(ChartTheme.fontValue).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let viewMin: Double = -3.5
        let viewMax: Double = 3.5
        let n = rollingZScores.count
        let step = size.width / CGFloat(n - 1)
        func yFor(_ z: Double) -> CGFloat {
            CGFloat(1 - (z - viewMin) / (viewMax - viewMin)) * size.height
        }
        // ±2σ 阈值（橙虚）
        for level: Double in [2, -2] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: yFor(level)))
            line.addLine(to: CGPoint(x: size.width, y: yFor(level)))
            ctx.stroke(line, with: .color(ChartTheme.chartBandLine),
                       style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        }
        // 0 线
        var zeroLine = Path()
        zeroLine.move(to: CGPoint(x: 0, y: yFor(0)))
        zeroLine.addLine(to: CGPoint(x: size.width, y: yFor(0)))
        ctx.stroke(zeroLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
        // Z 折线
        var path = Path()
        for (i, z) in rollingZScores.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: yFor(z))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(ChartTheme.chartLine.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        // 标题
        let title = Text("📈 滚动 Z-score（窗口 \(rollingWindow) · 橙线 ±2σ 反转阈值）")
            .font(ChartTheme.fontSubvalue).foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    // MARK: - hover

    private struct HoverInfo {
        let index: Int
        let value: Double
        let nearPrice: Double
        let farPrice: Double
        let zScore: Double?
        let snapX: CGFloat
    }

    private func hoverInfo(at pt: CGPoint, in size: CGSize) -> HoverInfo? {
        guard let i = ChartHitTester.barIndex(
            atX: pt.x, width: size.width, barCount: spreadValues.count
        ) else { return nil }
        let n = spreadValues.count
        let step = (n > 1) ? size.width / CGFloat(n - 1) : size.width
        let snapX = CGFloat(i) * step
        let sv = spreadValues[i]
        let z: Double? = (i < rollingZScores.count && i >= rollingWindow - 1) ? rollingZScores[i] : nil
        return HoverInfo(
            index: i,
            value: NSDecimalNumber(decimal: sv.value).doubleValue,
            nearPrice: NSDecimalNumber(decimal: sv.leg1Close).doubleValue,
            farPrice: NSDecimalNumber(decimal: sv.leg2Close).doubleValue,
            zScore: z,
            snapX: snapX
        )
    }

    private func crosshair(at pt: CGPoint, snapX: CGFloat, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: snapX, y: 0))
            p.addLine(to: CGPoint(x: snapX, y: size.height))
        }
        .stroke(ChartTheme.crosshairLine,
                style: StrokeStyle(lineWidth: ChartTheme.crosshairLineWidth, dash: ChartTheme.crosshairDash))
        .allowsHitTesting(false)
    }

    private func hoverTooltip(info: HoverInfo) -> some View {
        let zText: String = info.zScore.map { String(format: "%.2f", $0) } ?? "—"
        let zColor: Color = info.zScore.map { abs($0) >= 2 ? .orange : ChartTheme.tooltipSecondary } ?? .secondary
        let structureColor: Color = info.value > 1 ? ChartTheme.chartLoss
                                  : (info.value < -1 ? ChartTheme.chartProfit : .secondary)
        let structureText: String = info.value > 1 ? "升水" : (info.value < -1 ? "贴水" : "中性")
        let costPct = info.nearPrice > 0 ? (info.value / info.nearPrice * 100) : 0
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let timeText = f.string(from: spreadValues[info.index].openTime)
        return VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(ChartTheme.fontValue)
                .foregroundColor(ChartTheme.tooltipSecondary)
            Text("点 #\(info.index + 1) / \(spreadValues.count)")
                .font(ChartTheme.fontSubvalue)
                .foregroundColor(ChartTheme.tooltipMuted)
            Divider().background(ChartTheme.tooltipDivider)
            row("近月", String(format: "%.2f", info.nearPrice), color: ChartTheme.tooltipSecondary)
            row("远月", String(format: "%.2f", info.farPrice), color: ChartTheme.tooltipSecondary)
            row("价差", String(format: "%+.2f", info.value), color: structureColor)
            row("结构", structureText, color: structureColor)
            row("成本%", String(format: "%+.2f%%", costPct), color: ChartTheme.tooltipSecondary)
            Divider().background(ChartTheme.tooltipDivider)
            row("Z", zText, color: zColor)
            row("均值", fmt(statistics.mean), color: ChartTheme.tooltipSecondary)
        }
        .padding(ChartTheme.tooltipPadding)
        .frame(width: 220, alignment: .leading)
        .background(ChartTheme.tooltipBackground)
        .cornerRadius(ChartTheme.tooltipCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: ChartTheme.tooltipCornerRadius)
                    .stroke(ChartTheme.tooltipBorder, lineWidth: ChartTheme.tooltipBorderWidth))
    }

    private func row(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ChartTheme.fontLabel)
                .foregroundColor(ChartTheme.tooltipLabel)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(ChartTheme.fontValue)
                .foregroundColor(color)
            Spacer()
        }
    }

    private func tooltipPosition(near pt: CGPoint, in size: CGSize, tooltipSize: CGSize) -> CGPoint {
        let dx: CGFloat = pt.x + 12 + tooltipSize.width / 2 < size.width
            ? tooltipSize.width / 2 + 12
            : -tooltipSize.width / 2 - 12
        let dy: CGFloat = pt.y + 12 + tooltipSize.height / 2 < size.height
            ? tooltipSize.height / 2 + 12
            : -tooltipSize.height / 2 - 12
        return CGPoint(x: pt.x + dx, y: pt.y + dy)
    }

    // MARK: - 数据加载

    private func reload() {
        let pair = selectedPair
        let basePrice = defaultBasePrice(pair.underlyingID)
        let calVals = CalendarSpreadCalculator.generateMockSeries(
            for: pair, basePrice: basePrice, count: 200
        )
        spreadValues = CalendarSpreadCalculator.toSpreadValues(calVals)
        statistics = SpreadStatisticsCalculator.compute(spreadValues)
        recomputeRollingZ()
    }

    private func recomputeRollingZ() {
        rollingZScores = SpreadStatisticsCalculator.rollingZScores(spreadValues, window: rollingWindow)
    }

    private func fmt(_ v: Decimal) -> String {
        let d = NSDecimalNumber(decimal: v).doubleValue
        if abs(d) >= 1000 { return String(format: "%.0f", d) }
        if abs(d) >= 10   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func defaultBasePrice(_ underlyingID: String) -> Double {
        // 从 SectorPresets 找品种主连续作为基准价
        let candidates = SectorPresets.all.filter { $0.id.hasPrefix(underlyingID) }
        if let first = candidates.first {
            return NSDecimalNumber(decimal: first.lastPrice).doubleValue
        }
        return 1000
    }
}

#endif
