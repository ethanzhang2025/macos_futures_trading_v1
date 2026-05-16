// 板块联动窗口（v15.43 · WP-行情 V3 · ⌘⌥B）
//
// 4 大区块（垂直分割）：
//   1. 顶部 toolbar：11 板块 Tab + 排序 Picker（涨跌/价格/持仓）
//   2. 板块统计 HUD：总数 / 涨家数 / 跌家数 / 平均涨幅 / 多空偏向进度条 / 最强 / 最弱 / 总持仓
//   3. 中部表格：该板块所有品种行（id / 名称 / 价格 / 涨跌幅 / 持仓量）
//   4. 底部 footer：板块说明 / 共 N 板块统计概览（横向迷你板块条）
//
// 设计意图：
// - trader 早盘 5 秒看完所有板块情绪 · 找龙头板块/弱势板块/进场标的
// - 与 ⌘L 自选合约（V2 · 自选维度）形成互补：⌘L 看自己的池 · ⌘⌥B 看全市场板块
// - 数据来自 SectorPresets · 60+ 主连续品种 · v2 接 CTP 真行情后整段废弃 mock

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

// MARK: - 主窗口

struct SectorWindow: View {

    @State private var selectedSector: Sector = .黑色
    @State private var sortField: SortField = .changePct
    @State private var sortDescending: Bool = true
    @Environment(\.openWindow) private var openWindow
    /// v17.241 · V1 主窗 monitor 区嵌入模式标识 · 嵌入时 minWidth/minHeight=0 防撑大 NSSplitView divider
    @Environment(\.isHostedInShell) private var isHostedInShell

    /// v17.108 · 用户 K 线配色偏好（跟 ChartScene/Settings 同步 · 涨跌色 swap 用）
    @State private var candleColorMode: CandleColorMode = ChartSettingsStore.loadCandleColorMode()

    /// v17.117 · 用户字号偏好
    @State private var chartFontSize: ChartFontSize = ChartSettingsStore.loadChartFontSize()

    // v17.108 · 涨跌色（跟 candleColorMode swap · 中国习惯红涨绿跌 / 国际相反）
    private var chartProfit: Color { chartProfitColor(mode: candleColorMode) }
    private var chartLoss: Color { chartLossColor(mode: candleColorMode) }

