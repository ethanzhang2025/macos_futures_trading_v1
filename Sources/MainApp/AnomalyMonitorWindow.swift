// 异常品种监控窗口（v15.54 · ⌘⌥A · 全市场 5 维度异常扫描）
//
// trader 用法：一个窗口看全市场所有异常信号 · 不用挨个翻自选
//   - 价格异动（涨跌幅 ≥ 阈值）
//   - 持仓异动（OI ≥ 板块均值 × multiple）
//   - 资金异动（|净流入| ≥ 阈值百万）
//   - 量价背离（涨价减仓 / 跌价增仓）
//   - 板块离群（与板块多数方向相反）
//
// 数据源：SectorPresets 全市场快照 · v2 接 CTP 后整段切换 · UI 不变

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct AnomalyMonitorWindow: View {

    @State private var thresholds: AnomalyThresholds = .default
    @State private var sectorFilter: SectorFilter = .all
    @State private var viewMode: ViewMode = .list
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
        case list           // 异常事件列表（按 severity 降序）
        case kindBreakdown  // 5 类型分布
        case sectorBreakdown // 板块异常分布

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .list: return "异常列表"
            case .kindBreakdown: return "类型分布"
            case .sectorBreakdown: return "板块分布"
            }
        }
    }

    private var detectionResult: AnomalyDetectionResult {
        AnomalyDetector.scan(instruments: SectorPresets.all, thresholds: thresholds)
    }

    private var filteredEvents: [AnomalyEvent] {
        let all = detectionResult.events
        switch sectorFilter {
        case .all: return all
        case .sector(let s): return all.filter { $0.sector == s }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            thresholdsBar
            Divider()
            statsBar
            Divider()
            switch viewMode {
            case .list:           listView
            case .kindBreakdown:  kindBreakdownView
            case .sectorBreakdown: sectorBreakdownView
            }
            Divider()
            legendBar
        }
        .frame(minWidth: 1080, minHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.54 · 联动：切合约时自动切到该合约的板块
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
                    ForEach(ViewMode.allCases) { m in Text(m.displayName).tag(m) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
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

            Spacer()

            Text("v1 mock · v2 接 CTP 真行情后 OI Δ + 资金流真值")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 阈值调节栏

    private var thresholdsBar: some View {
        HStack(spacing: 18) {
            // 价格异动
            kindToggle(.priceSpike)
            HStack(spacing: 4) {
                Text("价格").font(.caption).foregroundColor(.secondary)
                Stepper(value: $thresholds.priceSpikePct, in: 0.5...10.0, step: 0.5) {
                    Text(String(format: "≥ %.1f%%", thresholds.priceSpikePct))
                        .font(.caption.monospaced()).frame(minWidth: 60, alignment: .leading)
                }
                .frame(width: 130)
            }

            // 持仓异动
            kindToggle(.oiSpike)
            HStack(spacing: 4) {
                Text("持仓").font(.caption).foregroundColor(.secondary)
                Stepper(value: $thresholds.oiSpikeMultiple, in: 1.1...5.0, step: 0.1) {
                    Text(String(format: "≥ %.1f×", thresholds.oiSpikeMultiple))
                        .font(.caption.monospaced()).frame(minWidth: 50, alignment: .leading)
                }
                .frame(width: 120)
            }

            // 资金异动
            kindToggle(.fundSurge)
            HStack(spacing: 4) {
                Text("资金").font(.caption).foregroundColor(.secondary)
                Stepper(value: $thresholds.fundSurgeMillion, in: 10...500, step: 10) {
                    Text(String(format: "≥ %.0fM", thresholds.fundSurgeMillion))
                        .font(.caption.monospaced()).frame(minWidth: 60, alignment: .leading)
                }
                .frame(width: 130)
            }

            kindToggle(.priceOIDivergence)
            kindToggle(.sectorOutlier)

            Spacer()

            Button {
                thresholds = .default
            } label: {
                Label("默认", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private func kindToggle(_ kind: AnomalyKind) -> some View {
        let isOn = Binding<Bool>(
            get: { thresholds.enabledKinds.contains(kind) },
            set: { newVal in
                if newVal { thresholds.enabledKinds.insert(kind) }
                else { thresholds.enabledKinds.remove(kind) }
            }
        )
        return Toggle(isOn: isOn) {
            Label(kind.displayName, systemImage: kind.icon)
                .font(.caption)
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - 顶部统计

    private var statsBar: some View {
        let r = detectionResult
        let filtered = filteredEvents.count
        let kinds = AnomalyKind.allCases.filter { (r.countByKind[$0] ?? 0) > 0 }.count
        let sectors = r.countBySector.values.filter { $0 > 0 }.count
        return HStack(spacing: 22) {
            statBlock("异常总数", "\(r.total)", color: r.total > 20 ? ChartTheme.chartLoss : .primary)
            statBlock("当前过滤", "\(filtered)", color: .secondary)
            Divider().frame(height: 28)
            ForEach(AnomalyKind.allCases) { k in
                statBlock(k.displayName, "\(r.countByKind[k] ?? 0)", color: kindColor(k))
            }
            Divider().frame(height: 28)
            statBlock("命中类型", "\(kinds) / 5", color: .secondary)
            statBlock("命中板块", "\(sectors) / 11", color: .secondary)
            Spacer()
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

    private func kindColor(_ kind: AnomalyKind) -> Color {
        switch kind {
        case .priceSpike:        return ChartTheme.chartLoss
        case .oiSpike:           return .orange
        case .fundSurge:         return .yellow
        case .priceOIDivergence: return .purple
        case .sectorOutlier:     return .pink
        }
    }

    // MARK: - 异常列表（list 视图）

    private var listView: some View {
        let evts = filteredEvents
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("严重度").font(.caption.bold()).foregroundColor(.secondary).frame(width: 72, alignment: .leading)
                Text("类型").font(.caption.bold()).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                Text("品种").font(.caption.bold()).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
                Text("板块").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
                Text("说明").font(.caption.bold()).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))

            if evts.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(evts) { evt in eventRow(evt) }
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("当前过滤条件下无异常品种")
                .font(.callout).foregroundColor(.secondary)
            Text("调低阈值 / 切到其他板块查看")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventRow(_ evt: AnomalyEvent) -> some View {
        Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: evt.instrumentID)
        } label: {
            HStack(spacing: 0) {
                // severity bar
                HStack(spacing: 4) {
                    Text(String(format: "%.0f", evt.severity))
                        .font(.system(size: 11, design: .monospaced).bold())
                        .foregroundColor(severityColor(evt.severity))
                        .frame(width: 28, alignment: .trailing)
                    GeometryReader { geom in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(severityColor(evt.severity).opacity(0.85))
                                .frame(width: max(2, geom.size.width * CGFloat(evt.severity / 100.0)),
                                       height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(width: 72, alignment: .leading)

                // 类型 tag
                Label(evt.kind.displayName, systemImage: evt.kind.icon)
                    .font(.caption)
                    .foregroundColor(kindColor(evt.kind))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(kindColor(evt.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: 90, alignment: .leading)

                // 品种
                HStack(spacing: 6) {
                    Text(evt.instrumentID)
                        .font(.system(size: 11, design: .monospaced).bold())
                        .frame(width: 50, alignment: .leading)
                    Text(evt.instrumentName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)

                // 板块
                Label(evt.sector.displayName, systemImage: evt.sector.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1)

                // 说明
                Text(evt.description)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(evt.instrumentName)（\(evt.instrumentID)）· \(evt.kind.displayName) · 严重度 \(Int(evt.severity)) · 点击切主图")
    }

    private func severityColor(_ s: Double) -> Color {
        if s >= 80 { return ChartTheme.chartLoss }
        if s >= 50 { return .orange }
        return .yellow
    }

    // MARK: - 类型分布视图

    private var kindBreakdownView: some View {
        let r = detectionResult
        let total = max(r.total, 1)
        return ScrollView {
            VStack(spacing: 12) {
                ForEach(AnomalyKind.allCases) { k in
                    kindBreakdownRow(kind: k, count: r.countByKind[k] ?? 0, total: total)
                }
            }
            .padding(14)
        }
    }

    private func kindBreakdownRow(kind: AnomalyKind, count: Int, total: Int) -> some View {
        let pct = Double(count) / Double(total)
        return VStack(spacing: 6) {
            HStack {
                Label(kind.displayName, systemImage: kind.icon)
                    .font(.callout.bold())
                    .foregroundColor(kindColor(kind))
                Spacer()
                Text("\(count)").font(.callout.monospaced().bold())
                Text(String(format: "(%.0f%%)", pct * 100))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            GeometryReader { geom in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(kindColor(kind).opacity(0.8))
                        .frame(width: max(2, geom.size.width * CGFloat(pct)), height: 12)
                }
            }
            .frame(height: 12)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 板块分布视图

    private var sectorBreakdownView: some View {
        let r = detectionResult
        let total = max(r.total, 1)
        let sorted = Sector.allCases.map { ($0, r.countBySector[$0] ?? 0) }
            .sorted { $0.1 > $1.1 }
        return ScrollView {
            VStack(spacing: 10) {
                ForEach(sorted, id: \.0) { (sec, count) in
                    sectorBreakdownRow(sector: sec, count: count, total: total)
                }
            }
            .padding(14)
        }
    }

    private func sectorBreakdownRow(sector: Sector, count: Int, total: Int) -> some View {
        let pct = Double(count) / Double(total)
        let universe = SectorPresets.instruments(in: sector).count
        return Button {
            sectorFilter = .sector(sector)
            viewMode = .list
        } label: {
            HStack(spacing: 12) {
                Label(sector.displayName, systemImage: sector.icon)
                    .font(.callout.bold())
                    .foregroundColor(.secondary)
                    .frame(width: 110, alignment: .leading)
                GeometryReader { geom in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(count > 0 ? Color.orange.opacity(0.8) : Color.clear)
                            .frame(width: max(2, geom.size.width * CGFloat(pct)), height: 14)
                    }
                }
                .frame(height: 14)
                Text("\(count)").font(.callout.monospaced().bold())
                    .frame(width: 40, alignment: .trailing)
                Text("/ \(universe)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(sector.displayName) 板块 \(count) 异常 / \(universe) 品种 · 点击切到列表")
    }

    // MARK: - 图例栏

    private var legendBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(ChartTheme.chartLoss).frame(width: 8, height: 8)
                Text("≥ 80 高").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("50-79 中").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.yellow).frame(width: 8, height: 8)
                Text("< 50 低").font(.caption2).foregroundColor(.secondary)
            }
            Divider().frame(height: 12)
            Text("点击行 → 切主图 K 线 · 6 行情窗口自动跟随板块")
                .font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text("v15.54 · 异常品种监控")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
    }
}

#endif
