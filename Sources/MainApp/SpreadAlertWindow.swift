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
import AlertCore
import StoreCore

struct SpreadAlertWindow: View {

    @State private var thresholds: SpreadAlertThresholds = .default
    @State private var directionFilter: DirectionFilter = .all
    /// v15.57 · "已加预警" toast · 一次显示一条 · 2.5s 自动消失
    @State private var addedAlertToast: String? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    /// v15.57 · 已加进 evaluator 的 spreadID 集合 · 按钮显 ✓ 替代 +
    @State private var addedSpreadIDs: Set<String> = []
    @Environment(\.openWindow) private var openWindow
    @Environment(\.alertEvaluator) private var alertEvaluator
    @Environment(\.storeManager) private var storeManager

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
        ZStack(alignment: .top) {
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
            // v15.57 · "已加 ⌘B" toast · 顶部居中 2.5s 自动消失
            if let msg = addedAlertToast {
                Text(msg)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: addedAlertToast)
        .frame(minWidth: 1180, minHeight: 720)
        .task {
            // v15.67 · 启动时把持久化 spread alerts 注入 evaluator（防 ⌘B 未打开时无 alerts 监听）
            await loadPersistedSpreadAlertsToEvaluator()
            // 启动时同步已存在的 spreadDeviation alerts → 按钮显 ✓
            await refreshAddedSpreadIDs()
            // v15.60 · 启动周期扫描 · 60s 间隔喂 evaluator → 真触发已加预警的 spread alerts
            await runEvaluatorPushLoop()
        }
    }

    /// v15.67 · 启动时把 alertConfig 中的 spread alerts 注入 evaluator
    /// evaluator.addAlert 同 ID 覆盖 · ⌘B 也调过 addAlert 时不重复
    private func loadPersistedSpreadAlertsToEvaluator() async {
        guard let evaluator = alertEvaluator,
              let store = storeManager?.alertConfig,
              let persisted = (try? await store.load()) ?? nil else { return }
        for a in persisted {
            if case .spreadDeviation = a.condition {
                await evaluator.addAlert(a)
            }
        }
    }

    // MARK: - v15.60 周期扫描 · 喂 evaluator 真触发

