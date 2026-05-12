// 多空持仓分布窗口（v15.47 · ⌘⌥P · 全市场多空持仓占比 + 净持仓视图）
//
// 设计：
//   - 60+ 品种横条图 · 中点对齐
//   - 左红多头 / 右绿空头 · 长度按 mock 多空比
//   - 净持仓数值 + 颜色标记（多头主导红 / 空头主导绿）
//   - mock 公式：bullRatio = 0.5 + (changePct / 8) · 涨多 = 多头加仓 · 跌多 = 空头加仓
//     v2 接 CTP 持仓数据 / 龙虎榜接口 (CFTC 类似数据接口)
//
// trader 用法：
//   - 看板块多空一致性（同板块品种是否一致看多/看空）
//   - 找异动品种（净持仓与价格背离 = 异动信号）
//   - 与 ⌘⌥B 板块联动 / ⌘⌥H 热力图互补：⌘⌥P 看多空力量 · 不只看价格

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct PositionWindow: View {

    @State private var sectorFilter: SectorFilter = .all
    @State private var sortField: SortField = .netPosition
    @State private var sortDescending: Bool = true
    @Environment(\.openWindow) private var openWindow

    /// v17.109 · 用户 K 线配色偏好（跟 ChartScene/Settings 同步 · 涨跌色 swap 用）
    @State private var candleColorMode: CandleColorMode = ChartSettingsStore.loadCandleColorMode()
    /// v17.120 · 用户字号档（跟 ChartScene/Settings 同步）
    @State private var chartFontSize: ChartFontSize = ChartSettingsStore.loadChartFontSize()

    // v17.109 · 涨跌色（跟 candleColorMode swap · 中国习惯红涨绿跌 / 国际相反）
    private var chartProfit: Color { chartProfitColor(mode: candleColorMode) }
    private var chartLoss: Color { chartLossColor(mode: candleColorMode) }

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

    enum SortField: String, CaseIterable, Identifiable {
        case netPosition       // 净持仓（多 - 空）
        case bullRatio         // 多头占比
        case totalOI           // 总持仓
        case changePct         // 涨跌幅

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .netPosition: return "净持仓"
            case .bullRatio:   return "多头比"
            case .totalOI:     return "总持仓"
            case .changePct:   return "涨跌幅"
            }
        }
    }

    /// 单品种多空持仓 mock（基于 SectorInstrument 推定）
    struct PositionRow: Identifiable {
        let inst: SectorInstrument
        let bullRatio: Double       // [0, 1] 多头持仓比
        let bearRatio: Double       // [0, 1] 空头持仓比
        let bullOI: Double          // 多头持仓量（K 单位）
        let bearOI: Double          // 空头持仓量（K 单位）
        let netOI: Double           // 净持仓（多 - 空）

        var id: String { inst.id }
    }

    private var rows: [PositionRow] {
        let pool: [SectorInstrument]
        switch sectorFilter {
        case .all: pool = SectorPresets.all
        case .sector(let s): pool = SectorPresets.instruments(in: s)
        }
        let withMock = pool.map { positionRow(for: $0) }
        return sorted(withMock)
    }

    /// v15.82 · 全市场 combo 异常映射（与 ⌘⌥H/B/N/L 同跨窗口视觉）
    private var comboMap: [String: ComboAnomaly] {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        let combos = ComboAnomalyAggregator.aggregate(events: result.events, minKinds: 3)
        return Dictionary(uniqueKeysWithValues: combos.map { ($0.instrumentID, $0) })
    }

    private func positionRow(for inst: SectorInstrument) -> PositionRow {
        // mock 公式：涨幅推多空 · clamp [0.30, 0.70]
        let raw = 0.5 + inst.changePct / 8.0
        let bullRatio = max(0.30, min(0.70, raw))
        let bearRatio = 1.0 - bullRatio
        let bullOI = inst.openInterestK * bullRatio
        let bearOI = inst.openInterestK * bearRatio
        let netOI = bullOI - bearOI
        return PositionRow(inst: inst, bullRatio: bullRatio, bearRatio: bearRatio,
                           bullOI: bullOI, bearOI: bearOI, netOI: netOI)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statsBar
            Divider()
            positionTable
            Divider()
            legendBar
        }
        .frame(minWidth: 1000, minHeight: 640)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时自动切到该合约的板块
            if let id = note.object as? String, let sec = SectorPresets.byID[id]?.sector {
                sectorFilter = .sector(sec)
            }
        }
        // v17.109 · 同步用户 K 线配色偏好（Settings → 国际习惯 → 涨跌色 swap）
        // v17.120 · 同步字号档
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let newMode = ChartSettingsStore.loadCandleColorMode()
            if newMode != candleColorMode { candleColorMode = newMode }
            let newFontSize = ChartSettingsStore.loadChartFontSize()
            if newFontSize != chartFontSize { chartFontSize = newFontSize }
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
                .frame(width: 130)
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("排序").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $sortField) {
                    ForEach(SortField.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .frame(width: 100)
                .labelsHidden()
                Button {
                    sortDescending.toggle()
                } label: {
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up").font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Text("v1 mock · 涨幅推多空（v2 接 CTP 持仓数据）")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 顶部统计

    private var statsBar: some View {
        let r = rows
        guard !r.isEmpty else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let totalOI = r.reduce(0.0) { $0 + $1.inst.openInterestK }
        let bullDominant = r.filter { $0.bullRatio > 0.5 }.count
        let bearDominant = r.filter { $0.bearRatio > 0.5 }.count
        let avgBull = r.reduce(0.0) { $0 + $1.bullRatio } / Double(r.count)
        return AnyView(HStack(spacing: 22) {
            statBlock("品种", "\(r.count)", color: .secondary)
            statBlock("多头主导", "\(bullDominant)", color: chartLoss)
            statBlock("空头主导", "\(bearDominant)", color: chartProfit)
            statBlock("均多头比",
                     String(format: "%.1f%%", avgBull * 100),
                     color: avgBull >= 0.5 ? chartLoss : chartProfit)
            statBlock("市场情绪",
                     avgBull >= 0.55 ? "偏多" : (avgBull <= 0.45 ? "偏空" : "中性"),
                     color: avgBull >= 0.55 ? chartLoss
                          : (avgBull <= 0.45 ? chartProfit : .secondary))
            Spacer()
            statBlock("总持仓", String(format: "%.0fK", totalOI), color: .secondary)
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

    // MARK: - 表格

    private var positionTable: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                cellHeader("代码", w: 70, alignment: .leading)
                cellHeader("名称", w: 90, alignment: .leading)
                cellHeader("涨跌", w: 65, alignment: .trailing)
                cellHeader("总持仓", w: 80, alignment: .trailing)
                cellHeader("多头持仓 ←|→ 空头持仓", w: 320, alignment: .center)
                cellHeader("多/空", w: 80, alignment: .center)
                cellHeader("净持仓", w: 80, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        positionRowView(row)
                    }
                }
            }
        }
    }

    private func positionRowView(_ row: PositionRow) -> some View {
        let inst = row.inst
        let changeColor: Color = inst.changePct > 0 ? chartLoss
                              : (inst.changePct < 0 ? chartProfit : .secondary)
        let netColor: Color = row.netOI > 0 ? chartLoss : chartProfit
        return Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst.id)
        } label: {
            HStack(spacing: 0) {
                Text(inst.id)
                    .font(.system(size: 12 + chartFontSize.sizeDelta, design: .monospaced).bold())
                    .foregroundColor(.primary)
                    .frame(width: 70, alignment: .leading)
                Text(inst.name)
                    .font(.system(size: 12 + chartFontSize.sizeDelta))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced))
                    .foregroundColor(changeColor)
                    .frame(width: 65, alignment: .trailing)
                Text(String(format: "%.0fK", inst.openInterestK))
                    .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
                bullBearBar(bullRatio: row.bullRatio, bearRatio: row.bearRatio,
                            bullOI: row.bullOI, bearOI: row.bearOI)
                    .frame(width: 320, height: 22)
                Text(String(format: "%.0f / %.0f",
                            row.bullRatio * 100, row.bearRatio * 100))
                    .font(.system(size: 10 + chartFontSize.sizeDelta, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .center)
                Text(String(format: "%+.0fK", row.netOI))
                    .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced).bold())
                    .foregroundColor(netColor)
                    .frame(width: 80, alignment: .trailing)
                // v15.82 · combo 徽章
                comboBadge(for: inst)
                    .frame(width: 56, alignment: .center)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(rowHelpText(inst, row: row))
    }

    @ViewBuilder
    private func comboBadge(for inst: SectorInstrument) -> some View {
        if let c = comboMap[inst.id] {
            HStack(spacing: 2) {
                Image(systemName: "sparkles").font(.system(size: 9 + chartFontSize.sizeDelta))
                Text("\(c.kindCount)/5").font(.system(size: 10 + chartFontSize.sizeDelta, design: .monospaced).bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(comboBadgeColor(c), in: RoundedRectangle(cornerRadius: 3))
        } else {
            Text("—").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
    }

    private func comboBadgeColor(_ c: ComboAnomaly) -> Color {
        if c.kindCount >= 5 { return chartLoss }
        if c.kindCount == 4 { return .orange }
        return .yellow
    }

    private func rowHelpText(_ inst: SectorInstrument, row: PositionRow) -> String {
        let base = "\(inst.name)（\(inst.id)） · 多 \(String(format: "%.0fK", row.bullOI)) / 空 \(String(format: "%.0fK", row.bearOI)) · 净 \(String(format: "%+.0fK", row.netOI)) · 点击切主图"
        guard let c = comboMap[inst.id] else { return base }
        let kindLabel = AnomalyKind.allCases
            .filter { c.kinds.contains($0) }
            .map(\.displayName)
            .joined(separator: " · ")
        return base + " · ✨ Combo \(c.kindCount)/5（\(kindLabel)）"
    }

    /// 多空横条：左红多 / 右绿空 · 中点对齐
    private func bullBearBar(bullRatio: Double, bearRatio: Double,
                             bullOI: Double, bearOI: Double) -> some View {
        GeometryReader { geom in
            let totalW = geom.size.width
            let bullW = totalW * bullRatio
            let bearW = totalW * bearRatio
            ZStack(alignment: .center) {
                // 背景轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: totalW, height: 14)
                // 多空条
                HStack(spacing: 0) {
                    // 左半：多头条（从中点向左生长）
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(chartLoss.opacity(0.85))
                            .frame(width: bullW * 0.95, height: 14)
                    }
                    // 右半：空头条（从中点向右生长）
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(chartProfit.opacity(0.85))
                            .frame(width: bearW * 0.95, height: 14)
                        Spacer()
                    }
                }
                // 中线
                Rectangle()
                    .fill(Color.white.opacity(0.50))
                    .frame(width: 1, height: 16)
                // OI 数值（左多 · 右空）
                HStack {
                    Text(String(format: "%.0fK", bullOI))
                        .font(.system(size: 9 + chartFontSize.sizeDelta, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.leading, 6)
                    Spacer()
                    Text(String(format: "%.0fK", bearOI))
                        .font(.system(size: 9 + chartFontSize.sizeDelta, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.trailing, 6)
                }
            }
        }
    }

    private func cellHeader(_ text: String, w: CGFloat, alignment: Alignment) -> some View {
        Text(text).font(.caption2).foregroundColor(.secondary)
            .frame(width: w, alignment: alignment)
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 22) {
            legendItem(color: chartLoss, text: "多头持仓（涨幅推算）")
            legendItem(color: chartProfit, text: "空头持仓")
            Text("净持仓 = 多 - 空 · 正=多头主导（红） · 负=空头主导（绿）")
                .font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text("点击行 · 切主图")
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

    // MARK: - 排序

    private func sorted(_ list: [PositionRow]) -> [PositionRow] {
        let asc = list.sorted { a, b in
            switch sortField {
            case .netPosition: return a.netOI < b.netOI
            case .bullRatio:   return a.bullRatio < b.bullRatio
            case .totalOI:     return a.inst.openInterestK < b.inst.openInterestK
            case .changePct:   return a.inst.changePct < b.inst.changePct
            }
        }
        return sortDescending ? asc.reversed() : asc
    }
}

#endif
