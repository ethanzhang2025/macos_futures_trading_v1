// 价差套利 alert 窗口（v15.55 · ⌘⌥W · 26 对全市场偏离扫描）
//
// trader 用法：一窗口看全市场所有偏离 mean 的套利对 · 不用挨个翻 ⌘⌥S/⌘⌥X
//   - 12 跨品种（rb-hc / au-80ag / IF-IH 等）+ 14 跨期（rb-05-10 / m-05-09 等）= 26 对
//   - |Z| ≥ 阈值（默认 2.0 = ±2σ 经典套利信号）→ 触发 alert
//   - 上轨突破 → 做空价差 / 下轨突破 → 做多价差
//
// 与 ⌘⌥A 异常品种监控的边界：
//   - A：单品种异动（涨跌/持仓/资金/背离/离群）
//   - W：价差对偏离（mean-revert 入场机会）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import Shared
import DataCore

struct SpreadAlertWindow: View {

    @State private var thresholds: SpreadAlertThresholds = .default
    @State private var directionFilter: DirectionFilter = .all
    @Environment(\.openWindow) private var openWindow

    enum DirectionFilter: String, CaseIterable, Identifiable {
        case all
        case upperOnly  // 仅上轨突破
        case lowerOnly  // 仅下轨突破

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .all:       return "全部"
            case .upperOnly: return "🔻 上轨突破"
            case .lowerOnly: return "🔺 下轨突破"
            }
        }
    }

    private var allEvents: [SpreadAlertEvent] {
        SpreadAlertDetector.scanAll(thresholds: thresholds)
    }

    private var filteredEvents: [SpreadAlertEvent] {
        let evts = allEvents
        switch directionFilter {
        case .all:       return evts
        case .upperOnly: return evts.filter { $0.direction == .upperBreached }
        case .lowerOnly: return evts.filter { $0.direction == .lowerBreached }
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
            if filteredEvents.isEmpty {
                emptyHint
            } else {
                listHeader
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredEvents) { evt in eventRow(evt) }
                    }
                }
            }
            Divider()
            legendBar
        }
        .frame(minWidth: 1180, minHeight: 720)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("方向").font(.callout).foregroundColor(.secondary)
                Picker("", selection: $directionFilter) {
                    ForEach(DirectionFilter.allCases) { f in Text(f.displayName).tag(f) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()
            }

            Spacer()

            Text("v1 mock · v2 接 CTP 真历史 K 线 + AlertCore 通知通道")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 阈值调节栏

    private var thresholdsBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                Text("Z 阈值").font(.caption).foregroundColor(.secondary)
                Stepper(value: $thresholds.zThreshold, in: 0.5...4.0, step: 0.25) {
                    Text(String(format: "|z| ≥ %.2f", thresholds.zThreshold))
                        .font(.caption.monospaced()).frame(minWidth: 80, alignment: .leading)
                }
                .frame(width: 150)
            }

            Toggle(isOn: $thresholds.includeCrossInstrument) {
                Label("跨品种（12 对）", systemImage: "arrow.left.and.right")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $thresholds.includeCalendar) {
                Label("跨期（14 对）", systemImage: "calendar")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 4) {
                Text("最小样本").font(.caption).foregroundColor(.secondary)
                Stepper(value: $thresholds.minSamples, in: 10...100, step: 10) {
                    Text("\(thresholds.minSamples)")
                        .font(.caption.monospaced()).frame(minWidth: 30, alignment: .leading)
                }
                .frame(width: 110)
            }

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

    // MARK: - 顶部统计

    private var statsBar: some View {
        let evts = filteredEvents
        let upperCount = evts.filter { $0.direction == .upperBreached }.count
        let lowerCount = evts.filter { $0.direction == .lowerBreached }.count
        let crossCount = evts.filter { $0.kind == .crossInstrument }.count
        let calCount = evts.filter { $0.kind == .calendar }.count
        let maxAbsZ = evts.map(\.absZ).max() ?? 0
        return HStack(spacing: 22) {
            statBlock("命中", "\(evts.count) / 26", color: evts.count > 5 ? ChartTheme.chartLoss : .primary)
            Divider().frame(height: 28)
            statBlock("上轨", "\(upperCount)", color: ChartTheme.chartLoss)
            statBlock("下轨", "\(lowerCount)", color: ChartTheme.chartProfit)
            Divider().frame(height: 28)
            statBlock("跨品种", "\(crossCount)", color: .orange)
            statBlock("跨期", "\(calCount)", color: .cyan)
            Divider().frame(height: 28)
            statBlock("最大 |Z|", String(format: "%.2f", maxAbsZ),
                     color: maxAbsZ >= 3 ? ChartTheme.chartLoss : .primary)
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

    // MARK: - 列表

    private var listHeader: some View {
        HStack(spacing: 0) {
            Text("|Z|").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text("类型").font(.caption.bold()).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text("价差对").font(.caption.bold()).foregroundColor(.secondary).frame(width: 160, alignment: .leading)
            Text("方向").font(.caption.bold()).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
            Text("当前").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
            Text("均值").font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .trailing)
            Text("±2σ 区间").font(.caption.bold()).foregroundColor(.secondary).frame(width: 130, alignment: .trailing)
            Spacer().frame(width: 14)
            Text("策略建议").font(.caption.bold()).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("当前阈值下无套利偏离机会")
                .font(.callout).foregroundColor(.secondary)
            Text("调低 Z 阈值 / 切方向过滤 / 检查类型开关")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventRow(_ evt: SpreadAlertEvent) -> some View {
        let dirColor: Color = evt.direction == .upperBreached ? ChartTheme.chartLoss : ChartTheme.chartProfit
        let kindColor: Color = evt.kind == .crossInstrument ? .orange : .cyan
        let kindLabel: String = evt.kind == .crossInstrument ? "跨品种" : "跨期"
        return Button {
            // 跳到对应的套利窗口（跨品种 → ⌘⌥S · 跨期 → ⌘⌥X）
            switch evt.kind {
            case .crossInstrument: openWindow(id: "spread")
            case .calendar:        openWindow(id: "calendarSpread")
            }
        } label: {
            HStack(spacing: 0) {
                // |Z| 进度条
                HStack(spacing: 4) {
                    Text(String(format: "%.2f", evt.absZ))
                        .font(.system(size: 11, design: .monospaced).bold())
                        .foregroundColor(zColor(evt.absZ))
                        .frame(width: 36, alignment: .trailing)
                    GeometryReader { geom in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(zColor(evt.absZ).opacity(0.85))
                                .frame(width: max(2, geom.size.width * CGFloat(min(evt.absZ / 4.0, 1.0))),
                                       height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(width: 80, alignment: .leading)

                // 类型 tag
                Text(kindLabel)
                    .font(.caption)
                    .foregroundColor(kindColor)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(kindColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: 70, alignment: .leading)

                // 价差对
                VStack(alignment: .leading, spacing: 1) {
                    Text(evt.spreadName)
                        .font(.system(size: 11, design: .monospaced).bold())
                    Text(evt.categoryDisplay)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

                // 方向
                Label(evt.direction.displayName, systemImage: evt.direction == .upperBreached ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(dirColor)
                    .frame(width: 110, alignment: .leading)

                // 当前
                Text(formatValue(evt.currentValue, unit: evt.unitLabel))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(dirColor)
                    .frame(width: 80, alignment: .trailing)

                // 均值
                Text(formatValue(evt.mean, unit: evt.unitLabel))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)

                // ±2σ 区间
                Text("[\(formatValue(evt.lowerBand, unit: nil)), \(formatValue(evt.upperBand, unit: nil))]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 130, alignment: .trailing)

                Spacer().frame(width: 14)

                // 策略
                Text(evt.strategy)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(evt.spreadName) · \(evt.direction.displayName) · |Z| \(String(format: "%.2f", evt.absZ)) · \(evt.strategy) · 点击切到对应套利窗口")
    }

    private func zColor(_ z: Double) -> Color {
        if z >= 3.0 { return ChartTheme.chartLoss }
        if z >= 2.0 { return .orange }
        return .yellow
    }

    private func formatValue(_ v: Double, unit: String?) -> String {
        let s: String
        if abs(v) >= 1000 { s = String(format: "%.0f", v) }
        else if abs(v) >= 10 { s = String(format: "%.1f", v) }
        else { s = String(format: "%.2f", v) }
        if let u = unit, !u.isEmpty { return "\(s) \(u)" }
        return s
    }

    // MARK: - 图例栏

    private var legendBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(ChartTheme.chartLoss).frame(width: 8, height: 8)
                Text("|Z| ≥ 3 极值").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("|Z| ≥ 2 经典").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Color.yellow).frame(width: 8, height: 8)
                Text("|Z| < 2 弱信号").font(.caption2).foregroundColor(.secondary)
            }
            Divider().frame(height: 12)
            Text("点击行 → 切对应套利窗口（跨品种 ⌘⌥S · 跨期 ⌘⌥X）")
                .font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text("v15.55 · 价差套利 alert")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.04))
    }
}

#endif