    /// 60s 间隔扫描 26 对 spread series · 喂 evaluator.onSpreadValue
    /// v2 接 CTP 真行情后切换：从 SpreadValue stream 收到点 → 直接 push（无需 timer）
    private func runEvaluatorPushLoop() async {
        // 启动后立刻跑一次 · 之后 60s 间隔
        while !Task.isCancelled {
            await pushAllSpreadSeriesToEvaluator()
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    private func pushAllSpreadSeriesToEvaluator() async {
        guard let evaluator = alertEvaluator else { return }
        // 跨品种 12 对
        for pair in SpreadPresets.all {
            let values = SpreadAlertDetector.mockCrossInstrumentSeries(for: pair, count: 200)
            let series = values.map(\.value)
            await evaluator.onSpreadValue(series: series, spreadID: pair.id, isCalendar: false)
        }
        // 跨期 14 对
        for pair in CalendarSpreadPresets.all {
            let basePrice = SpreadAlertDetector.defaultBasePrice(pair.underlyingID)
            let cal = CalendarSpreadCalculator.generateMockSeries(for: pair, basePrice: basePrice, count: 200)
            let series = CalendarSpreadCalculator.toSpreadValues(cal).map(\.value)
            await evaluator.onSpreadValue(series: series, spreadID: pair.id, isCalendar: true)
        }
    }

    // MARK: - 一键加预警

    private func handleAddAlert(_ evt: SpreadAlertEvent) {
        guard let evaluator = alertEvaluator else {
            showToast("⚠️ alertEvaluator 未配置（开发期 · M5 启动前）")
            return
        }
        let alert = makeAlert(from: evt)
        Task {
            // 1. evaluator 内存 · 60s 周期扫描真触发用
            await evaluator.addAlert(alert)
            addedSpreadIDs.insert(evt.spreadID)
            // 2. v15.67 持久化 alertConfig · 重启恢复
            await persistSpreadAlert(alert)
            // 3. 通知已打开的 ⌘B AlertWindow · UI 立即更新
            NotificationCenter.default.post(name: .alertAddedFromChart, object: alert)
            showToast("已加到 ⌘B 预警面板：\(evt.spreadName)")
        }
    }

    /// v15.67 · 把 spread alert 写入 alertConfig store（重启时 ⌘B .task 加载会含此条）
    /// 防重：同 spreadID + isCalendar 的 spread alert 已存在 → 不重复 append
    private func persistSpreadAlert(_ alert: Alert) async {
        guard let store = storeManager?.alertConfig else { return }
        let existing = (try? await store.load()) ?? []
        let alreadyExists = existing.contains { existingAlert in
            guard case let .spreadDeviation(eID, eCal, _) = existingAlert.condition,
                  case let .spreadDeviation(nID, nCal, _) = alert.condition
            else { return false }
            return eID == nID && eCal == nCal
        }
        guard !alreadyExists else { return }
        try? await store.save(existing + [alert])
    }

    /// SpreadAlertEvent → AlertCore.Alert 转换
    /// instrumentID 用 leg1（跨品种）/ nearMonthID（跨期）方便用户在 ⌘B 看到关联合约
    /// condition 用 .spreadDeviation placeholder（v1 不触发 · 仅持久化展示）
    private func makeAlert(from evt: SpreadAlertEvent) -> Alert {
        let instrumentID: String = {
            switch evt.kind {
            case .crossInstrument:
                return SpreadPresets.byID[evt.spreadID]?.leg1.instrumentID ?? evt.spreadID
            case .calendar:
                return CalendarSpreadPresets.byID[evt.spreadID]?.nearMonthID ?? evt.spreadID
            }
        }()
        let kindLabel = evt.kind == .crossInstrument ? "跨品种" : "跨期"
        return Alert(
            name: "[价差·\(kindLabel)] \(evt.spreadName) \(evt.direction.displayName)",
            instrumentID: instrumentID,
            condition: .spreadDeviation(
                spreadID: evt.spreadID,
                isCalendar: evt.kind == .calendar,
                zThreshold: Decimal(thresholds.zThreshold)
            ),
            channels: [.inApp, .systemNotice],
            cooldownSeconds: 600
        )
    }

    private func showToast(_ message: String) {
        addedAlertToast = message
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                await MainActor.run { addedAlertToast = nil }
            }
        }
    }

    private func refreshAddedSpreadIDs() async {
        // v15.67 · 优先 alertConfig store（重启后真数据源）· evaluator 仅当前 session
        var ids: Set<String> = []
        if let store = storeManager?.alertConfig,
           let persisted = (try? await store.load()) ?? nil {
            for a in persisted {
                if case let .spreadDeviation(spreadID, _, _) = a.condition {
                    ids.insert(spreadID)
                }
            }
        }
        // evaluator 内存（兜底 · 当 store 不可用 · 开发期）
        if let evaluator = alertEvaluator {
            for a in await evaluator.allAlerts() {
                if case let .spreadDeviation(spreadID, _, _) = a.condition {
                    ids.insert(spreadID)
                }
            }
        }
        addedSpreadIDs = ids
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

            Text("v1 mock 行情 · 真触发已接通（60s 周期扫描 → AlertCore.onSpreadValue → ⌘B 通知）")
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
            Spacer().frame(width: 10)
            // v15.68 · 30 点走势 sparkline 列
            Text("30 走势").font(.caption.bold()).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
            Spacer().frame(width: 10)
            Text("策略建议").font(.caption.bold()).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            // v15.57 · 行尾 + 按钮列
            Text("⌘B").font(.caption.bold()).foregroundColor(.secondary).frame(width: 64, alignment: .center)
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
        let isAdded = addedSpreadIDs.contains(evt.spreadID)
        return HStack(spacing: 0) {
            // 信息区（点击切对应套利窗口）
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

                Spacer().frame(width: 10)

                // v15.68 · 30 点走势 sparkline · 上下轨 dash + current 高亮
                spreadSparkline(for: evt)
                    .frame(width: 110, height: 28)

                Spacer().frame(width: 10)

                // 策略
                Text(evt.strategy)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // 跳到对应的套利窗口（跨品种 → ⌘⌥S · 跨期 → ⌘⌥X）
                switch evt.kind {
                case .crossInstrument: openWindow(id: "spread")
                case .calendar:        openWindow(id: "calendarSpread")
                }
            }
            .help("\(evt.spreadName) · \(evt.direction.displayName) · |Z| \(String(format: "%.2f", evt.absZ)) · 点击切到对应套利窗口")

            // v15.57 · 一键加预警按钮（独立按钮 · 不嵌入信息区 tap）
            Button {
                handleAddAlert(evt)
            } label: {
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(ChartTheme.chartLoss)
                } else {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.accentColor)
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 64, alignment: .center)
            .disabled(isAdded)
            .help(isAdded ? "已加到 ⌘B 预警面板（60s 周期真扫触发）" : "加到 ⌘B 预警面板（每 60s 自动扫描 · |z|≥阈值时触发系统通知）")
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
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

