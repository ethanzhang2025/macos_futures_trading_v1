// 品种深度分析窗口（v15.51 · ⌘⌥I · 单合约一站式仪表盘）
//
// trader "选合约 → 一眼看完所有相关信息"：
//   - 顶部：合约选择器 + 板块过滤
//   - 中部：合约 mock K 线（折线版 · 200 点）+ 价格统计 HUD
//   - 右侧：4 卡片 metadata + 板块情绪 + 相关品种 + 跨窗口跳转按钮
//   - 与 ⌘⌥B/H/P/C/N/X 形成"全市场 → 单品种"双向闭环：
//     ⌘⌥H/B 找标的 → ⌘⌥I 深度看 → 主图 K 线 / ⌘⌥C 找联动 / ⌘⌥X 跨期套利

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore

struct InstrumentDashboardWindow: View {

    @State private var selectedID: String = "RB0"
    @State private var sectorFilter: SectorFilter = .all
    @State private var hoverPoint: CGPoint?
    /// v15.51 · 相关品种 cache（避免 hover 重绘时反复跑 60×60 correlation 矩阵）
    @State private var cachedRelated: (positive: [(SectorInstrument, Double)], negative: [(SectorInstrument, Double)]) = ([], [])
    /// v15.51 · mock K 线 cache（同样避免重绘时反复 RNG）
    @State private var cachedSeries: [Double] = []
    @Environment(\.openWindow) private var openWindow

    enum SectorFilter: Hashable, Identifiable {
        case all
        case sector(Sector)
        var id: String {
            switch self {
            case .all: return "all"
            case .sector(let s): return s.id
            }
        }
        var displayName: String {
            switch self {
            case .all: return "全部"
            case .sector(let s): return s.displayName
            }
        }
    }

    private var instruments: [SectorInstrument] {
        switch sectorFilter {
        case .all: return SectorPresets.all
        case .sector(let s): return SectorPresets.instruments(in: s)
        }
    }

    private var selected: SectorInstrument? {
        SectorPresets.byID[selectedID]
    }

    /// 板块联动统计（轻量 · 11 品种 · 不缓存）
    private var sectorStats: SectorStatistics? {
        guard let inst = selected else { return nil }
        let list = SectorPresets.instruments(in: inst.sector)
        return SectorStatisticsCalculator.compute(list, sector: inst.sector)
    }

