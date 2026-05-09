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
    @State private var comboMinKinds: Int = 3  // v15.70 · 组合异常 minKinds 阈值
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
        case historyBacktest // v15.59 · 30d 异常频次回溯 + sparkline
        case weeklyTrend    // v15.61 · 本周 vs 上周对比（异动加剧/减弱）
        case combo          // v15.70 · 组合异常发现（同品种 ≥ N 类同时命中）

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .list: return "异常列表"
            case .kindBreakdown: return "类型分布"
            case .sectorBreakdown: return "板块分布"
            case .historyBacktest: return "30d 频次回溯"
            case .weeklyTrend: return "周对比"
            case .combo: return "组合异常"
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
            case .historyBacktest: historyBacktestView
            case .weeklyTrend:    weeklyTrendView
            case .combo:          comboView
            }
            Divider()
            legendBar
        }
        .frame(minWidth: 1280, minHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            // v15.54 · 联动：切合约时自动切到该合约的板块
            if let id = note.object as? String, let sec = SectorPresets.byID[id]?.sector {
                sectorFilter = .sector(sec)
            }
        }
    }

    // MARK: - v15.64 · 导出 CSV（v15.71 · 加 combo 支持）

    private func exportCurrentCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date())
        }()
        let data: Data
        switch viewMode {
        case .combo:
            panel.title = "导出组合异常"
            panel.nameFieldStringValue = "组合异常_\(dateStr).csv"
            let scopedEvents: [AnomalyEvent] = {
                switch sectorFilter {
                case .all: return detectionResult.events
                case .sector(let s): return detectionResult.events.filter { $0.sector == s }
                }
            }()
            let combos = ComboAnomalyAggregator.aggregate(events: scopedEvents, minKinds: comboMinKinds)
            data = ComboAnomalyCSVExporter.exportData(combos)
        default:
            panel.title = "导出异常事件"
            panel.nameFieldStringValue = "异常事件_\(dateStr).csv"
            data = AnomalyEventCSVExporter.exportData(filteredEvents)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    /// 工具栏导出按钮 help 文案
    private var exportButtonHelp: String {
        switch viewMode {
        case .list:
            return filteredEvents.isEmpty ? "当前过滤条件下无异常 · 调阈值或切板块"
                                          : "导出当前 \(filteredEvents.count) 条异常事件为 CSV"
        case .combo:
            let scopedEvents: [AnomalyEvent] = {
                switch sectorFilter {
                case .all: return detectionResult.events
                case .sector(let s): return detectionResult.events.filter { $0.sector == s }
                }
            }()
            let n = ComboAnomalyAggregator.aggregate(events: scopedEvents, minKinds: comboMinKinds).count
            return n == 0 ? "当前过滤下无组合异常 · 调低 minKinds 或类型阈值"
                          : "导出当前 \(n) 条组合异常为 CSV"
        default:
            return "切到 \"异常列表\" 或 \"组合异常\" 视图后可导出"
        }
    }

    /// 当前视图能否导出 + 是否有数据
    private var canExportCurrentView: Bool {
        switch viewMode {
        case .list:
            return !filteredEvents.isEmpty
        case .combo:
            let scopedEvents: [AnomalyEvent] = {
                switch sectorFilter {
                case .all: return detectionResult.events
                case .sector(let s): return detectionResult.events.filter { $0.sector == s }
                }
            }()
            return !ComboAnomalyAggregator.aggregate(events: scopedEvents, minKinds: comboMinKinds).isEmpty
        default:
            return false
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
                .frame(width: 600)
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

            // v15.64 · 导出 CSV（list / combo 视图启用 · v15.71 加 combo 支持）
            Button {
                exportCurrentCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!canExportCurrentView)
            .help(exportButtonHelp)

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

    // MARK: - 板块分布视图（v15.65 增强：异常密度排行 + 龙头/弱势）

    private var sectorBreakdownView: some View {
        let r = detectionResult
        // v15.65 · 按"异常密度"排序（异常数 / 板块品种数 · 而非裸异常数）
        // 避免大板块（化工 13）总数高但实际密度低 · 小板块（贵金属 2）易被淹没
        let rows: [SectorRankingRow] = Sector.allCases.compactMap { sec -> SectorRankingRow? in
            let universe = SectorPresets.instruments(in: sec).count
            guard universe > 0 else { return nil }
            let count = r.countBySector[sec] ?? 0
            let density = Double(count) / Double(universe)
            // 板块内龙头/弱势（严重度 max/min · 仅 list 同维度）
            let secEvents = r.events.filter { $0.sector == sec }
            let leader = secEvents.first  // events 已按 severity desc · 第一个就是龙头
            let lagger = secEvents.last
            return SectorRankingRow(
                sector: sec, count: count, universe: universe, density: density,
                leader: leader, lagger: lagger
            )
        }
        .sorted { $0.density > $1.density }
        let maxDensity = max(rows.first?.density ?? 0, 0.001)

        return ScrollView {
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    sectorBreakdownRowEnhanced(row, maxDensity: maxDensity)
                }
            }
            .padding(14)
        }
    }

    /// v15.65 · 板块排行行 fixture（不写 enum 把派生属性内联在闭包）
    private struct SectorRankingRow: Identifiable {
        let sector: Sector
        let count: Int
        let universe: Int
        let density: Double  // 0..1+ · count / universe
        let leader: AnomalyEvent?
        let lagger: AnomalyEvent?
        var id: String { sector.id }
    }

    private func sectorBreakdownRowEnhanced(_ row: SectorRankingRow, maxDensity: Double) -> some View {
        let pct = row.density / maxDensity
        return Button {
            sectorFilter = .sector(row.sector)
            viewMode = .list
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // 主行：板块名 + 进度条 + 异常数 / 总数 + 密度
                HStack(spacing: 12) {
                    Label(row.sector.displayName, systemImage: row.sector.icon)
                        .font(.callout.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geom in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(densityColor(row.density))
                                .frame(width: max(2, geom.size.width * CGFloat(pct)), height: 14)
                        }
                    }
                    .frame(height: 14)
                    Text("\(row.count) / \(row.universe)")
                        .font(.callout.monospaced().bold())
                        .frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.0f%%", row.density * 100))
                        .font(.caption.monospaced())
                        .foregroundColor(densityColor(row.density))
                        .frame(width: 50, alignment: .trailing)
                }
                // 副行：龙头 + 弱势（板块内 severity 最高 / 最低）
                if row.count > 0 {
                    HStack(spacing: 12) {
                        Spacer().frame(width: 110)
                        if let l = row.leader {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                    .foregroundColor(ChartTheme.chartLoss)
                                Text("龙头：\(l.instrumentName)（\(Int(l.severity))）")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                        if row.count > 1, let lag = row.lagger, lag.id != row.leader?.id {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundColor(ChartTheme.chartProfit)
                                Text("弱势：\(lag.instrumentName)（\(Int(lag.severity))）")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(row.sector.displayName) 板块异常密度 \(String(format: "%.0f%%", row.density * 100))（\(row.count) / \(row.universe)）· 点击切到列表")
    }

    private func densityColor(_ d: Double) -> Color {
        if d >= 0.6 { return ChartTheme.chartLoss }
        if d >= 0.3 { return .orange }
        if d > 0    { return .yellow }
        return .secondary.opacity(0.3)
    }

    // MARK: - 30d 频次回溯（v15.59）

    private var historyBacktestView: some View {
        let history = AnomalyHistoryGenerator.generate(days: 30)
        // 按板块过滤 · 与其他视图一致
        let filtered: [InstrumentAnomalyHistory] = {
            switch sectorFilter {
            case .all: return history
            case .sector(let s): return history.filter { $0.sector == s }
            }
        }()
        // sparkline 全市场 peak（视觉对齐 · 不同行 sparkline 高度可比）
        let globalPeak = max(filtered.map(\.peakDayCount).max() ?? 1, 1)

        return VStack(spacing: 0) {
            historyHeader
            if filtered.isEmpty {
                Text("当前过滤无数据").font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { (rank, h) in
                            historyRow(rank: rank + 1, history: h, globalPeak: globalPeak)
                        }
                    }
                }
            }
        }
    }

    private var historyHeader: some View {
        HStack(spacing: 0) {
            Text("#").font(.caption.bold()).foregroundColor(.secondary).frame(width: 36, alignment: .trailing)
            Text("品种").font(.caption.bold()).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
            Text("板块").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("30d 总").font(.caption.bold()).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
            Text("avg/天").font(.caption.bold()).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
            Text("峰值").font(.caption.bold()).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
            Spacer().frame(width: 14)
            Text("30d sparkline").font(.caption.bold()).foregroundColor(.secondary).frame(width: 220, alignment: .leading)
            Spacer().frame(width: 14)
            Text("类型分布（价/持/资/背/离）").font(.caption.bold()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func historyRow(rank: Int, history h: InstrumentAnomalyHistory, globalPeak: Int) -> some View {
        Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: h.instrumentID)
        } label: {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)

                HStack(spacing: 6) {
                    Text(h.instrumentID)
                        .font(.system(size: 11, design: .monospaced).bold())
                        .frame(width: 50, alignment: .leading)
                    Text(h.instrumentName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)

                Label(h.sector.displayName, systemImage: h.sector.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1)

                Text("\(h.totalCount)")
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(totalCountColor(h.totalCount))
                    .frame(width: 60, alignment: .trailing)

                Text(String(format: "%.1f", h.avgPerDay))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Text("\(h.peakDayCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Spacer().frame(width: 14)

                sparkline(counts: h.dailyCounts, peak: globalPeak)
                    .frame(width: 220, height: 22)

                Spacer().frame(width: 14)

                kindCountTags(h.countByKind)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(h.instrumentName)（\(h.instrumentID)）30d 共 \(h.totalCount) 次异常 · 峰值 \(h.peakDayCount) · 点击切主图")
    }

    /// sparkline 30 个 cell mini bar chart · 全局 peak 归一化高度
    private func sparkline(counts: [Int], peak: Int) -> some View {
        GeometryReader { geom in
            let w = geom.size.width
            let h = geom.size.height
            let n = max(counts.count, 1)
            let cellW = w / CGFloat(n)
            let barW = max(1.5, cellW - 1.0)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(counts.enumerated()), id: \.offset) { (i, c) in
                    let ratio = peak > 0 ? CGFloat(c) / CGFloat(peak) : 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(sparklineColor(c, peak: peak))
                        .frame(width: barW, height: max(1.5, h * ratio))
                        .opacity(c == 0 ? 0.18 : 1.0)
                }
            }
        }
    }

    private func sparklineColor(_ count: Int, peak: Int) -> Color {
        guard peak > 0 else { return .secondary }
        let ratio = Double(count) / Double(peak)
        if ratio >= 0.75 { return ChartTheme.chartLoss }
        if ratio >= 0.4  { return .orange }
        return .yellow
    }

    private func totalCountColor(_ count: Int) -> Color {
        if count >= 80 { return ChartTheme.chartLoss }
        if count >= 40 { return .orange }
        return .primary
    }

    private func kindCountTags(_ counts: [AnomalyKind: Int]) -> some View {
        HStack(spacing: 4) {
            ForEach(AnomalyKind.allCases) { k in
                let c = counts[k] ?? 0
                Text("\(c)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(c > 0 ? kindColor(k) : .secondary.opacity(0.5))
                    .frame(width: 24, alignment: .center)
                    .padding(.vertical, 2)
                    .background(c > 0 ? kindColor(k).opacity(0.12) : Color.clear,
                               in: RoundedRectangle(cornerRadius: 3))
                    .help("\(k.displayName) · 30d \(c) 次")
            }
        }
    }

    // MARK: - 周对比视图（v15.61）

    private var weeklyTrendView: some View {
        // 取 30d 历史 · 但用周对比派生属性（thisWeek/lastWeek）排序
        let history = AnomalyHistoryGenerator.generate(days: 30)
        let filtered: [InstrumentAnomalyHistory] = {
            switch sectorFilter {
            case .all: return history
            case .sector(let s): return history.filter { $0.sector == s }
            }
        }()
        // 按"加剧最严重"排序：本周相对上周 Δ% 降序（先看异动突然加剧的品种）
        let sorted = filtered.sorted { lhs, rhs in
            // surging 优先 · 同 trend 内按 |Δ%| × 本周量 综合排
            if lhs.weekTrend != rhs.weekTrend {
                let order: (WeekTrend) -> Int = {
                    switch $0 { case .surging: return 0; case .easing: return 2; case .flat: return 1 }
                }
                return order(lhs.weekTrend) < order(rhs.weekTrend)
            }
            return lhs.weekDelta > rhs.weekDelta
        }
        // 周对比统计
        let surgingCount = sorted.filter { $0.weekTrend == .surging }.count
        let easingCount = sorted.filter { $0.weekTrend == .easing }.count
        let flatCount = sorted.filter { $0.weekTrend == .flat }.count

        return VStack(spacing: 0) {
            weeklyTrendStatsBar(surging: surgingCount, easing: easingCount, flat: flatCount)
            Divider()
            weeklyTrendHeader
            if sorted.isEmpty {
                Text("当前过滤无数据").font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { (rank, h) in
                            weeklyTrendRow(rank: rank + 1, history: h)
                        }
                    }
                }
            }
        }
    }

    private func weeklyTrendStatsBar(surging: Int, easing: Int, flat: Int) -> some View {
        HStack(spacing: 22) {
            statBlock("加剧 ↑20%+", "\(surging)", color: ChartTheme.chartLoss)
            statBlock("减弱 ↓20%+", "\(easing)", color: ChartTheme.chartProfit)
            statBlock("持平", "\(flat)", color: .secondary)
            Spacer()
            Text("本周 7d vs 上周 7d · 异动突然加剧的品种值得重点跟踪")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private var weeklyTrendHeader: some View {
        HStack(spacing: 0) {
            Text("#").font(.caption.bold()).foregroundColor(.secondary).frame(width: 36, alignment: .trailing)
            Text("品种").font(.caption.bold()).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
            Text("板块").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("本周").font(.caption.bold()).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
            Text("上周").font(.caption.bold()).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
            Text("Δ").font(.caption.bold()).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
            Text("Δ%").font(.caption.bold()).foregroundColor(.secondary).frame(width: 70, alignment: .trailing)
            Spacer().frame(width: 14)
            Text("趋势").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("30d 总").font(.caption.bold()).foregroundColor(.secondary).frame(width: 60, alignment: .trailing)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func weeklyTrendRow(rank: Int, history h: InstrumentAnomalyHistory) -> some View {
        Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: h.instrumentID)
        } label: {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)

                HStack(spacing: 6) {
                    Text(h.instrumentID)
                        .font(.system(size: 11, design: .monospaced).bold())
                        .frame(width: 50, alignment: .leading)
                    Text(h.instrumentName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)

                Label(h.sector.displayName, systemImage: h.sector.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1)

                Text("\(h.thisWeekCount)")
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(weekCountColor(h.thisWeekCount))
                    .frame(width: 50, alignment: .trailing)

                Text("\(h.lastWeekCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Text(h.weekDelta > 0 ? "+\(h.weekDelta)" : "\(h.weekDelta)")
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(deltaColor(h.weekDelta))
                    .frame(width: 50, alignment: .trailing)

                Text(formatPct(h.weekDeltaPct))
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(trendColor(h.weekTrend))
                    .frame(width: 70, alignment: .trailing)

                Spacer().frame(width: 14)

                Label(h.weekTrend.displayName, systemImage: h.weekTrend.icon)
                    .font(.caption.bold())
                    .foregroundColor(trendColor(h.weekTrend))
                    .frame(width: 80, alignment: .leading)

                Text("\(h.totalCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(h.instrumentName)（\(h.instrumentID)）本周 \(h.thisWeekCount) vs 上周 \(h.lastWeekCount) · \(h.weekTrend.displayName) \(formatPct(h.weekDeltaPct)) · 点击切主图")
    }

    // MARK: - 组合异常视图（v15.70 · 同品种 ≥ minKinds 类命中）

    private var comboView: some View {
        let allEvents = detectionResult.events
        // 板块过滤：先按板块筛事件，再聚合
        let scopedEvents: [AnomalyEvent] = {
            switch sectorFilter {
            case .all: return allEvents
            case .sector(let s): return allEvents.filter { $0.sector == s }
            }
        }()
        let combos = ComboAnomalyAggregator.aggregate(events: scopedEvents, minKinds: comboMinKinds)
        let count5 = combos.filter { $0.kindCount == 5 }.count
        let count4 = combos.filter { $0.kindCount == 4 }.count
        let count3 = combos.filter { $0.kindCount == 3 }.count
        // v15.72 · 30d 历史 by instrumentID（让 trader 看出 combo 是新出现还是常态）
        let historyMap: [String: InstrumentAnomalyHistory] = Dictionary(
            uniqueKeysWithValues: AnomalyHistoryGenerator.generate(days: 30).map { ($0.instrumentID, $0) }
        )
        let globalPeak = max(historyMap.values.map(\.peakDayCount).max() ?? 1, 1)

        return VStack(spacing: 0) {
            comboStatsBar(total: combos.count, c5: count5, c4: count4, c3: count3)
            Divider()
            comboHeader
            if combos.isEmpty {
                comboEmptyHint
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(combos.enumerated()), id: \.element.id) { (rank, combo) in
                            comboRow(rank: rank + 1, combo: combo,
                                     history: historyMap[combo.instrumentID],
                                     globalPeak: globalPeak)
                        }
                    }
                }
            }
        }
    }

    private func comboStatsBar(total: Int, c5: Int, c4: Int, c3: Int) -> some View {
        HStack(spacing: 22) {
            statBlock("Combo 总数", "\(total)",
                      color: total > 0 ? ChartTheme.chartLoss : .secondary)
            Divider().frame(height: 28)
            statBlock("满命中 5 类", "\(c5)", color: c5 > 0 ? ChartTheme.chartLoss : .secondary)
            statBlock("4 类命中", "\(c4)", color: c4 > 0 ? .orange : .secondary)
            statBlock("3 类命中", "\(c3)", color: c3 > 0 ? .yellow : .secondary)
            Divider().frame(height: 28)
            HStack(spacing: 4) {
                Text("最少命中").font(.caption).foregroundColor(.secondary)
                Stepper(value: $comboMinKinds, in: 2...5, step: 1) {
                    Text("≥ \(comboMinKinds) 类")
                        .font(.caption.monospaced())
                        .frame(minWidth: 50, alignment: .leading)
                }
                .frame(width: 130)
            }
            Spacer()
            Text("同品种多类同时命中 = 真信号 · 单类触发可能是噪声")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.04))
    }

    private var comboHeader: some View {
        HStack(spacing: 0) {
            Text("#").font(.caption.bold()).foregroundColor(.secondary).frame(width: 36, alignment: .trailing)
            Text("Combo").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("品种").font(.caption.bold()).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
            Text("板块").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("类型数").font(.caption.bold()).foregroundColor(.secondary).frame(width: 56, alignment: .trailing)
            Text("命中类型").font(.caption.bold()).foregroundColor(.secondary).frame(width: 280, alignment: .leading)
            Spacer().frame(width: 14)
            Text("avg").font(.caption.bold()).foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
            Spacer().frame(width: 14)
            Text("30d 频次").font(.caption.bold()).foregroundColor(.secondary).frame(width: 180, alignment: .leading)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private var comboEmptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("当前过滤下无组合异常")
                .font(.callout).foregroundColor(.secondary)
            Text("调低 \"最少命中\" 阈值 / 调低各类型阈值 / 切板块")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func comboRow(rank: Int, combo: ComboAnomaly,
                          history: InstrumentAnomalyHistory?, globalPeak: Int) -> some View {
        Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: combo.instrumentID)
        } label: {
            HStack(spacing: 0) {
                Text("\(rank)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)

                // Combo severity 徽章（数字 + 进度条）
                HStack(spacing: 4) {
                    Text(String(format: "%.0f", combo.totalSeverity))
                        .font(.system(size: 11, design: .monospaced).bold())
                        .foregroundColor(comboSeverityColor(combo))
                    GeometryReader { geom in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(comboSeverityColor(combo).opacity(0.85))
                                .frame(width: max(2, geom.size.width * CGFloat(combo.totalSeverity / 100.0)),
                                       height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(width: 80, alignment: .leading)

                // 品种
                HStack(spacing: 6) {
                    Text(combo.instrumentID)
                        .font(.system(size: 11, design: .monospaced).bold())
                        .frame(width: 50, alignment: .leading)
                    Text(combo.instrumentName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 130, alignment: .leading)

                // 板块
                Label(combo.sector.displayName, systemImage: combo.sector.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1)

                // 类型数（5/5 染色）
                Text("\(combo.kindCount) / 5")
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(comboKindCountColor(combo.kindCount))
                    .frame(width: 56, alignment: .trailing)

                // 命中类型 tags（5 列固定布局 · 命中色块 / 未命中灰）
                comboKindTags(kinds: combo.kinds)
                    .frame(width: 280, alignment: .leading)

                Spacer().frame(width: 14)

                // avg severity
                Text(String(format: "%.0f", combo.avgSeverity))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Spacer().frame(width: 14)

                // v15.72 · 30d 频次 sparkline + 总数
                if let h = history {
                    HStack(spacing: 6) {
                        sparkline(counts: h.dailyCounts, peak: globalPeak)
                            .frame(width: 130, height: 20)
                        Text("\(h.totalCount)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .frame(width: 180, alignment: .leading)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(width: 180, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(comboHelpText(combo: combo, history: history))
    }

    private func comboHelpText(combo: ComboAnomaly, history: InstrumentAnomalyHistory?) -> String {
        let kindLabel = AnomalyKind.allCases
            .filter { combo.kinds.contains($0) }
            .map(\.displayName)
            .joined(separator: " · ")
        let base = "\(combo.instrumentName)（\(combo.instrumentID)）· combo 严重度 \(Int(combo.totalSeverity)) · \(combo.kindCount) 类命中：\(kindLabel)"
        if let h = history {
            return base + " · 30d 共 \(h.totalCount) 次异常（avg \(String(format: "%.1f", h.avgPerDay))/天）· 点击切主图"
        }
        return base + " · 点击切主图"
    }

    private func comboKindTags(kinds: Set<AnomalyKind>) -> some View {
        HStack(spacing: 4) {
            ForEach(AnomalyKind.allCases) { k in
                let hit = kinds.contains(k)
                Label(k.displayName, systemImage: k.icon)
                    .font(.system(size: 10))
                    .foregroundColor(hit ? kindColor(k) : .secondary.opacity(0.4))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(hit ? kindColor(k).opacity(0.14) : Color.clear,
                               in: RoundedRectangle(cornerRadius: 3))
                    .help(k.displayName + (hit ? " · 命中" : " · 未命中"))
            }
        }
    }

    private func comboSeverityColor(_ combo: ComboAnomaly) -> Color {
        if combo.kindCount >= 5 { return ChartTheme.chartLoss }
        if combo.kindCount == 4 { return .orange }
        if combo.totalSeverity >= 80 { return ChartTheme.chartLoss }
        if combo.totalSeverity >= 50 { return .orange }
        return .yellow
    }

    private func comboKindCountColor(_ count: Int) -> Color {
        if count >= 5 { return ChartTheme.chartLoss }
        if count == 4 { return .orange }
        return .yellow
    }

    private func weekCountColor(_ c: Int) -> Color {
        if c >= 15 { return ChartTheme.chartLoss }
        if c >= 8  { return .orange }
        return .primary
    }

    private func deltaColor(_ d: Int) -> Color {
        if d > 5 { return ChartTheme.chartLoss }
        if d < -5 { return ChartTheme.chartProfit }
        return .secondary
    }

    private func trendColor(_ t: WeekTrend) -> Color {
        switch t {
        case .surging: return ChartTheme.chartLoss
        case .easing:  return ChartTheme.chartProfit
        case .flat:    return .secondary
        }
    }

    private func formatPct(_ pct: Double) -> String {
        if pct == 0 { return "0%" }
        if abs(pct) >= 10 { return String(format: "%+.0fx", pct) }  // > 1000% 显示 +Nx
        return String(format: "%+.0f%%", pct * 100)
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