    // MARK: - v15.68 · spread 走势 sparkline

    /// 30 点 spread 时序 mini chart · 上下轨 dash + current 点 highlight
    private func spreadSparkline(for evt: SpreadAlertEvent) -> some View {
        let series = lastNSpreadValues(for: evt, n: 30)
        return Canvas { ctx, size in
            guard series.count >= 2 else { return }
            let w = size.width
            let h = size.height
            // 视觉范围：取 series min/max + 上下轨 · 留 6% padding
            let dataMin = series.min() ?? 0
            let dataMax = series.max() ?? 1
            let lo = min(dataMin, evt.lowerBand)
            let hi = max(dataMax, evt.upperBand)
            let range = max(hi - lo, 1e-9)
            let pad = range * 0.06
            let viewLo = lo - pad
            let viewHi = hi + pad
            let viewRange = viewHi - viewLo

            // y 转换 · 上是 max
            func yFor(_ v: Double) -> CGFloat {
                CGFloat(1 - (v - viewLo) / viewRange) * h
            }

            // 上下轨 dash 线（淡色）
            var upperLine = Path()
            upperLine.move(to: CGPoint(x: 0, y: yFor(evt.upperBand)))
            upperLine.addLine(to: CGPoint(x: w, y: yFor(evt.upperBand)))
            ctx.stroke(upperLine, with: .color(ChartTheme.chartLoss.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))

            var lowerLine = Path()
            lowerLine.move(to: CGPoint(x: 0, y: yFor(evt.lowerBand)))
            lowerLine.addLine(to: CGPoint(x: w, y: yFor(evt.lowerBand)))
            ctx.stroke(lowerLine, with: .color(ChartTheme.chartProfit.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))

            // mean 中线（更淡）
            var meanLine = Path()
            meanLine.move(to: CGPoint(x: 0, y: yFor(evt.mean)))
            meanLine.addLine(to: CGPoint(x: w, y: yFor(evt.mean)))
            ctx.stroke(meanLine, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [1, 3]))

            // spread 折线
            var path = Path()
            let stepX = w / CGFloat(series.count - 1)
            for (i, v) in series.enumerated() {
                let pt = CGPoint(x: CGFloat(i) * stepX, y: yFor(v))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

            // 末点 highlight（与 z 严重度色阶对齐）
            if let last = series.last {
                let cx = w
                let cy = yFor(last)
                let fillColor = zColor(evt.absZ)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5)),
                         with: .color(fillColor))
            }
        }
        .help("近 30 点 spread 走势 · 红虚线 = 上轨 +2σ · 绿虚线 = 下轨 -2σ · 末点高亮 = 当前位置")
    }

    /// 取 spread 的最近 N 点 series（mock · 与 SpreadAlertDetector 同算法）
    private func lastNSpreadValues(for evt: SpreadAlertEvent, n: Int) -> [Double] {
        switch evt.kind {
        case .crossInstrument:
            guard let pair = SpreadPresets.byID[evt.spreadID] else { return [] }
            let values = SpreadAlertDetector.mockCrossInstrumentSeries(for: pair, count: 200)
            return values.suffix(n).map { NSDecimalNumber(decimal: $0.value).doubleValue }
        case .calendar:
            guard let pair = CalendarSpreadPresets.byID[evt.spreadID] else { return [] }
            let basePrice = SpreadAlertDetector.defaultBasePrice(pair.underlyingID)
            let cal = CalendarSpreadCalculator.generateMockSeries(for: pair, basePrice: basePrice, count: 200)
            return CalendarSpreadCalculator.toSpreadValues(cal).suffix(n).map { NSDecimalNumber(decimal: $0.value).doubleValue }
        }
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
