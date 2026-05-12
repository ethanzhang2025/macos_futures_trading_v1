// 时段对比窗口（v15.52 · ⌘⌥T · 中国期货时段差异分析）
//
// 中国期货交易时段：
//   - 夜盘 21:00-02:30（黑色/有色/能化）· 部分品种至 23:00（贵金属/股指无夜盘）
//   - 日盘 上午 09:00-11:30 · 下午 13:30-15:00
//
// 3 对比模式：
//   1. 夜盘 vs 日盘：trader 看外盘联动 · 日盘是否承接夜盘走势
//   2. 上午 vs 下午：开盘冲击 vs 收盘 squaring · 时段活跃度
//   3. 节后效应：节前最后涨跌 vs 节后开盘 gap · 节假日风险
//
// trader 用法：
//   - 找夜盘外盘联动品种（高相关 = 跟随外盘 · 适合夜盘交易）
//   - 看下午是否加速（部分品种 14:00 后波动加剧）
//   - 节后开盘冲击预警（持仓周末 = 节后 gap 风险）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared

struct SessionCompareWindow: View {

    @State private var compareMode: CompareMode = .nightVsDay
    @State private var sortField: SortField = .difference
    @State private var sortDescending: Bool = true
    /// v17.97 · 主图切到某合约时高亮该行（不修改 sort/mode · 仅指引）
    @State private var highlightedID: String?
    @Environment(\.openWindow) private var openWindow

