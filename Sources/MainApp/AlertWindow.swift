// MainApp · 预警面板 Scene（WP-52 UI · 共 4 commit）
//
// 进度：
//   ✅ 1/4：开窗 + Mock alerts + 列表占位
//   ✅ 2/4：添加预警 Sheet（6 类 condition 表单）
//   ✅ 3/4：编辑/删除/启停 + 触发历史 Tab（AddOrEditAlertSheet 双模式 · MockAlertHistory）
//   ⏳ 4/4：通知通道（系统通知 / 声音 留 Mac 验收）
//
// 留待 M5：StoreManager 注入 AlertEvaluator + 持久化 alerts + 真实历史

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import AlertCore

// MARK: - Tab 切换

private enum AlertTab: String, CaseIterable, Identifiable {
    case list    = "预警列表"
    case history = "触发历史"
    var id: String { rawValue }
}

// MARK: - Sheet 状态（add / edit 二态）

private enum SheetState: Identifiable {
    case add
    case edit(Alert)
    var id: String {
        switch self {
        case .add:           return "add"
        case .edit(let a):   return "edit-\(a.id.uuidString)"
        }
    }
}

// MARK: - 主窗口

struct AlertWindow: View {

    @State private var alerts: [Alert] = []
    @State private var historyEntries: [AlertHistoryEntry] = []
    @State private var selectedTab: AlertTab = .list
    @State private var sheetState: SheetState?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            tabContent
            Divider()
            footerHint
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 480, idealHeight: 640)
        .task {
            alerts = MockAlerts.generate()
            historyEntries = MockAlertHistory.generate()
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .add:
                AddOrEditAlertSheet(editing: nil) { newAlert in
                    alerts.append(newAlert)
                }
            case .edit(let alert):
                AddOrEditAlertSheet(editing: alert) { updated in
                    if let idx = alerts.firstIndex(where: { $0.id == updated.id }) {
                        alerts[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: - 顶部 stats

    private var header: some View {
        let active = alerts.filter { $0.status == .active }.count
        let triggered = alerts.filter { $0.status == .triggered }.count
        let paused = alerts.filter { $0.status == .paused }.count

        return HStack(spacing: 24) {
            Text("🔔 预警面板").font(.title2).bold()
            Divider().frame(height: 24)
            stat("总数", "\(alerts.count)")
            stat("活跃", "\(active)", color: .green)
            stat("已触发", "\(triggered)", color: .red)
            stat("已暂停", "\(paused)", color: .secondary)
            Spacer()
            Button {
                sheetState = .add
            } label: {
                Label("添加", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("添加预警（⌘⇧N）")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func stat(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - Tab 切换栏

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(AlertTab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .labelsHidden()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .list:
            if alerts.isEmpty {
                ProgressView("加载预警…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                alertsList
            }
        case .history:
            historyList
        }
    }

    // MARK: - 预警列表

    private var alertsList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("合约").frame(width: 60, alignment: .leading)
                Text("条件").frame(width: 200, alignment: .leading)
                Text("状态").frame(width: 70, alignment: .center)
                Text("通道").frame(width: 80, alignment: .leading)
                Text("冷却").frame(width: 50, alignment: .trailing)
                Text("操作").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                        Divider()
                    }
                }
            }
        }
    }

    private func alertRow(_ a: Alert) -> some View {
        HStack(spacing: 8) {
            Text(a.name).frame(maxWidth: .infinity, alignment: .leading)
            Text(a.instrumentID).frame(width: 60, alignment: .leading)
            Text(a.condition.displayDescription).frame(width: 200, alignment: .leading)
                .foregroundColor(.secondary)
            Self.statusBadge(a.status).frame(width: 70, alignment: .center)
            Text(a.channels.map { Self.channelLabel($0) }.sorted().joined(separator: "·"))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(Int(a.cooldownSeconds))s")
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)
            rowActions(a).frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowActions(_ a: Alert) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleStatus(a)
            } label: {
                Image(systemName: a.status == .paused ? "play.circle" : "pause.circle")
                    .foregroundColor(a.status == .paused ? .green : .orange)
            }
            .buttonStyle(.borderless)
            .help(a.status == .paused ? "恢复" : "暂停")
            .disabled(a.status == .cancelled)

            Button {
                sheetState = .edit(a)
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button {
                deleteAlert(a)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .font(.system(size: 14))
    }

    private func toggleStatus(_ a: Alert) {
        guard let idx = alerts.firstIndex(where: { $0.id == a.id }) else { return }
        var copy = alerts[idx]
        copy.status = (copy.status == .paused) ? .active : .paused
        alerts[idx] = copy
    }

    private func deleteAlert(_ a: Alert) {
        alerts.removeAll { $0.id == a.id }
    }

    @ViewBuilder
    private static func statusBadge(_ s: AlertStatus) -> some View {
        switch s {
        case .active:    badge("活跃", color: .green)
        case .triggered: badge("已触发", color: .red)
        case .paused:    badge("暂停", color: .orange)
        case .cancelled: badge("已取消", color: .secondary)
        }
    }

    private static func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.8))
            .cornerRadius(3)
    }

    private static func channelLabel(_ k: NotificationChannelKind) -> String {
        switch k {
        case .inApp:        return "内"
        case .systemNotice: return "通"
        case .sound:        return "声"
        case .console:      return "控"
        case .file:         return "文"
        }
    }

    // MARK: - 触发历史列表

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("时间").frame(width: 150, alignment: .leading)
                Text("预警").frame(maxWidth: .infinity, alignment: .leading)
                Text("合约").frame(width: 60, alignment: .leading)
                Text("触发价").frame(width: 80, alignment: .trailing)
                Text("条件").frame(width: 200, alignment: .leading)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            if historyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("暂无触发历史").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyEntries) { entry in
                            historyRow(entry)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ e: AlertHistoryEntry) -> some View {
        HStack(spacing: 8) {
            Text(Self.formatTime(e.triggeredAt))
                .frame(width: 150, alignment: .leading)
                .foregroundColor(.secondary)
            Text(e.alertName).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.instrumentID).frame(width: 60, alignment: .leading)
            Text(Self.formatPrice(e.triggerPrice))
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.red.opacity(0.8))
            Text(e.conditionSnapshot.displayDescription)
                .frame(width: 200, alignment: .leading)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    private static func formatTime(_ d: Date) -> String { timeFormatter.string(from: d) }

    private static func formatPrice(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        if abs(n - n.rounded()) < 0.01 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }

    // MARK: - 底部提示

    private var footerHint: some View {
        HStack(spacing: 16) {
            Label("通知通道（系统通知/声音）· 待 commit 4", systemImage: "bell.badge")
            Spacer()
            Text("v1 mock · 待 M5 接 AlertEvaluator + 持久化")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

// MARK: - 添加 / 编辑 预警 Sheet（commit 2/4 + 3/4 双模式）

/// 6 类可编辑 condition（horizontalLineTouched 需要 drawingID 选择 · 留 v2）
private enum ConditionKind: String, CaseIterable, Identifiable {
    case priceAbove       = "价格 >"
    case priceBelow       = "价格 <"
    case priceCrossAbove  = "上穿"
    case priceCrossBelow  = "下穿"
    case volumeSpike      = "成交量异常"
    case priceMoveSpike   = "价格急动"
    var id: String { rawValue }

    static func of(_ c: AlertCondition) -> ConditionKind {
        switch c {
        case .priceAbove:            return .priceAbove
        case .priceBelow:            return .priceBelow
        case .priceCrossAbove:       return .priceCrossAbove
        case .priceCrossBelow:       return .priceCrossBelow
        case .horizontalLineTouched: return .priceAbove   // v2 加 horizontalLine kind 时改
        case .volumeSpike:           return .volumeSpike
        case .priceMoveSpike:        return .priceMoveSpike
        }
    }
}

struct AddOrEditAlertSheet: View {
    let editing: Alert?
    let onSave: (Alert) -> Void
    @Environment(\.dismiss) private var dismiss

    // 基本字段
    @State private var name: String
    @State private var instrumentID: String
    @State private var status: AlertStatus
    @State private var cooldownSeconds: Int

    // 条件类型 + 6 套参数
    @State private var conditionKind: ConditionKind
    @State private var priceThreshold: Double
    @State private var volumeMultiple: Double
    @State private var volumeWindowBars: Int
    @State private var movePercent: Double
    @State private var moveSeconds: Int

    // 通知渠道
    @State private var enableInApp: Bool
    @State private var enableSystemNotice: Bool
    @State private var enableSound: Bool
    @State private var enableConsole: Bool
    @State private var enableFile: Bool

    init(editing: Alert?, onSave: @escaping (Alert) -> Void) {
        self.editing = editing
        self.onSave = onSave
        let a = editing
        self._name = State(initialValue: a?.name ?? "")
        self._instrumentID = State(initialValue: a?.instrumentID ?? "RB0")
        self._status = State(initialValue: a?.status ?? .active)
        self._cooldownSeconds = State(initialValue: Int(a?.cooldownSeconds ?? 60))
        self._conditionKind = State(initialValue: a.map { ConditionKind.of($0.condition) } ?? .priceAbove)

        var price = 3900.0, volMul = 3.0, mvPct = 1.0
        var volWin = 20, mvSec = 60
        if let cond = a?.condition {
            switch cond {
            case .priceAbove(let p), .priceBelow(let p),
                 .priceCrossAbove(let p), .priceCrossBelow(let p):
                price = NSDecimalNumber(decimal: p).doubleValue
            case .horizontalLineTouched(_, let p):
                price = NSDecimalNumber(decimal: p).doubleValue
            case .volumeSpike(let m, let n):
                volMul = NSDecimalNumber(decimal: m).doubleValue
                volWin = n
            case .priceMoveSpike(let p, let s):
                mvPct = NSDecimalNumber(decimal: p).doubleValue
                mvSec = s
            }
        }
        self._priceThreshold = State(initialValue: price)
        self._volumeMultiple = State(initialValue: volMul)
        self._volumeWindowBars = State(initialValue: volWin)
        self._movePercent = State(initialValue: mvPct)
        self._moveSeconds = State(initialValue: mvSec)

        let chs = a?.channels ?? [.inApp, .systemNotice]
        self._enableInApp = State(initialValue: chs.contains(.inApp))
        self._enableSystemNotice = State(initialValue: chs.contains(.systemNotice))
        self._enableSound = State(initialValue: chs.contains(.sound))
        self._enableConsole = State(initialValue: chs.contains(.console))
        self._enableFile = State(initialValue: chs.contains(.file))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editing == nil ? "添加预警" : "编辑预警")
                .font(.title2).bold().padding(.bottom, 12)

            Form {
                Section("基本") {
                    TextField("名称（必填）", text: $name)
                    TextField("合约", text: $instrumentID)
                    Picker("状态", selection: $status) {
                        ForEach(AlertStatus.allCases, id: \.self) { s in
                            Text(Self.statusLabel(s)).tag(s)
                        }
                    }
                }

                Section("条件") {
                    Picker("类型", selection: $conditionKind) {
                        ForEach(ConditionKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    conditionParams
                }

                Section("通知通道") {
                    Toggle("App 内浮窗", isOn: $enableInApp)
                    Toggle("系统通知中心", isOn: $enableSystemNotice)
                    Toggle("声音", isOn: $enableSound)
                    Toggle("控制台日志", isOn: $enableConsole)
                    Toggle("文件日志", isOn: $enableFile)
                    HStack {
                        Text("冷却（秒）")
                        TextField("", value: $cooldownSeconds, format: .number)
                            .frame(width: 80)
                    }
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "保存" : "更新") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    @ViewBuilder
    private var conditionParams: some View {
        switch conditionKind {
        case .priceAbove, .priceBelow, .priceCrossAbove, .priceCrossBelow:
            HStack {
                Text("阈值价格")
                TextField("", value: $priceThreshold, format: .number)
                    .frame(width: 120)
            }
        case .volumeSpike:
            HStack {
                Text("倍数 ≥")
                TextField("", value: $volumeMultiple, format: .number)
                    .frame(width: 80)
                Text("近")
                TextField("", value: $volumeWindowBars, format: .number)
                    .frame(width: 60)
                Text("期均值")
            }
        case .priceMoveSpike:
            HStack {
                Text("变化 ≥")
                TextField("", value: $movePercent, format: .number)
                    .frame(width: 80)
                Text("% / 窗口")
                TextField("", value: $moveSeconds, format: .number)
                    .frame(width: 60)
                Text("秒")
            }
        }
    }

    private func save() {
        let condition: AlertCondition = {
            switch conditionKind {
            case .priceAbove:      return .priceAbove(Decimal(priceThreshold))
            case .priceBelow:      return .priceBelow(Decimal(priceThreshold))
            case .priceCrossAbove: return .priceCrossAbove(Decimal(priceThreshold))
            case .priceCrossBelow: return .priceCrossBelow(Decimal(priceThreshold))
            case .volumeSpike:
                return .volumeSpike(multiple: Decimal(volumeMultiple), windowBars: volumeWindowBars)
            case .priceMoveSpike:
                return .priceMoveSpike(percentThreshold: Decimal(movePercent), windowSeconds: moveSeconds)
            }
        }()

        var channels: Set<NotificationChannelKind> = []
        if enableInApp { channels.insert(.inApp) }
        if enableSystemNotice { channels.insert(.systemNotice) }
        if enableSound { channels.insert(.sound) }
        if enableConsole { channels.insert(.console) }
        if enableFile { channels.insert(.file) }

        let alert = Alert(
            id: editing?.id ?? UUID(),
            name: name,
            instrumentID: instrumentID.isEmpty ? "RB0" : instrumentID,
            condition: condition,
            status: status,
            channels: channels,
            cooldownSeconds: TimeInterval(cooldownSeconds),
            createdAt: editing?.createdAt ?? Date(),
            lastTriggeredAt: editing?.lastTriggeredAt
        )
        onSave(alert)
        dismiss()
    }

    private static func statusLabel(_ s: AlertStatus) -> String {
        switch s {
        case .active:    return "活跃"
        case .triggered: return "已触发"
        case .paused:    return "暂停"
        case .cancelled: return "已取消"
        }
    }
}

// MARK: - AlertCondition UI 描述（仅 MainApp 用 · 不污染 AlertCore）

extension AlertCondition {
    /// 简短中文描述（列表 / 历史展示用）
    var displayDescription: String {
        switch self {
        case .priceAbove(let p):           return "价格 > \(formatDecimal(p))"
        case .priceBelow(let p):           return "价格 < \(formatDecimal(p))"
        case .priceCrossAbove(let p):      return "上穿 \(formatDecimal(p))"
        case .priceCrossBelow(let p):      return "下穿 \(formatDecimal(p))"
        case .horizontalLineTouched(_, let p): return "触线 \(formatDecimal(p))"
        case .volumeSpike(let m, let n):
            return "成交量 ≥ \(formatDecimal(m))× / \(n)期"
        case .priceMoveSpike(let p, let s):
            return "急动 ≥ \(formatDecimal(p))% / \(s)秒"
        }
    }

    private func formatDecimal(_ v: Decimal) -> String {
        let n = NSDecimalNumber(decimal: v).doubleValue
        if abs(n - n.rounded()) < 0.01 { return String(format: "%.0f", n) }
        return String(format: "%.2f", n)
    }
}

// MARK: - Mock alerts（v1 演示 · M5 替换为 AlertEvaluator + 持久化）

enum MockAlerts {
    /// 8 个示例 · 覆盖 6 condition 类 + 4 status 类 + 多合约
    static func generate() -> [Alert] {
        [
            Alert(name: "螺纹突破 3900",
                  instrumentID: "RB0",
                  condition: .priceAbove(3900)),
            Alert(name: "沪深 300 跌破 3450",
                  instrumentID: "IF0",
                  condition: .priceBelow(3450),
                  cooldownSeconds: 300),
            Alert(name: "黄金上穿 460",
                  instrumentID: "AU0",
                  condition: .priceCrossAbove(460),
                  channels: [.inApp, .systemNotice, .sound]),
            Alert(name: "铜下穿 72000",
                  instrumentID: "CU0",
                  condition: .priceCrossBelow(72000),
                  status: .triggered,
                  lastTriggeredAt: Date().addingTimeInterval(-120)),
            Alert(name: "螺纹成交量异常",
                  instrumentID: "RB0",
                  condition: .volumeSpike(multiple: 3, windowBars: 20),
                  channels: [.inApp]),
            Alert(name: "黄金 60 秒急动 1%",
                  instrumentID: "AU0",
                  condition: .priceMoveSpike(percentThreshold: 1, windowSeconds: 60),
                  status: .paused),
            Alert(name: "RB0 触水平线 3850",
                  instrumentID: "RB0",
                  condition: .horizontalLineTouched(drawingID: UUID(), price: 3850),
                  channels: [.inApp, .systemNotice]),
            Alert(name: "IF0 上穿 3550 月线",
                  instrumentID: "IF0",
                  condition: .priceCrossAbove(3550),
                  status: .cancelled,
                  cooldownSeconds: 0),
        ]
    }
}

// MARK: - Mock 触发历史（v1 演示 · M5 替换为 AlertHistoryStore.allHistory）

enum MockAlertHistory {
    /// 12 条 mock 触发记录 · 时间倒序近 24 小时
    static func generate() -> [AlertHistoryEntry] {
        let now = Date()
        let mockIDs = (0..<6).map { _ in UUID() }
        let template: [(String, String, Decimal, AlertCondition, String, Double)] = [
            ("螺纹突破 3900",        "RB0", 3905,  .priceAbove(3900),                                "RB0 价格 3905 > 3900",                  -300),
            ("黄金上穿 460",         "AU0", 460.5, .priceCrossAbove(460),                            "AU0 上穿 460",                          -1200),
            ("铜下穿 72000",         "CU0", 71850, .priceCrossBelow(72000),                          "CU0 下穿 72000",                        -3600),
            ("螺纹成交量异常",       "RB0", 3920,  .volumeSpike(multiple: 3, windowBars: 20),         "RB0 成交量 3.2× 近 20 期均值",          -7200),
            ("黄金 60 秒急动 1%",    "AU0", 462,   .priceMoveSpike(percentThreshold: 1, windowSeconds: 60), "AU0 60 秒涨 1.2%",                 -10800),
            ("沪深 300 跌破 3450",   "IF0", 3445,  .priceBelow(3450),                                "IF0 价格 3445 < 3450",                  -14400),
            ("螺纹突破 3900",        "RB0", 3902,  .priceAbove(3900),                                "RB0 价格 3902 > 3900（重复）",          -18000),
            ("RB0 触水平线 3850",    "RB0", 3850.5,.horizontalLineTouched(drawingID: UUID(), price: 3850), "RB0 触水平线 3850",                -25200),
            ("黄金上穿 460",         "AU0", 460.3, .priceCrossAbove(460),                            "AU0 再次上穿 460",                      -32400),
            ("螺纹成交量异常",       "RB0", 3895,  .volumeSpike(multiple: 3, windowBars: 20),         "RB0 成交量 4.1× 异常",                  -50400),
            ("沪深 300 跌破 3450",   "IF0", 3448,  .priceBelow(3450),                                "IF0 跌破触发",                          -68400),
            ("铜下穿 72000",         "CU0", 71990, .priceCrossBelow(72000),                          "CU0 边界下穿",                          -86400),
        ]
        return template.enumerated().map { (i, t) in
            AlertHistoryEntry(
                alertID: mockIDs[i % mockIDs.count],
                alertName: t.0,
                instrumentID: t.1,
                triggerPrice: t.2,
                triggeredAt: now.addingTimeInterval(t.5),
                conditionSnapshot: t.3,
                message: t.4
            )
        }
    }
}

#endif