    enum SortField: String, CaseIterable, Identifiable {
        case changePct, lastPrice, openInterest, name
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .changePct:    return "涨跌幅"
            case .lastPrice:    return "价格"
            case .openInterest: return "持仓量"
            case .name:         return "名称"
            }
        }
    }

    private var instruments: [SectorInstrument] {
        let raw = SectorPresets.instruments(in: selectedSector)
        return sorted(raw)
    }

    private var statistics: SectorStatistics {
        SectorStatisticsCalculator.compute(SectorPresets.instruments(in: selectedSector),
                                           sector: selectedSector)
    }

    private var allSectorStats: [SectorStatistics] {
        SectorStatisticsCalculator.computeAll(SectorPresets.all)
    }

    /// v15.77 · 全市场 combo 异常映射 by instrumentID（统一跨窗口视觉语言）
    private var comboMap: [String: ComboAnomaly] {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        let combos = ComboAnomalyAggregator.aggregate(events: result.events, minKinds: 3)
        return Dictionary(uniqueKeysWithValues: combos.map { ($0.instrumentID, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            sectorTabBar
            Divider()
            statsHUD
            Divider()
            instrumentTable
            Divider()
            sectorOverviewFooter
        }
        // v17.241 · 嵌入模式（V1 主窗 monitor 段）minWidth/minHeight=0 防撑大外层 NSSplitView · 独立窗口仍保留 960x600
        .frame(minWidth: isHostedInShell ? 0 : 960, minHeight: isHostedInShell ? 0 : 600)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时自动切到该合约的板块
            if let id = note.object as? String, let sec = SectorPresets.byID[id]?.sector {
                selectedSector = sec
            }
        }
        // v17.108 · 同步用户 K 线配色偏好（Settings → 国际习惯 → 涨跌色 swap）
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let newMode = ChartSettingsStore.loadCandleColorMode()
            if newMode != candleColorMode { candleColorMode = newMode }
            // v17.117 · 字号偏好
            let newFontSize = ChartSettingsStore.loadChartFontSize()
            if newFontSize != chartFontSize { chartFontSize = newFontSize }
        }
    }

    // MARK: - 顶部板块 Tab + 排序

    private var sectorTabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Sector.allCases) { sec in
                        sectorTabButton(sec)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("排序").font(.caption).foregroundColor(.secondary)
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
                    Image(systemName: sortDescending ? "arrow.down" : "arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .tooltip(sortDescending ? "降序（点切换升序）" : "升序（点切换降序）")
            }
            .padding(.trailing, 14)
        }
        .padding(.vertical, 8)
    }

    private func sectorTabButton(_ sec: Sector) -> some View {
        let isSelected = sec == selectedSector
        let stats = allSectorStats.first { $0.sector == sec }
        let avgChange = stats?.avgChangePct ?? 0
        let bgTint: Color
        if avgChange > 0.5 { bgTint = chartLoss.opacity(isSelected ? 0.40 : 0.10) }   // 中国习惯涨红
        else if avgChange < -0.5 { bgTint = chartProfit.opacity(isSelected ? 0.40 : 0.10) }
        else { bgTint = Color.gray.opacity(isSelected ? 0.30 : 0.08) }
        return Button {
            selectedSector = sec
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sec.icon).font(.caption)
                Text(sec.displayName).font(.callout)
                if let s = stats {
                    Text(String(format: "%+.1f%%", s.avgChangePct))
                        .font(ChartTheme.fontHint(size: chartFontSize))
                        .foregroundColor(s.avgChangePct >= 0 ? chartLoss : chartProfit)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(bgTint)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 板块统计 HUD

    private var statsHUD: some View {
        let s = statistics
        return HStack(spacing: 22) {
            statBlock("品种", "\(s.totalCount)", color: .secondary)
            statBlock("涨", "\(s.gainers)", color: chartLoss)
            statBlock("跌", "\(s.losers)", color: chartProfit)
            if s.unchanged > 0 {
                statBlock("平", "\(s.unchanged)", color: .secondary)
            }
            statBlock("均涨幅",
                     String(format: "%+.2f%%", s.avgChangePct),
                     color: s.avgChangePct >= 0 ? chartLoss : chartProfit)
            Divider().frame(height: 28)
            // 多空偏向进度条
            bullBiasBar(bias: s.bullBias)
            Divider().frame(height: 28)
            if let strong = s.strongest {
                statBlockWide("龙头",
                              "\(strong.name) \(String(format: "%+.2f%%", strong.changePct))",
                              color: chartLoss)
            }
            if let weak = s.weakest, weak.id != s.strongest?.id {
                statBlockWide("弱势",
                              "\(weak.name) \(String(format: "%+.2f%%", weak.changePct))",
                              color: chartProfit)
            }
            Spacer()
            statBlock("总持仓", String(format: "%.0fK", s.totalOpenInterestK), color: .secondary)
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

    private func statBlockWide(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.callout.monospaced()).foregroundColor(color)
                .lineLimit(1)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private func bullBiasBar(bias: Double) -> some View {
        // bias ∈ [-1, +1] · 红涨绿跌
        let pct = (bias + 1) / 2  // 转 [0, 1]
        let color: Color = bias > 0 ? chartLoss : (bias < 0 ? chartProfit : .secondary)
        return VStack(alignment: .leading, spacing: 2) {
            Text("多空偏向").font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 80, height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(2, 80 * pct), height: 8)
                }
                Text(String(format: "%+.0f%%", bias * 100))
                    .font(.caption.monospaced())
                    .foregroundColor(color)
            }
        }
    }

    // MARK: - 品种表格

    private var instrumentTable: some View {
        VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                cellHeader("代码", w: 70, alignment: .leading)
                cellHeader("名称", w: 100, alignment: .leading)
                cellHeader("最新价", w: 100, alignment: .trailing)
                cellHeader("涨跌幅", w: 100, alignment: .trailing)
                cellHeader("持仓量", w: 100, alignment: .trailing)
                cellHeader("Combo", w: 80, alignment: .center)  // v15.77
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(instruments) { inst in
                        instrumentRow(inst)
                    }
                }
            }
        }
    }

    private func instrumentRow(_ inst: SectorInstrument) -> some View {
        let priceStr = formatPrice(inst.lastPrice)
        let changeColor: Color = inst.changePct > 0 ? chartLoss
                              : (inst.changePct < 0 ? chartProfit : .secondary)
        return Button {
            // v15.46 · 点击 → 主图切合约（与 ⌘⌥H 热力图同机制）
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst.id)
        } label: {
            HStack(spacing: 0) {
                Text(inst.id)
                    .font(.system(size: 12, design: .monospaced).bold())
                    .foregroundColor(.primary)
                    .frame(width: 70, alignment: .leading)
                Text(inst.name)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text(priceStr)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 100, alignment: .trailing)
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.system(size: 12, design: .monospaced).bold())
                    .foregroundColor(changeColor)
                    .frame(width: 100, alignment: .trailing)
                Text(String(format: "%.0fK", inst.openInterestK))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                // v15.77 · combo 徽章（命中才显示 · 不命中空白）
                comboBadge(for: inst)
                    .frame(width: 80, alignment: .center)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(rowBackground(for: inst))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(rowHelpText(inst))
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
        if c.kindCount >= 5 { return chartLoss }
        if c.kindCount == 4 { return .orange }
        return .yellow
    }

    private func rowHelpText(_ inst: SectorInstrument) -> String {
        let base = "点击切主图 · \(inst.name)（\(inst.id)）"
        guard let c = comboMap[inst.id] else { return base }
        let kindLabel = AnomalyKind.allCases
            .filter { c.kinds.contains($0) }
            .map(\.displayName)
            .joined(separator: " · ")
        return base + " · ✨ Combo \(c.kindCount)/5（\(kindLabel)）"
    }

    private func rowBackground(for inst: SectorInstrument) -> Color {
        // 涨跌幅 > 2% 强烈染色 · 1-2% 弱染色 · 内换行视觉强弱
        let intensity = min(abs(inst.changePct) / 5.0, 1.0)
        if inst.changePct > 1 { return chartLoss.opacity(0.06 * intensity) }
        if inst.changePct < -1 { return chartProfit.opacity(0.06 * intensity) }
        return Color.clear
    }

    private func cellHeader(_ text: String, w: CGFloat, alignment: Alignment) -> some View {
        Text(text).font(.caption2).foregroundColor(.secondary)
            .frame(width: w, alignment: alignment)
    }

    // MARK: - 底部 11 板块概览

    private var sectorOverviewFooter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allSectorStats, id: \.sector) { s in
                    miniSectorChip(stats: s)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(height: 56)
        .background(Color.secondary.opacity(0.04))
    }

    private func miniSectorChip(stats: SectorStatistics) -> some View {
        let color: Color = stats.avgChangePct > 0.3 ? chartLoss
                         : (stats.avgChangePct < -0.3 ? chartProfit : .secondary)
        let isSelected = stats.sector == selectedSector
        return Button {
            selectedSector = stats.sector
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: stats.sector.icon).font(.system(size: 9))
                    Text(stats.sector.displayName).font(.system(size: 10, weight: .semibold))
                }
                Text(String(format: "%+.2f%% · %d涨/%d跌", stats.avgChangePct, stats.gainers, stats.losers))
                    .font(ChartTheme.fontHint(size: chartFontSize))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 排序

    private func sorted(_ list: [SectorInstrument]) -> [SectorInstrument] {
        let asc = list.sorted { a, b in
            switch sortField {
            case .changePct:    return a.changePct < b.changePct
            case .lastPrice:    return a.lastPrice < b.lastPrice
            case .openInterest: return a.openInterestK < b.openInterestK
            case .name:         return a.name < b.name
            }
        }
        return sortDescending ? asc.reversed() : asc
    }

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if abs(d) >= 10000 { return String(format: "%.0f", d) }
        if abs(d) >= 100   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }
}

#endif
