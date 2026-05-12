// 跨品种套利分析窗口（v15.27 · WP-套利分析 V1 MVP）
//
// 职责：
//   - 顶部 toolbar：预设 Picker（12 经典对）+ 周期 Picker
//   - 中部 Canvas：价差折线 + mean 中线 + ±2σ 通道（套利交易者必看）
//   - 底部 HUD：count / current / mean / std / zScore / percentile / range / upper/lower band
//
// 数据来源（v1）：mock 合成两腿 K 线 → SpreadCalculator → SpreadStatistics
// v2 计划：接入 SinaMarketData / 真 CTP 历史，对预设两腿都拉 K 线再计算

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore
import ChartCore

// MARK: - 主窗口

struct SpreadWindow: View {

    @State private var selectedPairID: String = SpreadPresets.all.first?.id ?? "rb-hc"
    @State private var period: KLinePeriod = .minute15
    @State private var spreadValues: [SpreadValue] = []
    @State private var statistics: SpreadStatistics = .empty
    /// v15.37 V2 · 滚动 Z 时序（主图标信号点用）
    @State private var rollingZScores: [Double] = []
    /// v15.37 V2 · 信号序列（主图叠加 ▲▼ 标识）
    @State private var signals: [SpreadSignal] = []
    /// v15.37 V2 · 价差直方图（底部副图用）
    @State private var histogram: SpreadHistogram = .empty
    /// v15.37 V2 · 副图模式（none = 无副图 · histogram = 分布直方图）
    @State private var subChartMode: SubChartMode = .histogram
    /// v15.37 V2 · 回测 sheet 显隐
    @State private var backtestSheetPresented: Bool = false
    /// v15.37 V2 · 滚动 Z 窗口（trader 可调）
    @State private var rollingWindow: Int = 30
    /// v15.40 · 主图 hover 点（鼠标在 spreadChart 内的像素坐标 · nil = 鼠标已离开）
    @State private var spreadHoverPoint: CGPoint?

    /// v17.95 · 单击两腿 label → openWindow("chart") + post 切主图
    @Environment(\.openWindow) private var openWindow

    private var selectedPair: SpreadPair {
        SpreadPresets.byID[selectedPairID] ?? SpreadPresets.all.first!
    }

    enum SubChartMode: String, CaseIterable, Identifiable {
        case none, histogram, rollingZ
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .none:      return "无"
            case .histogram: return "直方图"
            case .rollingZ:  return "滚动 Z"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statisticsHUD
            Divider()
            if subChartMode == .none {
                spreadChart
            } else {
                VStack(spacing: 0) {
                    spreadChart
                        .frame(maxHeight: .infinity)
                    Divider()
                    subChartView
                        .frame(height: 160)
                }
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .task(id: selectedPairID) { reload() }
        .onChange(of: rollingWindow) { _ in recomputeV2() }
        // v17.95 · 接 watchlistInstrumentSelected · 主图切到某合约时 · 自动找含该腿的套利对（保持当前对若已含）
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            guard let id = note.object as? String else { return }
            // 当前对已含 → 不切（避免来回跳）
            if selectedPair.leg1.instrumentID == id || selectedPair.leg2.instrumentID == id { return }
            // 找首个含 id 的预设对
            if let match = SpreadPresets.all.first(where: { $0.leg1.instrumentID == id || $0.leg2.instrumentID == id }),
               match.id != selectedPairID {
                selectedPairID = match.id
            }
        }
        .sheet(isPresented: $backtestSheetPresented) {
            SpreadBacktestSheet(
                pair: selectedPair,
                values: spreadValues,
                rollingWindow: rollingWindow,
                isPresented: $backtestSheetPresented
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("套利对").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $selectedPairID) {
                    ForEach(SpreadPair.Category.allCases, id: \.self) { cat in
                        if let pairs = SpreadPresets.byCategory[cat], !pairs.isEmpty {
                            Section(cat.rawValue) {
                                ForEach(pairs) { pair in
                                    Text(pair.name).tag(pair.id)
                                }
                            }
                        }
                    }
                }
                .frame(width: 220)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("周期").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $period) {
                    Text("1 分").tag(KLinePeriod.minute1)
                    Text("15 分").tag(KLinePeriod.minute15)
                    Text("60 分").tag(KLinePeriod.hour1)
                    Text("日").tag(KLinePeriod.daily)
                }
                .frame(width: 100)
                .labelsHidden()
            }

