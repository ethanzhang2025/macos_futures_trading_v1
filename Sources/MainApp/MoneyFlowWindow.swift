// 资金流向窗口（v15.49 · ⌘⌥N · 全市场资金净流入排行 + 板块资金分布）
//
// 三维度市场情绪闭环（与 ⌘⌥B / ⌘⌥H / ⌘⌥P / ⌘⌥C 互补）：
//   - ⌘⌥B 板块联动：板块涨跌 + 多空偏向
//   - ⌘⌥H 行情热力：全市场涨跌染色网格
//   - ⌘⌥P 多空持仓：多空力量结构
//   - ⌘⌥N 资金流向：资金 inflow / outflow（本窗口 · 涨跌 × 持仓推算）
//   - ⌘⌥C 关联性：跨品种相关性
//
// mock 公式（v2 接 CTP 真持仓变化数据后整段废弃）：
//   netInflow = openInterestK × changePct × 0.5  （单位：百万元 · 估算）
//   涨且增仓 → 大量净流入 / 跌且减仓 → 资金抽离
//
// trader 用法：
//   - 找资金推动力最强的品种（净流入榜）· 趋势可能持续
//   - 找资金抽离最多的品种（净流出榜）· 反弹/趋势衰竭信号
//   - 板块资金分布 · 一图看全市场资金集中度

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct MoneyFlowWindow: View {

    @State private var sectorFilter: SectorFilter = .all
    @State private var topN: Int = 20
    @State private var viewMode: ViewMode = .ranking
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
            case .all: return "全市场"
            case .sector(let s): return s.displayName
            }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case ranking          // 资金流入榜（双向 TopN）
        case sectorBreakdown  // 板块资金分布

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ranking: return "流入榜"
            case .sectorBreakdown: return "板块分布"
            }
        }
    }

    /// 单品种资金流向 mock
    struct FlowRow: Identifiable {
        let inst: SectorInstrument
        let netInflow: Double      // 净流入（百万元）
        var id: String { inst.id }
    }

    private var allRows: [FlowRow] {
        SectorPresets.all.map { inst in
            // mock：净流入 = openInterestK × changePct × 0.5
            let inflow = inst.openInterestK * inst.changePct * 0.5
            return FlowRow(inst: inst, netInflow: inflow)
        }
    }

    private var filteredRows: [FlowRow] {
        switch sectorFilter {
        case .all: return allRows
        case .sector(let s): return allRows.filter { $0.inst.sector == s }
        }
    }

    /// v15.77 · 全市场 combo 异常映射 by instrumentID（统一跨窗口视觉）
    private var comboMap: [String: ComboAnomaly] {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        let combos = ComboAnomalyAggregator.aggregate(events: result.events, minKinds: 3)
        return Dictionary(uniqueKeysWithValues: combos.map { ($0.instrumentID, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statsBar
            Divider()
            switch viewMode {
            case .ranking:
                rankingView
            case .sectorBreakdown:
                sectorBreakdownView
            }
            Divider()
            legendBar
        }
        .frame(minWidth: 1080, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时自动切到该合约的板块
            if let id = note.object as? String, let sec = SectorPresets.byID[id]?.sector {
                sectorFilter = .sector(sec)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("视图").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("板块").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $sectorFilter) {
                    Text("全市场").tag(SectorFilter.all)
                    ForEach(Sector.allCases) { sec in
                        Text(sec.displayName).tag(SectorFilter.sector(sec))
                    }
                }
                .frame(width: 130)
                .labelsHidden()
            }

            if viewMode == .ranking {
                HStack(spacing: 6) {
                    Text("TopN").font(.callout).foregroundColor(.secondary)
                    Stepper(value: $topN, in: 5...30, step: 5) {
                        Text("\(topN)").font(.callout.monospaced()).frame(minWidth: 28)
                    }
                    .frame(width: 110)
                }
            }

            Spacer()

            Text("v1 mock · changePct × OI 推算 · v2 接 CTP 持仓变化")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 顶部统计

    private var statsBar: some View {
        let r = filteredRows
        guard !r.isEmpty else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let totalInflow = r.filter { $0.netInflow > 0 }.reduce(0.0) { $0 + $1.netInflow }
        let totalOutflow = -r.filter { $0.netInflow < 0 }.reduce(0.0) { $0 + $1.netInflow }
        let netTotal = totalInflow - totalOutflow
        let inflowCount = r.filter { $0.netInflow > 0 }.count
        let outflowCount = r.filter { $0.netInflow < 0 }.count
        return AnyView(HStack(spacing: 22) {
            statBlock("品种", "\(r.count)", color: .secondary)
            statBlock("流入", "\(inflowCount)", color: ChartTheme.chartLoss)
            statBlock("流出", "\(outflowCount)", color: ChartTheme.chartProfit)
            Divider().frame(height: 28)
            statBlock("总流入", String(format: "+%.1fM", totalInflow), color: ChartTheme.chartLoss)
            statBlock("总流出", String(format: "-%.1fM", totalOutflow), color: ChartTheme.chartProfit)
            statBlock("净额",
                     String(format: "%+.1fM", netTotal),
                     color: netTotal >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            Divider().frame(height: 28)
            statBlock("市场态势",
                     netTotal > 50 ? "资金流入" : (netTotal < -50 ? "资金流出" : "平衡"),
                     color: netTotal > 50 ? ChartTheme.chartLoss
                          : (netTotal < -50 ? ChartTheme.chartProfit : .secondary))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06)))
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
        }
    }

    // MARK: - 流入榜视图（双向 TopN）

    private var rankingView: some View {
        let sorted = filteredRows.sorted { $0.netInflow > $1.netInflow }
        let topInflow = Array(sorted.prefix(topN))
        let topOutflow = Array(sorted.suffix(topN).reversed())
        let maxAbs = max(
            (topInflow.first?.netInflow ?? 1).magnitude,
            (topOutflow.first?.netInflow ?? 1).magnitude,
            1.0
        )
        return HStack(spacing: 0) {
            rankingColumn(title: "🔴 净流入 TOP \(topN)", rows: topInflow,
                          color: ChartTheme.chartLoss, maxAbs: maxAbs)
            Divider()
            rankingColumn(title: "🟢 净流出 TOP \(topN)", rows: topOutflow,
                          color: ChartTheme.chartProfit, maxAbs: maxAbs)
        }
    }

    private func rankingColumn(title: String, rows: [FlowRow],
                               color: Color, maxAbs: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.callout.bold())
                Spacer()
                Text("\(rows.count) 项").font(.caption.monospaced()).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.secondary.opacity(0.06))
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(rows.indices, id: \.self) { i in
                        flowRowView(rank: i + 1, row: rows[i], color: color, maxAbs: maxAbs)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func flowRowView(rank: Int, row: FlowRow, color: Color, maxAbs: Double) -> some View {
        let inst = row.inst
        let absInflow = abs(row.netInflow)
        let barRatio = min(absInflow / maxAbs, 1.0)
        return Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst.id)
        } label: {
            HStack(spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Text(inst.id)
                    .font(.system(size: 11, design: .monospaced).bold())
                    .frame(width: 60, alignment: .leading)
                Text(inst.name)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(inst.changePct >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
                    .frame(width: 56, alignment: .trailing)
                // bar
                GeometryReader { geom in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.85))
                            .frame(width: max(2, geom.size.width * CGFloat(barRatio)), height: 14)
                    }
                }
                .frame(height: 16)
                Text(String(format: "%+.1fM", row.netInflow))
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(color)
                    .frame(width: 80, alignment: .trailing)
                // v15.77 · combo 徽章
                comboBadge(for: inst)
                    .frame(width: 56, alignment: .center)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(rowHelpText(inst, row: row))
    }

    /// v15.77 · 组合异常徽章（命中才显示）
    @ViewBuilder
    private func comboBadge(for inst: SectorInstrument) -> some View {
        if let c = comboMap[inst.id] {
            HStack(spacing: 2) {
                Image(systemName: "sparkles").font(.system(size: 9))
                Text("\(c.kindCount)/5").font(.system(size: 10, design: .monospaced).bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(comboBadgeColor(c), in: RoundedRectangle(cornerRadius: 3))
        } else {
            Text("—").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
    }

    private func comboBadgeColor(_ c: ComboAnomaly) -> Color {
        if c.kindCount >= 5 { return ChartTheme.chartLoss }
        if c.kindCount == 4 { return .orange }
        return .yellow
    }

    private func rowHelpText(_ inst: SectorInstrument, row: FlowRow) -> String {
        let base = "\(inst.name)（\(inst.id)）净流入 \(String(format: "%+.1fM", row.netInflow)) · 点击切主图"
        guard let c = comboMap[inst.id] else { return base }
        let kindLabel = AnomalyKind.allCases
            .filter { c.kinds.contains($0) }
            .map(\.displayName)
            .joined(separator: " · ")
        return base + " · ✨ Combo \(c.kindCount)/5（\(kindLabel)）"
    }

    // MARK: - 板块资金分布

    private var sectorBreakdownView: some View {
        let bySector: [Sector: Double] = {
            var dict: [Sector: Double] = [:]
            for sec in Sector.allCases {
                let inSec = allRows.filter { $0.inst.sector == sec }
                dict[sec] = inSec.reduce(0.0) { $0 + $1.netInflow }
            }
            return dict
        }()
        let sorted = Sector.allCases.map { ($0, bySector[$0] ?? 0) }
            .sorted { abs($0.1) > abs($1.1) }
        let maxAbs = max(sorted.first.map { abs($0.1) } ?? 1, 1)
        return ScrollView {
            VStack(spacing: 12) {
                ForEach(sorted, id: \.0) { (sec, value) in
                    sectorBreakdownRow(sector: sec, value: value, maxAbs: maxAbs, bySectorMap: bySector)
                }
            }
            .padding(14)
        }
    }

    private func sectorBreakdownRow(sector: Sector, value: Double, maxAbs: Double,
                                    bySectorMap: [Sector: Double]) -> some View {
        let isPositive = value >= 0
        let color: Color = isPositive ? ChartTheme.chartLoss : ChartTheme.chartProfit
        let barRatio = min(abs(value) / maxAbs, 1.0)
        let count = SectorPresets.instruments(in: sector).count
        return Button {
            sectorFilter = .sector(sector)
            viewMode = .ranking
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: sector.icon).font(.callout)
                    Text(sector.displayName).font(.callout.bold())
                    Text("(\(count))").font(.caption.monospaced()).foregroundColor(.secondary)
                }
                .frame(width: 130, alignment: .leading)
                .foregroundColor(color)
                GeometryReader { geom in
                    ZStack(alignment: isPositive ? .leading : .trailing) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(height: 22)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.75))
                            .frame(width: max(4, geom.size.width * CGFloat(barRatio)), height: 22)
                    }
                }
                .frame(height: 24)
                Text(String(format: "%+.1fM", value))
                    .font(.system(size: 13, design: .monospaced).bold())
                    .foregroundColor(color)
                    .frame(width: 100, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(sector.displayName)板块净流入 \(String(format: "%+.1fM", value)) · 点击查看该板块品种榜")
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 18) {
            legendItem(color: ChartTheme.chartLoss, text: "净流入（资金推涨）")
            legendItem(color: ChartTheme.chartProfit, text: "净流出（资金抽离）")
            Text("· 流入 = OI × changePct × 0.5（mock 公式）· 单位 M=百万元")
                .font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text("点击品种切主图 · 点击板块查该板块榜")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
    }
}

#endif
