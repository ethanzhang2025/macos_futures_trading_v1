// 行情热力地图（v15.44 · ⌘⌥H · 全市场 60+ 品种一图全览）
//
// 设计：
//   - LazyVGrid 网格布局 · 每 cell 30-50pt 高 · 按 sortMode 排列
//   - sortMode 4 种：板块归属 / 涨幅榜 / 跌幅榜 / 持仓量榜
//   - 每 cell 涨跌幅染色（红涨/绿跌 · 强度按 |changePct| / 5% 归一）
//   - hover 浮窗显示完整信息
//   - cell 点击：切换主图（v2 加 NotificationCenter 事件 · 当前 v1 仅 print）
//
// trader 用法：
//   - 早盘 3 秒看完全市场情绪 · 找强势板块 / 弱势品种
//   - 与 ⌘⌥B 板块联动互补：⌘⌥B 看板块聚合 · ⌘⌥H 看全市场每个 cell

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct HeatmapWindow: View {

    @State private var sortMode: SortMode = .bySector
    @State private var hoveredID: String?
    /// v15.53 · 接收 watchlistInstrumentSelected · 高亮该 cell
    @State private var highlightedID: String?
    @Environment(\.openWindow) private var openWindow

    enum SortMode: String, CaseIterable, Identifiable {
        case bySector       // 按板块归属
        case topGainers     // 涨幅榜
        case topLosers      // 跌幅榜
        case topOI          // 持仓量榜

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .bySector:    return "按板块"
            case .topGainers:  return "涨幅榜"
            case .topLosers:   return "跌幅榜"
            case .topOI:       return "持仓量"
            }
        }
    }

    private var sortedInstruments: [SectorInstrument] {
        switch sortMode {
        case .bySector:
            return SectorPresets.all  // 已按 sector 顺序
        case .topGainers:
            return SectorPresets.all.sorted { $0.changePct > $1.changePct }
        case .topLosers:
            return SectorPresets.all.sorted { $0.changePct < $1.changePct }
        case .topOI:
            return SectorPresets.all.sorted { $0.openInterestK > $1.openInterestK }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            heatmapGrid
            Divider()
            legendBar
        }
        .frame(minWidth: 960, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.53 · 联动：切合约时高亮该 cell（保持原 sortMode · 不切板块）
            if let id = note.object as? String { highlightedID = id }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("排序").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $sortMode) {
                    ForEach(SortMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .labelsHidden()
            }

            Spacer()

            // 全市场总览：涨家数 / 跌家数 / 平均涨幅
            let total = SectorPresets.all
            let gainers = total.filter { $0.changePct > 0 }.count
            let losers = total.filter { $0.changePct < 0 }.count
            let avg = total.reduce(0.0) { $0 + $1.changePct } / Double(max(total.count, 1))
            HStack(spacing: 18) {
                Text("\(total.count) 品种").font(.caption.monospaced()).foregroundColor(.secondary)
                Text("\(gainers) 涨").font(.caption.monospaced()).foregroundColor(ChartTheme.chartLoss)
                Text("\(losers) 跌").font(.caption.monospaced()).foregroundColor(ChartTheme.chartProfit)
                Text(String(format: "均 %+.2f%%", avg))
                    .font(.caption.monospaced())
                    .foregroundColor(avg >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            }
            .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 热力网格

    private var heatmapGrid: some View {
        ScrollView {
            if sortMode == .bySector {
                // 按板块分组 · 每板块一个 section
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Sector.allCases) { sec in
                        let list = SectorPresets.instruments(in: sec)
                        if !list.isEmpty {
                            sectorSection(sector: sec, instruments: list)
                        }
                    }
                }
                .padding(14)
            } else {
                // 不分组 · 单 grid
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(sortedInstruments) { inst in
                        heatmapCell(inst)
                    }
                }
                .padding(14)
            }
        }
        .background(ChartTheme.dark.background.opacity(0.5))
    }

    private func sectorSection(sector: Sector, instruments: [SectorInstrument]) -> some View {
        let stats = SectorStatisticsCalculator.compute(instruments, sector: sector)
        let color: Color = stats.avgChangePct > 0.3 ? ChartTheme.chartLoss
                         : (stats.avgChangePct < -0.3 ? ChartTheme.chartProfit : .secondary)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: sector.icon).font(.caption.bold())
                    .foregroundColor(color)
                Text(sector.displayName).font(.callout.bold())
                Text(String(format: "(%d 品种 · 均 %+.2f%%)",
                            instruments.count, stats.avgChangePct))
                    .font(.caption.monospaced())
                    .foregroundColor(color)
                Spacer()
                Text(String(format: "%d↑ %d↓", stats.gainers, stats.losers))
                    .font(.caption.monospaced()).foregroundColor(.secondary)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(instruments) { inst in
                    heatmapCell(inst)
                }
            }
        }
    }

    private func heatmapCell(_ inst: SectorInstrument) -> some View {
        let intensity = min(abs(inst.changePct) / 4.0, 1.0)
        let bgColor: Color
        if inst.changePct > 0.05 {
            bgColor = ChartTheme.chartLoss.opacity(0.20 + 0.55 * intensity)
        } else if inst.changePct < -0.05 {
            bgColor = ChartTheme.chartProfit.opacity(0.20 + 0.55 * intensity)
        } else {
            bgColor = Color.gray.opacity(0.15)
        }
        let isHovered = hoveredID == inst.id
        let isHighlighted = highlightedID == inst.id
        return Button {
            // v15.44 v2：复用 watchlistInstrumentSelected 通道（与 ⌘L 自选 / ⌘B 预警同机制）
            // 主图 ChartScene 接收后切合约 · 默认在 chart 窗口前置
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(inst.id).font(.system(size: 11, design: .monospaced).bold())
                    Spacer()
                    Text(String(format: "%+.1f%%", inst.changePct))
                        .font(.system(size: 10, design: .monospaced).bold())
                }
                Text(inst.name)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(bgColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHighlighted ? ChartTheme.chartLine : (isHovered ? Color.white.opacity(0.7) : Color.clear),
                            lineWidth: isHighlighted ? 2 : 1.2)
            )
            .foregroundColor(.white)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.10), value: isHovered)
        }
        .buttonStyle(.plain)
        .help("\(inst.name)（\(inst.id)） · \(formatPrice(inst.lastPrice)) · \(String(format: "%+.2f%%", inst.changePct)) · 持仓 \(String(format: "%.0fK", inst.openInterestK))")
        .onHover { isOver in
            hoveredID = isOver ? inst.id : nil
        }
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 18) {
            Text("色阶").font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 0) {
                ForEach([-4.0, -2.5, -1.0, -0.3, 0.3, 1.0, 2.5, 4.0], id: \.self) { pct in
                    let intensity = min(abs(pct) / 4.0, 1.0)
                    let bg: Color = pct > 0
                        ? ChartTheme.chartLoss.opacity(0.20 + 0.55 * intensity)
                        : (pct < 0
                           ? ChartTheme.chartProfit.opacity(0.20 + 0.55 * intensity)
                           : Color.gray.opacity(0.15))
                    Rectangle()
                        .fill(bg)
                        .frame(width: 38, height: 16)
                        .overlay(
                            Text(String(format: "%+.1f%%", pct))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white)
                        )
                }
            }
            .cornerRadius(2)
            Spacer()
            Text("· 红涨 / 绿跌 · 强度 ∝ |涨跌幅| / 4% · hover 看完整数据 · 点击切主图")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    // MARK: - Helpers

    private func formatPrice(_ p: Decimal) -> String {
        let d = NSDecimalNumber(decimal: p).doubleValue
        if abs(d) >= 10000 { return String(format: "%.0f", d) }
        if abs(d) >= 100   { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }
}

#endif