    enum CompareMode: String, CaseIterable, Identifiable {
        case nightVsDay
        case morningVsAfternoon
        case postHoliday

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .nightVsDay:           return "夜盘 vs 日盘"
            case .morningVsAfternoon:   return "上午 vs 下午"
            case .postHoliday:          return "节后效应"
            }
        }

        var sessionALabel: String {
            switch self {
            case .nightVsDay:         return "夜盘"
            case .morningVsAfternoon: return "上午"
            case .postHoliday:        return "节前末日"
            }
        }

        var sessionBLabel: String {
            switch self {
            case .nightVsDay:         return "日盘"
            case .morningVsAfternoon: return "下午"
            case .postHoliday:        return "节后开盘"
            }
        }

        var description: String {
            switch self {
            case .nightVsDay:
                return "夜盘 21:00-02:30 跟随外盘 · 日盘 9:00-15:00 承接 / 反转 · 看时段一致性"
            case .morningVsAfternoon:
                return "上午开盘冲击 + 主力建仓 · 下午 14:00 后波动加剧 · 看时段活跃度差"
            case .postHoliday:
                return "节前末日（多周末减仓）vs 节后开盘 gap · 节假日风险 + 跳空机会"
            }
        }
    }

    enum SortField: String, CaseIterable, Identifiable {
        case difference  // 时段差值（B - A）
        case sessionA
        case sessionB
        case totalChange
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .difference:  return "时段差"
            case .sessionA:    return "时段 A"
            case .sessionB:    return "时段 B"
            case .totalChange: return "总涨跌"
            }
        }
    }

    /// 单品种 · 双时段对比 mock
    struct SessionRow: Identifiable {
        let inst: SectorInstrument
        let sessionA: Double  // 时段 A 涨跌
        let sessionB: Double  // 时段 B 涨跌
        var difference: Double { sessionB - sessionA }
        var id: String { inst.id }
    }

    private var rows: [SessionRow] {
        let raw = SectorPresets.all.map { inst in
            sessionRow(for: inst, mode: compareMode)
        }
        return sorted(raw)
    }

    /// mock 公式（v2 接 CTP 真历史 K 线后整段废弃）
    private func sessionRow(for inst: SectorInstrument, mode: CompareMode) -> SessionRow {
        let total = inst.changePct
        // 用 inst.id + mode 做 seeded 偏移 · 同合约同模式可复现
        let seed = UInt64(bitPattern: Int64(inst.id.hashValue ^ mode.rawValue.hashValue))
        var rng = SimpleRNG(seed: seed)
        switch mode {
        case .nightVsDay:
            // 夜盘约占总涨幅 60%（外盘主导）+ 噪声 · 日盘剩余
            let nightRatio = 0.4 + rng.nextDouble() * 0.4   // [0.4, 0.8]
            let night = total * nightRatio + rng.nextDouble(in: -0.5...0.5)
            let day = total - night + rng.nextDouble(in: -0.3...0.3)
            return SessionRow(inst: inst, sessionA: night, sessionB: day)
        case .morningVsAfternoon:
            // 日盘内部：上午冲击 + 下午加速（部分品种 14:00 后逆转）
            let morningRatio = 0.3 + rng.nextDouble() * 0.4   // [0.3, 0.7]
            let dayTotal = total  // 简化：日盘 = 总涨跌
            let morning = dayTotal * morningRatio + rng.nextDouble(in: -0.4...0.4)
            let afternoon = dayTotal - morning + rng.nextDouble(in: -0.4...0.4)
            return SessionRow(inst: inst, sessionA: morning, sessionB: afternoon)
        case .postHoliday:
            // 节前末日 vs 节后开盘 gap（部分品种节后 gap 显著）
            let preHoliday = total * 0.3 + rng.nextDouble(in: -0.8...0.8)
            // 节后 gap：seeded 大概率反转（trader 心理博弈）
            let gapMagnitude = rng.nextDouble(in: -3.0...3.0)  // 节后 gap [-3%, +3%]
            let postHoliday = gapMagnitude
            return SessionRow(inst: inst, sessionA: preHoliday, sessionB: postHoliday)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            modeDescriptionBar
            Divider()
            statsBar
            Divider()
            comparisonTable
            Divider()
            sectorSummary
        }
        .frame(minWidth: 1080, minHeight: 720)
        // v17.97 · inbound · 主图切到某合约 · 高亮该行（保持当前 sort/mode · 仅指引）
        .onReceive(NotificationCenter.default.publisher(for: .watchlistInstrumentSelected)) { note in
            if let id = note.object as? String { highlightedID = id }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("对比模式").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $compareMode) {
                    ForEach(CompareMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                .labelsHidden()
            }

            Spacer()

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
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 模式说明

    private var modeDescriptionBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").font(.caption).foregroundColor(.secondary)
            Text(compareMode.description)
                .font(.caption).foregroundColor(.secondary)
            Spacer()
            Text("v1 mock · 基于 changePct + seeded 偏移（v2 接 CTP 真分时数据）")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    // MARK: - 统计 HUD

    private var statsBar: some View {
        let r = rows
        guard !r.isEmpty else {
            return AnyView(Color.clear.frame(height: 0))
        }
        let aStrong = r.filter { $0.sessionA > $0.sessionB }.count
        let bStrong = r.filter { $0.sessionB > $0.sessionA }.count
        let avgA = r.reduce(0.0) { $0 + $1.sessionA } / Double(r.count)
        let avgB = r.reduce(0.0) { $0 + $1.sessionB } / Double(r.count)
        let diff = avgB - avgA
        return AnyView(HStack(spacing: 22) {
            statBlock("品种", "\(r.count)", color: .secondary)
            statBlock("\(compareMode.sessionALabel) 强", "\(aStrong)", color: .secondary)
            statBlock("\(compareMode.sessionBLabel) 强", "\(bStrong)", color: .secondary)
            Divider().frame(height: 28)
            statBlock("均 \(compareMode.sessionALabel)",
                     String(format: "%+.2f%%", avgA),
                     color: avgA >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            statBlock("均 \(compareMode.sessionBLabel)",
                     String(format: "%+.2f%%", avgB),
                     color: avgB >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            statBlock("时段差",
                     String(format: "%+.2f%%", diff),
                     color: diff >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            Spacer()
            Text(diff > 0.5
                 ? "\(compareMode.sessionBLabel) 整体强于 \(compareMode.sessionALabel)"
                 : (diff < -0.5
                    ? "\(compareMode.sessionALabel) 整体强于 \(compareMode.sessionBLabel)"
                    : "两段强度接近"))
                .font(.caption.monospaced()).foregroundColor(.secondary)
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

    // MARK: - 对比表格

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                cellHeader("代码", w: 70, alignment: .leading)
                cellHeader("名称", w: 90, alignment: .leading)
                cellHeader("板块", w: 70, alignment: .leading)
                cellHeader(compareMode.sessionALabel, w: 80, alignment: .trailing)
                cellHeader(compareMode.sessionBLabel, w: 80, alignment: .trailing)
                cellHeader("时段差对比", w: 280, alignment: .center)
                cellHeader("差值", w: 80, alignment: .trailing)
                cellHeader("总涨跌", w: 70, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    let maxAbs = max(
                        rows.map { abs($0.sessionA) + abs($0.sessionB) }.max() ?? 1,
                        1
                    )
                    ForEach(rows) { row in
                        rowView(row: row, maxAbs: maxAbs)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func rowView(row: SessionRow, maxAbs: Double) -> some View {
        let inst = row.inst
        let aColor: Color = row.sessionA > 0 ? ChartTheme.chartLoss
                          : (row.sessionA < 0 ? ChartTheme.chartProfit : .secondary)
        let bColor: Color = row.sessionB > 0 ? ChartTheme.chartLoss
                          : (row.sessionB < 0 ? ChartTheme.chartProfit : .secondary)
        let diffColor: Color = row.difference > 0 ? ChartTheme.chartLoss
                             : (row.difference < 0 ? ChartTheme.chartProfit : .secondary)
        let totalColor: Color = inst.changePct > 0 ? ChartTheme.chartLoss
                              : (inst.changePct < 0 ? ChartTheme.chartProfit : .secondary)
        return Button {
            openWindow(id: "chart")
            NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: inst.id)
        } label: {
            HStack(spacing: 0) {
                Text(inst.id)
                    .font(.system(size: 11, design: .monospaced).bold())
                    .frame(width: 70, alignment: .leading)
                Text(inst.name)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: inst.sector.icon).font(.system(size: 9))
                    Text(inst.sector.displayName).font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
                Text(String(format: "%+.2f%%", row.sessionA))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(aColor)
                    .frame(width: 80, alignment: .trailing)
                Text(String(format: "%+.2f%%", row.sessionB))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(bColor)
                    .frame(width: 80, alignment: .trailing)
                sessionBar(row: row, maxAbs: maxAbs)
                    .frame(width: 280, height: 22)
                Text(String(format: "%+.2f%%", row.difference))
                    .font(.system(size: 11, design: .monospaced).bold())
                    .foregroundColor(diffColor)
                    .frame(width: 80, alignment: .trailing)
                Text(String(format: "%+.2f%%", inst.changePct))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(totalColor)
                    .frame(width: 70, alignment: .trailing)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(highlightedID == inst.id ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip("\(inst.name) · \(compareMode.sessionALabel) \(String(format: "%+.2f%%", row.sessionA)) · \(compareMode.sessionBLabel) \(String(format: "%+.2f%%", row.sessionB))")
    }

    /// 双时段横条对比：左侧 sessionA 从中点向左 / 右侧 sessionB 从中点向右
    private func sessionBar(row: SessionRow, maxAbs: Double) -> some View {
        GeometryReader { geom in
            let totalW = geom.size.width
            let halfW = totalW / 2
            let aRatio = min(abs(row.sessionA) / maxAbs, 1.0)
            let bRatio = min(abs(row.sessionB) / maxAbs, 1.0)
            let aColor: Color = row.sessionA > 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit
            let bColor: Color = row.sessionB > 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: totalW, height: 14)
                HStack(spacing: 0) {
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(aColor.opacity(0.85))
                            .frame(width: halfW * aRatio, height: 14)
                    }
                    HStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bColor.opacity(0.85))
                            .frame(width: halfW * bRatio, height: 14)
                        Spacer()
                    }
                }
                Rectangle()
                    .fill(Color.white.opacity(0.50))
                    .frame(width: 1, height: 16)
            }
        }
    }

    private func cellHeader(_ text: String, w: CGFloat, alignment: Alignment) -> some View {
        Text(text).font(.caption2).foregroundColor(.secondary)
            .frame(width: w, alignment: alignment)
    }

    // MARK: - 板块汇总

    private var sectorSummary: some View {
        let allRows = rows
        let bySector = Dictionary(grouping: allRows) { $0.inst.sector }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Sector.allCases) { sec in
                    if let rows = bySector[sec], !rows.isEmpty {
                        sectorChip(sector: sec, rows: rows)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(height: 64)
        .background(Color.secondary.opacity(0.04))
    }

    private func sectorChip(sector: Sector, rows: [SessionRow]) -> some View {
        let avgA = rows.reduce(0.0) { $0 + $1.sessionA } / Double(rows.count)
        let avgB = rows.reduce(0.0) { $0 + $1.sessionB } / Double(rows.count)
        let diff = avgB - avgA
        let diffColor: Color = diff > 0 ? ChartTheme.chartLoss
                             : (diff < 0 ? ChartTheme.chartProfit : .secondary)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: sector.icon).font(.system(size: 9))
                Text(sector.displayName).font(.system(size: 10, weight: .semibold))
            }
            HStack(spacing: 6) {
                Text("\(compareMode.sessionALabel)\(String(format: "%+.1f", avgA))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(avgA >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
                Text("→")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("\(compareMode.sessionBLabel)\(String(format: "%+.1f", avgB))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(avgB >= 0 ? ChartTheme.chartLoss : ChartTheme.chartProfit)
            }
            Text(String(format: "差 %+.2f%%", diff))
                .font(.system(size: 9, design: .monospaced).bold())
                .foregroundColor(diffColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(diffColor.opacity(0.08))
        .cornerRadius(4)
    }

    // MARK: - 排序

    private func sorted(_ list: [SessionRow]) -> [SessionRow] {
        let asc = list.sorted { a, b in
            switch sortField {
            case .difference:  return a.difference < b.difference
            case .sessionA:    return a.sessionA < b.sessionA
            case .sessionB:    return a.sessionB < b.sessionB
            case .totalChange: return a.inst.changePct < b.inst.changePct
            }
        }
        return sortDescending ? asc.reversed() : asc
    }
}

// MARK: - 简易 RNG（XorShift64）

private struct SimpleRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }

    mutating func nextDouble() -> Double {
        Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        nextDouble() * (range.upperBound - range.lowerBound) + range.lowerBound
    }
}

#endif