    /// 重算 cache（仅 selectedID 变化时调 · 避免 hover 重绘卡顿）
    private func refreshCache() {
        guard let inst = selected else {
            cachedSeries = []
            cachedRelated = ([], [])
            return
        }
        // mock K 线（200 点单品种 · 毫秒级）
        let single = CorrelationMockSeries.generate(for: [inst], count: 200)
        cachedSeries = single[inst.id] ?? []

        // 相关品种（60 品种 × 100 点 → 60×60 corrs · 几十 ms）
        let pool = SectorPresets.all
        let series = CorrelationMockSeries.generate(for: pool, count: 100)
        guard let mySeries = series[inst.id] else {
            cachedRelated = ([], [])
            return
        }
        var corrs: [(SectorInstrument, Double)] = []
        for other in pool where other.id != inst.id {
            guard let otherSeries = series[other.id] else { continue }
            let r = CorrelationCalculator.priceCorrelation(mySeries, otherSeries)
            corrs.append((other, r))
        }
        let sorted = corrs.sorted { $0.1 > $1.1 }
        let pos = Array(sorted.prefix(5))
        let neg = Array(sorted.suffix(5).reversed())
        cachedRelated = (pos, neg)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                leftPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                rightPane
                    .frame(width: 340)
            }
        }
        .frame(minWidth: 1180, minHeight: 740)
        .onAppear { refreshCache() }
        .onChange(of: selectedID) { _ in refreshCache() }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时直接显示该合约（同步切板块过滤）
            if let id = note.object as? String, SectorPresets.byID[id] != nil {
                if let sec = SectorPresets.byID[id]?.sector {
                    sectorFilter = .sector(sec)
                }
                selectedID = id   // 触发 onChange → refreshCache
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("板块").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $sectorFilter) {
                    Text("全部").tag(SectorFilter.all)
                    ForEach(Sector.allCases) { sec in
                        Text(sec.displayName).tag(SectorFilter.sector(sec))
                    }
                }
                .frame(width: 120)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("合约").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $selectedID) {
                    ForEach(instruments) { inst in
                        Text("\(inst.id) · \(inst.name)").tag(inst.id)
                    }
                }
                .frame(width: 200)
                .labelsHidden()
            }

            Spacer()

            // 跨窗口跳转按钮
            HStack(spacing: 8) {
                jumpButton("主图", systemImage: "chart.xyaxis.line", id: "chart") {
                    NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: selectedID)
                }
                jumpButton("板块", systemImage: "square.stack.3d.down.right", id: "sector")
                jumpButton("热力图", systemImage: "square.grid.4x3.fill", id: "heatmap")
                jumpButton("关联", systemImage: "link", id: "correlation")
                jumpButton("跨期", systemImage: "calendar", id: "calendarSpread")
            }
            .controlSize(.small)
            .padding(.trailing, 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func jumpButton(_ label: String, systemImage: String, id: String,
                            action: (() -> Void)? = nil) -> some View {
        Button {
            openWindow(id: id)
            action?()
        } label: {
            Label(label, systemImage: systemImage).font(.caption)
        }
    }

    // MARK: - 左侧：mock K 线 + HUD

    private var leftPane: some View {
        VStack(spacing: 0) {
            instrumentHeader
            Divider()
            priceHUD
            Divider()
            mockChart
                .frame(maxHeight: .infinity)
        }
    }

    private var instrumentHeader: some View {
        guard let inst = selected else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let changeColor: Color = inst.changePct > 0 ? ChartTheme.chartLoss
                              : (inst.changePct < 0 ? ChartTheme.chartProfit : .secondary)
        return AnyView(HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(inst.name).font(.title2.bold())
                    Text(inst.id).font(.callout.monospaced()).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: inst.sector.icon).font(.caption)
                        Text(inst.sector.displayName).font(.caption)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.10))
                    .cornerRadius(3)
                    .foregroundColor(.secondary)
                }
                Text("\(formatPrice(inst.lastPrice))")
                    .font(.system(size: 28, design: .monospaced).bold())
                    .foregroundColor(changeColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.title3.monospaced().bold())
                    .foregroundColor(changeColor)
                Text(String(format: "持仓 %.0fK", inst.openInterestK))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12))
    }

    private var priceHUD: some View {
        let series = cachedSeries
        guard !series.isEmpty else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let high = series.max() ?? 0
        let low = series.min() ?? 0
        let avg = series.reduce(0, +) / Double(series.count)
        let amp = (high - low) / avg * 100
        // 简易动量：最后 10 根 vs 前 10 根
        let lastN = Array(series.suffix(10))
        let firstN = Array(series.prefix(10))
        let momentum = (lastN.reduce(0, +) / Double(lastN.count)) - (firstN.reduce(0, +) / Double(firstN.count))
        let momPct = momentum / avg * 100
        let momColor: Color = momPct > 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit
        return AnyView(HStack(spacing: 22) {
            statBlock("200 日高", String(format: "%.2f", high), color: ChartTheme.chartLoss)
            statBlock("200 日低", String(format: "%.2f", low), color: ChartTheme.chartProfit)
            statBlock("均值", String(format: "%.2f", avg), color: .secondary)
            statBlock("振幅", String(format: "%.1f%%", amp), color: .yellow)
            Divider().frame(height: 24)
            statBlock("近 10 动量", String(format: "%+.2f%%", momPct), color: momColor)
            statBlock("态势", momPct > 1 ? "趋势上行" : (momPct < -1 ? "趋势下行" : "震荡"),
                     color: momColor)
            Spacer()
            Text("v1 mock · 200 日时序")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06)))
    }

    private var mockChart: some View {
        GeometryReader { geom in
            ZStack {
                Canvas { ctx, size in
                    drawMockChart(ctx: ctx, size: size)
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

                if let pt = hoverPoint, !cachedSeries.isEmpty {
                    chartCrosshair(at: pt, in: geom.size)
                }
            }
        }
    }

    private func drawMockChart(ctx: GraphicsContext, size: CGSize) {
        let series = cachedSeries
        guard series.count >= 2 else { return }
        guard let lo = series.min(), let hi = series.max(), hi > lo else { return }
        let pad = (hi - lo) * 0.08
        let viewMin = lo - pad
        let viewMax = hi + pad
        let viewRange = max(0.01, viewMax - viewMin)
        let xStep = size.width / CGFloat(series.count - 1)

        func yFor(_ v: Double) -> CGFloat {
            CGFloat(1 - (v - viewMin) / viewRange) * size.height
        }

        // 均值线
        let avg = series.reduce(0, +) / Double(series.count)
        var meanLine = Path()
        meanLine.move(to: CGPoint(x: 0, y: yFor(avg)))
        meanLine.addLine(to: CGPoint(x: size.width, y: yFor(avg)))
        ctx.stroke(meanLine, with: .color(ChartTheme.chartLineSecondary),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        // 折线 · 分段染色（涨段红 / 跌段绿）
        for i in 0..<(series.count - 1) {
            let v1 = series[i]
            let v2 = series[i + 1]
            let x1 = CGFloat(i) * xStep
            let x2 = CGFloat(i + 1) * xStep
            var seg = Path()
            seg.move(to: CGPoint(x: x1, y: yFor(v1)))
            seg.addLine(to: CGPoint(x: x2, y: yFor(v2)))
            let color: Color = v2 >= v1 ? ChartTheme.chartLoss.opacity(0.85)
                                        : ChartTheme.chartProfit.opacity(0.85)
            ctx.stroke(seg, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // 末点圆点
        let lastIdx = series.count - 1
        let lastPt = CGPoint(x: CGFloat(lastIdx) * xStep, y: yFor(series[lastIdx]))
        let dot = Path(ellipseIn: CGRect(x: lastPt.x - 4, y: lastPt.y - 4, width: 8, height: 8))
        ctx.fill(dot, with: .color(ChartTheme.chartLine))

        // 标题
        let title = Text("📈 mock 价格曲线（200 日 · v2 接 CTP 真历史 K 线）")
            .font(ChartTheme.fontSubvalue).foregroundColor(.secondary)
        ctx.draw(title, at: CGPoint(x: 8, y: 6), anchor: .topLeading)
    }

    private func chartCrosshair(at pt: CGPoint, in size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: pt.y))
            p.addLine(to: CGPoint(x: size.width, y: pt.y))
            p.move(to: CGPoint(x: pt.x, y: 0))
            p.addLine(to: CGPoint(x: pt.x, y: size.height))
        }
        .stroke(ChartTheme.crosshairLine,
                style: StrokeStyle(lineWidth: ChartTheme.crosshairLineWidth, dash: ChartTheme.crosshairDash))
        .allowsHitTesting(false)
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    // MARK: - 右侧：板块联动 + 相关品种

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectorPanel
                Divider()
                relatedInstrumentsPanel
                Divider()
                tradingTips
            }
            .padding(14)
        }
    }

    private var sectorPanel: some View {
        guard let inst = selected, let stats = sectorStats else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let avgColor: Color = stats.avgChangePct > 0.3 ? ChartTheme.chartLoss
                            : (stats.avgChangePct < -0.3 ? ChartTheme.chartProfit : .secondary)
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: inst.sector.icon).font(.callout.bold())
                Text(inst.sector.displayName).font(.subheadline.bold())
                Spacer()
                Text(String(format: "均 %+.2f%%", stats.avgChangePct))
                    .font(.caption.monospaced())
                    .foregroundColor(avgColor)
            }
            HStack(spacing: 16) {
                statTile("家数", "\(stats.totalCount)", color: .secondary)
                statTile("涨", "\(stats.gainers)", color: ChartTheme.chartLoss)
                statTile("跌", "\(stats.losers)", color: ChartTheme.chartProfit)
            }
            // 多空偏向
            VStack(alignment: .leading, spacing: 3) {
                Text("板块多空偏向").font(.caption2).foregroundColor(.secondary)
                bullBiasBar(bias: stats.bullBias)
            }
            // 龙头/弱势
            if let strong = stats.strongest {
                jumpRow(emoji: "🔥", label: "龙头", inst: strong)
            }
            if let weak = stats.weakest, weak.id != stats.strongest?.id {
                jumpRow(emoji: "❄️", label: "弱势", inst: weak)
            }
        })
    }

    private func statTile(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    private func bullBiasBar(bias: Double) -> some View {
        let pct = (bias + 1) / 2
        let color: Color = bias > 0 ? ChartTheme.chartLoss : (bias < 0 ? ChartTheme.chartProfit : .secondary)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, 200 * pct), height: 8)
            }
            .frame(width: 200)
            Text(String(format: "%+.0f%%", bias * 100))
                .font(.caption.monospaced())
                .foregroundColor(color)
        }
    }

    private func jumpRow(emoji: String, label: String, inst: SectorInstrument) -> some View {
        Button {
            selectedID = inst.id
        } label: {
            HStack(spacing: 6) {
                Text(emoji).font(.caption)
                Text(label).font(.caption.bold()).foregroundColor(.secondary).frame(width: 30, alignment: .leading)
                Text("\(inst.name)（\(inst.id)）")
                    .font(.caption.monospaced())
                Spacer()
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.caption.monospaced())
                    .foregroundColor(inst.changePct >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip("点击切到 \(inst.name)")
    }

    private var relatedInstrumentsPanel: some View {
        let related = cachedRelated
        return VStack(alignment: .leading, spacing: 8) {
            Text("📊 相关品种 TOP 5").font(.subheadline.bold())

            if !related.positive.isEmpty {
                Text("正相关（套利候选）").font(.caption.bold()).foregroundColor(.orange)
                ForEach(related.positive, id: \.0.id) { (inst, r) in
                    relatedRow(inst: inst, r: r, color: .orange)
                }
            }

            if !related.negative.isEmpty {
                Text("负相关（对冲候选）").font(.caption.bold()).foregroundColor(.blue).padding(.top, 4)
                ForEach(related.negative, id: \.0.id) { (inst, r) in
                    relatedRow(inst: inst, r: r, color: .blue)
                }
            }
        }
    }

    private func relatedRow(inst: SectorInstrument, r: Double, color: Color) -> some View {
        Button {
            selectedID = inst.id
        } label: {
            HStack(spacing: 6) {
                Text(inst.id).font(.caption.monospaced().bold())
                    .frame(width: 50, alignment: .leading)
                Text(inst.name).font(.caption).foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "r=%+.2f", r))
                    .font(.caption.monospaced().bold())
                    .foregroundColor(color)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.06))
            .cornerRadius(3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip("点击切到 \(inst.name) · r=\(String(format: "%.3f", r))")
    }

    private var tradingTips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💡 交易提示").font(.subheadline.bold())
            tipLine("→ 看主图详细 K 线：点 ⌘⌥I 顶部「主图」")
            tipLine("→ 跨期套利：点「跨期」找该品种近-远月")
            tipLine("→ 找对冲品种：负相关（蓝）r < -0.5 优先")
            tipLine("→ 板块联动：龙头/弱势异动可联动到该品种")
        }
    }

    private func tipLine(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if abs(d) >= 10000 { return String(format: "%.0f", d) }
        if abs(d) >= 100   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }
}

#endif
