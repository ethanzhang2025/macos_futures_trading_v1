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
        .frame(minWidth: 960, minHeight: 600)
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
                .help(sortDescending ? "降序（点切换升序）" : "升序（点切换降序）")
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
        if avgChange > 0.5 { bgTint = ChartTheme.chartLoss.opacity(isSelected ? 0.40 : 0.10) }   // 中国习惯涨红
        else if avgChange < -0.5 { bgTint = ChartTheme.chartProfit.opacity(isSelected ? 0.40 : 0.10) }
        else { bgTint = Color.gray.opacity(isSelected ? 0.30 : 0.08) }
        return Button {
            selectedSector = sec
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sec.icon).font(.caption)
                Text(sec.displayName).font(.callout)
                if let s = stats {
                    Text(String(format: "%+.1f%%", s.avgChangePct))
                        .font(ChartTheme.fontHint)
                        .foregroundColor(s.avgChangePct >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
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
            statBlock("涨", "\(s.gainers)", color: ChartTheme.chartLoss)
            statBlock("跌", "\(s.losers)", color: ChartTheme.chartProfit)
            if s.unchanged > 0 {
                statBlock("平", "\(s.unchanged)", color: .secondary)
            }
            statBlock("均涨幅",
                     String(format: "%+.2f%%", s.avgChangePct),
                     color: s.avgChangePct >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            Divider().frame(height: 28)
            // 多空偏向进度条
            bullBiasBar(bias: s.bullBias)
            Divider().frame(height: 28)
            if let strong = s.strongest {
                statBlockWide("龙头",
                              "\(strong.name) \(String(format: "%+.2f%%", strong.changePct))",
                              color: ChartTheme.chartLoss)
            }
            if let weak = s.weakest, weak.id != s.strongest?.id {
                statBlockWide("弱势",
                              "\(weak.name) \(String(format: "%+.2f%%", weak.changePct))",
                              color: ChartTheme.chartProfit)
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
        let color: Color = bias > 0 ? ChartTheme.chartLoss : (bias < 0 ? ChartTheme.chartProfit : .secondary)
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
        let changeColor: Color = inst.changePct > 0 ? ChartTheme.chartLoss
                              : (inst.changePct < 0 ? ChartTheme.chartProfit : .secondary)
        return HStack(spacing: 0) {
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
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(rowBackground(for: inst))
    }

    private func rowBackground(for inst: SectorInstrument) -> Color {
        // 涨跌幅 > 2% 强烈染色 · 1-2% 弱染色 · 内换行视觉强弱
        let intensity = min(abs(inst.changePct) / 5.0, 1.0)
        if inst.changePct > 1 { return ChartTheme.chartLoss.opacity(0.06 * intensity) }
        if inst.changePct < -1 { return ChartTheme.chartProfit.opacity(0.06 * intensity) }
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
        let color: Color = stats.avgChangePct > 0.3 ? ChartTheme.chartLoss
                         : (stats.avgChangePct < -0.3 ? ChartTheme.chartProfit : .secondary)
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
                    .font(ChartTheme.fontHint)
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