            // v15.37 V2 · 滚动 Z 窗口
            HStack(spacing: 6) {
                Text("Z 窗口").font(.callout).foregroundColor(.secondary)
                Stepper(value: $rollingWindow, in: 5...200, step: 5) {
                    Text("\(rollingWindow)").font(.callout.monospaced())
                        .frame(minWidth: 28)
                }
            }

            // v15.37 V2 · 副图模式
            HStack(spacing: 6) {
                Text("副图").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $subChartMode) {
                    ForEach(SubChartMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .frame(width: 100)
                .labelsHidden()
            }

            Spacer()

            // v17.95 · 两腿合约可点击 · 单击切主图 K 线（与其他 6 窗口一致 · 跨窗口分析闭环）
            HStack(spacing: 6) {
                legChipButton(leg: selectedPair.leg1)
                Text("/").foregroundColor(.secondary.opacity(0.5)).font(.caption.monospaced())
                legChipButton(leg: selectedPair.leg2)
            }

            Button {
                backtestSheetPresented = true
            } label: {
                Label("回测", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tooltip("基于滚动 Z 阈值跑套利回测 · 出 PnL 曲线 + 胜率 + maxDD")

            Button {
                reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// v17.95 · 两腿合约可点击 chip（与 CalendarSpreadWindow 切主图风格一致）
    @ViewBuilder
    private func legChipButton(leg: SpreadLeg) -> some View {
        let sign = leg.ratio > 0 ? "+" : ""
        Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: leg.instrumentID)
        } label: {
            Text("\(sign)\(leg.ratio)·\(leg.instrumentID)")
                .font(.caption.monospaced())
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .help("切主图 K 线：\(leg.instrumentID)")
    }

    // MARK: - 统计 HUD

    private var statisticsHUD: some View {
        let s = statistics
        let zColor: Color = abs(NSDecimalNumber(decimal: s.zScore).doubleValue) > 2 ? .orange : .secondary
        return HStack(spacing: 22) {
            stat("点数", "\(s.count)", color: .secondary)
            stat("当前", fmt(s.current), color: .primary)
            stat("均值", fmt(s.mean), color: .secondary)
            stat("σ", fmt(s.stdDev), color: .secondary)
            stat("Z", String(format: "%.2f", NSDecimalNumber(decimal: s.zScore).doubleValue), color: zColor)
            stat("分位", String(format: "%.0f%%", s.percentile * 100), color: .secondary)
            Divider().frame(height: 24)
            stat("最低", fmt(s.min), color: .red)
            stat("最高", fmt(s.max), color: .green)
            stat("区间", fmt(s.range), color: .secondary)
            Divider().frame(height: 24)
            stat("+2σ", fmt(s.upperBand2σ), color: .orange.opacity(0.8))
            stat("-2σ", fmt(s.lowerBand2σ), color: .orange.opacity(0.8))
            Spacer()
            Text(selectedPair.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
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
                        case .active(let pt): spreadHoverPoint = pt
                        case .ended: spreadHoverPoint = nil
                        }
                    }

                if let pt = spreadHoverPoint, spreadValues.count >= 2,
                   let info = spreadHoverInfo(at: pt, in: geom.size) {
                    spreadCrosshair(at: pt, snapX: info.snapX, in: geom.size)
                    spreadHoverTooltip(info: info)
                        .position(tooltipPosition(near: pt, in: geom.size,
                                                   tooltipSize: CGSize(width: 220, height: 200)))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 主图 hover 信息
    private struct SpreadHoverInfo {
        let index: Int
        let value: Double
        let zScore: Double?       // 滚动 Z（不足 window 为 nil）
        let signal: SpreadSignal?
        let snapX: CGFloat        // 吸附到 bar 上的 x（视觉对齐）
    }

    private func spreadHoverInfo(at pt: CGPoint, in size: CGSize) -> SpreadHoverInfo? {
        guard let i = ChartHitTester.barIndex(
            atX: pt.x, width: size.width, barCount: spreadValues.count
        ) else { return nil }
        let v = NSDecimalNumber(decimal: spreadValues[i].value).doubleValue
        // 套利主图采用 (n-1) 等距步长（drawSpread 同公式）· snapX 必须复刻
        let n = spreadValues.count
        let step = (n > 1) ? size.width / CGFloat(n - 1) : size.width
        let snapX = CGFloat(i) * step
        let z: Double? = (i < rollingZScores.count && i >= rollingWindow - 1) ? rollingZScores[i] : nil
        let sig = signals.first { $0.index == i }
        return SpreadHoverInfo(index: i, value: v, zScore: z, signal: sig, snapX: snapX)
    }

    private func spreadCrosshair(at pt: CGPoint, snapX: CGFloat, in size: CGSize) -> some View {
        Path { p in
            // 横线跟鼠标 y · 竖线吸附到 bar
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: snapX, y: 0))
            p.addLine(to: CGPoint(x: snapX, y: size.height))
        }
        .stroke(ChartTheme.crosshairLine,
                style: StrokeStyle(lineWidth: ChartTheme.crosshairLineWidth, dash: ChartTheme.crosshairDash))
        .allowsHitTesting(false)
    }

    private func spreadHoverTooltip(info: SpreadHoverInfo) -> some View {
        let upper = NSDecimalNumber(decimal: statistics.upperBand2σ).doubleValue
        let lower = NSDecimalNumber(decimal: statistics.lowerBand2σ).doubleValue
        let mean = NSDecimalNumber(decimal: statistics.mean).doubleValue
        let zText: String = info.zScore.map { String(format: "%.2f", $0) } ?? "—"
        let zColor: Color = info.zScore.map { abs($0) >= 2 ? .orange : ChartTheme.tooltipSecondary } ?? .secondary
        let sigText: String?
        let sigColor: Color
        if let s = info.signal {
            let action = s.action == .entry ? "进场" : "出场"
            let side = s.side == .long ? "做多" : "做空"
            sigText = "\(side) · \(action)"
            sigColor = s.side == .long ? ChartTheme.chartProfit : ChartTheme.chartLoss
        } else {
            sigText = nil
            sigColor = .secondary
        }
        let sv = spreadValues[info.index]
        let leg1 = NSDecimalNumber(decimal: sv.leg1Close).doubleValue
        let leg2 = NSDecimalNumber(decimal: sv.leg2Close).doubleValue
        let timeText = spreadHoverTimeFormatter.string(from: sv.openTime)
        return VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(ChartTheme.fontValue)
                .foregroundColor(ChartTheme.tooltipSecondary)
            Text("点 #\(info.index + 1) / \(spreadValues.count)")
                .font(ChartTheme.fontSubvalue)
                .foregroundColor(ChartTheme.tooltipMuted)
            Divider().background(ChartTheme.tooltipDivider)
            tooltipRow("价差", String(format: "%.2f", info.value), color: ChartTheme.chartLine)
            tooltipRow(selectedPair.leg1.instrumentID, String(format: "%.2f", leg1), color: ChartTheme.tooltipSecondary)
            tooltipRow(selectedPair.leg2.instrumentID, String(format: "%.2f", leg2), color: ChartTheme.tooltipSecondary)
            tooltipRow("均值", fmt(statistics.mean), color: ChartTheme.tooltipSecondary)
            tooltipRow("Z", zText, color: zColor)
            tooltipRow("+2σ", String(format: "%.2f", upper), color: ChartTheme.chartBandLineEmphasized)
            tooltipRow("-2σ", String(format: "%.2f", lower), color: ChartTheme.chartBandLineEmphasized)
            tooltipRow("距均", String(format: "%+.2f", info.value - mean),
                       color: info.value >= mean ? ChartTheme.chartProfit : ChartTheme.chartLoss)
            if let s = sigText {
                Divider().background(ChartTheme.tooltipDivider)
                tooltipRow("信号", s, color: sigColor)
            }
        }
        .padding(ChartTheme.tooltipPadding)
        .frame(width: 220, alignment: .leading)
        .background(ChartTheme.tooltipBackground)
        .cornerRadius(ChartTheme.tooltipCornerRadius)
        .overlay(RoundedRectangle(cornerRadius: ChartTheme.tooltipCornerRadius)
                    .stroke(ChartTheme.tooltipBorder, lineWidth: ChartTheme.tooltipBorderWidth))
    }

    private var spreadHoverTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch period {
        case .daily, .weekly:    f.dateFormat = "yyyy-MM-dd"
        case .monthly:           f.dateFormat = "yyyy-MM"
        case .minute30, .hour1:  f.dateFormat = "yy-MM-dd HH:mm"
        default:                 f.dateFormat = "MM-dd HH:mm"
        }
        return f
    }

    private func tooltipRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ChartTheme.fontLabel)
                .foregroundColor(ChartTheme.tooltipLabel)
                .frame(width: 32, alignment: .leading)
            Text(value)
                .font(ChartTheme.fontValue)
                .foregroundColor(color)
            Spacer()
        }
    }

    /// 默认右下偏移 · 接边翻转
    private func tooltipPosition(near pt: CGPoint, in size: CGSize, tooltipSize: CGSize) -> CGPoint {
        let dx: CGFloat = pt.x + 12 + tooltipSize.width / 2 < size.width
            ? tooltipSize.width / 2 + 12
            : -tooltipSize.width / 2 - 12
        let dy: CGFloat = pt.y + 12 + tooltipSize.height / 2 < size.height
            ? tooltipSize.height / 2 + 12
            : -tooltipSize.height / 2 - 12
        return CGPoint(x: pt.x + dx, y: pt.y + dy)
    }

    private func drawSpread(_ ctx: GraphicsContext, size: CGSize) {
        guard spreadValues.count >= 2 else {
            let text = Text("等待数据 · \(spreadValues.count) 点")
                .font(.system(size: 12)).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }

        let values = spreadValues.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        let mean = NSDecimalNumber(decimal: statistics.mean).doubleValue
        let upper = NSDecimalNumber(decimal: statistics.upperBand2σ).doubleValue
        let lower = NSDecimalNumber(decimal: statistics.lowerBand2σ).doubleValue

        guard let minV = values.min(), let maxV = values.max() else { return }
        // 视图范围扩到 ±2σ + 价差极值（双方取宽）
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

        // ±2σ 通道（橙色虚线）
        var upperLine = Path()
        upperLine.move(to: CGPoint(x: 0, y: yFor(upper)))
        upperLine.addLine(to: CGPoint(x: size.width, y: yFor(upper)))
        ctx.stroke(upperLine, with: .color(ChartTheme.chartBandLine),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        var lowerLine = Path()
        lowerLine.move(to: CGPoint(x: 0, y: yFor(lower)))
        lowerLine.addLine(to: CGPoint(x: size.width, y: yFor(lower)))
        ctx.stroke(lowerLine, with: .color(ChartTheme.chartBandLine),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        // 均值中线（白色虚线）
        var meanLine = Path()
        meanLine.move(to: CGPoint(x: 0, y: yFor(mean)))
        meanLine.addLine(to: CGPoint(x: size.width, y: yFor(mean)))
        ctx.stroke(meanLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 价差折线（cyan）
        var path = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: yFor(v))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(ChartTheme.chartLine),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // 终点圆点
        let lastIdx = values.count - 1
        let lastPt = CGPoint(x: CGFloat(lastIdx) * step, y: yFor(values[lastIdx]))
        let dot = Path(ellipseIn: CGRect(x: lastPt.x - 3.5, y: lastPt.y - 3.5, width: 7, height: 7))
        ctx.fill(dot, with: .color(ChartTheme.chartLine))

        // v15.37 V2 · 信号点（▲ entry / ▼ exit · 红做空 / 绿做多）
        for sig in signals where sig.index < values.count {
            let x = CGFloat(sig.index) * step
            let y = yFor(values[sig.index])
            drawSignalMarker(ctx: ctx, at: CGPoint(x: x, y: y), signal: sig)
        }
    }

    /// 信号 marker：上三角 = entry · 下三角 = exit · 颜色按 side
    private func drawSignalMarker(ctx: GraphicsContext, at point: CGPoint, signal: SpreadSignal) {
        let color: Color
        switch signal.side {
        case .long:  color = ChartTheme.chartProfit
        case .short: color = ChartTheme.chartLoss
        }
        var path = Path()
        let size: CGFloat = 6
        switch signal.action {
        case .entry:
            // 上三角（▲）· entry 位置在点上方稍微偏移
            let cx = point.x
            let cy = point.y - 10
            path.move(to: CGPoint(x: cx, y: cy - size))
            path.addLine(to: CGPoint(x: cx - size, y: cy + size))
            path.addLine(to: CGPoint(x: cx + size, y: cy + size))
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
            ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.6)
        case .exit:
            // 下三角（▼）· exit 在点下方
            let cx = point.x
            let cy = point.y + 10
            path.move(to: CGPoint(x: cx, y: cy + size))
            path.addLine(to: CGPoint(x: cx - size, y: cy - size))
            path.addLine(to: CGPoint(x: cx + size, y: cy - size))
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.7)))
            ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 0.6)
        }
    }

    // MARK: - V2 副图（直方图 / 滚动 Z）

    @ViewBuilder
    private var subChartView: some View {
        Canvas { ctx, size in
            switch subChartMode {
            case .none:      break
            case .histogram: drawHistogram(ctx: ctx, size: size)
                            // header label 单独画在 onSubChartLabel
            case .rollingZ:  drawRollingZ(ctx: ctx, size: size)
            }
        }
        .background(ChartTheme.dark.background)
    }

    private func drawHistogram(ctx: GraphicsContext, size: CGSize) {
        let h = histogram
        guard !h.bins.isEmpty else {
            let text = Text("无直方图数据").font(.system(size: 11)).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        let maxC = h.bins.map { $0.count }.max() ?? 1
        let binW = size.width / CGFloat(h.bins.count)
        let pad: CGFloat = 1
        for (i, bin) in h.bins.enumerated() {
            let normalized = Double(bin.count) / Double(max(maxC, 1))
            let height = CGFloat(normalized) * (size.height - 16)
            let rect = CGRect(
                x: CGFloat(i) * binW + pad,
                y: size.height - height,
                width: binW - 2 * pad,
                height: height
            )
            let isCurrent = i == h.currentBinIndex
            let isMode = i == h.modeBinIndex
            let color: Color
            if isCurrent { color = ChartTheme.chartLine }
            else if isMode { color = .yellow.opacity(0.7) }
            else { color = .gray.opacity(0.55) }
            ctx.fill(Path(rect), with: .color(color))
        }
        // 顶部标题
        let title = Text("📊 价差分布（\(h.bins.count) bins · cyan=当前 · yellow=众数 · 共 \(h.totalCount) 样本）")
            .font(ChartTheme.fontSubvalue)
            .foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    private func drawRollingZ(ctx: GraphicsContext, size: CGSize) {
        guard rollingZScores.count >= 2 else {
            let text = Text("滚动 Z 不足（窗口 \(rollingWindow)）")
                .font(ChartTheme.fontValue).foregroundColor(.secondary)
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
            return
        }
        // Y 范围 [-3.5, 3.5]（覆盖大部分极值 · 极端值会出范围）
        let viewMin: Double = -3.5
        let viewMax: Double = 3.5
        let n = rollingZScores.count
        let step = size.width / CGFloat(n - 1)
        func yFor(_ z: Double) -> CGFloat {
            CGFloat(1 - (z - viewMin) / (viewMax - viewMin)) * size.height
        }
        // ±2σ 阈值线（橙虚）
        for level: Double in [2, -2] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: yFor(level)))
            line.addLine(to: CGPoint(x: size.width, y: yFor(level)))
            ctx.stroke(line, with: .color(ChartTheme.chartBandLine),
                       style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        }
        // 0 线（白虚）
        var zeroLine = Path()
        zeroLine.move(to: CGPoint(x: 0, y: yFor(0)))
        zeroLine.addLine(to: CGPoint(x: size.width, y: yFor(0)))
        ctx.stroke(zeroLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
        // Z 折线（cyan）
        var path = Path()
        for (i, z) in rollingZScores.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * step, y: yFor(z))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(ChartTheme.chartLine.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        // 标题
        let title = Text("📈 滚动 Z-score（窗口 \(rollingWindow) · 橙线 ±2σ 阈值）")
            .font(ChartTheme.fontSubvalue)
            .foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    // MARK: - 数据加载

    private func reload() {
        let pair = selectedPair
        // v1 mock：合成两腿 K 线 · v2 接 SinaMarketData
        let leg1Bars = MockSpreadData.bars(
            instrumentID: pair.leg1.instrumentID,
            basePrice: defaultBasePrice(pair.leg1.instrumentID),
            period: period,
            count: 200
        )
        let leg2Bars = MockSpreadData.bars(
            instrumentID: pair.leg2.instrumentID,
            basePrice: defaultBasePrice(pair.leg2.instrumentID),
            period: period,
            count: 200,
            seed: pair.id.hashValue ^ 0x1F   // 第 2 腿不同 seed · 不完全相关
        )
        spreadValues = SpreadCalculator.calculate(pair: pair, leg1Bars: leg1Bars, leg2Bars: leg2Bars)
        statistics = SpreadStatisticsCalculator.compute(spreadValues)
        recomputeV2()
    }

    /// v15.37 V2 · 重算滚动 Z + 信号 + 直方图（reload 后 / Z 窗口变化时调）
    private func recomputeV2() {
        rollingZScores = SpreadStatisticsCalculator.rollingZScores(spreadValues, window: rollingWindow)
        signals = SpreadSignalGenerator.generate(values: spreadValues, rollingZScores: rollingZScores)
        histogram = SpreadHistogramCalculator.compute(spreadValues)
    }

    private func fmt(_ v: Decimal) -> String {
        let d = NSDecimalNumber(decimal: v).doubleValue
        if abs(d) >= 1000 { return String(format: "%.0f", d) }
        if abs(d) >= 10   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private func defaultBasePrice(_ id: String) -> Double {
        // 复用 MockQuote.table（没用 import 简化 · v1 hardcoded 默认）
        switch id {
        case "RB0":  return 3245
        case "HC0":  return 3450
        case "J0":   return 1925
        case "JM0":  return 1180
        case "M0":   return 3180
        case "Y0":   return 8240
        case "P0":   return 8920
        case "OI0":  return 9180
        case "AU0":  return 612.5
        case "AG0":  return 7890
        case "CU0":  return 78650
        case "AL0":  return 19450
        case "IF0":  return 3856.4
        case "IH0":  return 2820.8
        case "IC0":  return 5680.2
        case "IM0":  return 6420.5
        case "T0":   return 104.85
        case "TF0":  return 103.42
        case "TS0":  return 101.85
        case "TL0":  return 108.20
        default:     return 1000
        }
    }
}

// MARK: - Mock 数据生成器

private enum MockSpreadData {
    /// 合成 K 线：random walk + 周期波动（让套利图有 mean-reverting 视觉效果）
    static func bars(
        instrumentID: String, basePrice: Double, period: KLinePeriod,
        count: Int = 200, seed: Int? = nil
    ) -> [KLine] {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed ?? instrumentID.hashValue)))
        let stepSec = TimeInterval(period.seconds)
        let baseTime = Date().addingTimeInterval(-Double(count) * stepSec)

        var price = basePrice
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        for i in 0..<count {
            // 周期 sin 波 + 小幅 random walk · 价差自然 mean-revert
            let cycle = sin(Double(i) * 0.1) * basePrice * 0.005
            let noise = rng.nextDouble(in: -0.002...0.002) * basePrice
            price = basePrice + cycle + noise + (price - basePrice) * 0.95
            let high = price + abs(noise) + 0.5
            let low = price - abs(noise) - 0.5
            bars.append(KLine(
                instrumentID: instrumentID, period: period,
                openTime: baseTime.addingTimeInterval(TimeInterval(i) * stepSec),
                open: Decimal(price - noise * 0.3),
                high: Decimal(high), low: Decimal(low), close: Decimal(price),
                volume: 100 + Int(abs(noise) * 100),
                openInterest: 0, turnover: 0
            ))
        }
        return bars
    }
}

// MARK: - 简单 seeded RNG（避免 SystemRandomNumberGenerator 跨预设 reload 同种）

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xCAFEBABE : seed }
    mutating func next() -> UInt64 {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let u = Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}

// MARK: - KLinePeriod helper

private extension KLinePeriod {
    var seconds: Int {
        switch self {
        case .minute1:  return 60
        case .minute5:  return 300
        case .minute15: return 900
        case .minute30: return 1800
        case .hour1:    return 3600
        case .daily:    return 86400
        default:        return 60
        }
    }
}

#endif
