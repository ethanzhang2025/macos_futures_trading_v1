// MainApp · 预警面板 Scene（WP-52 UI · 8 alerts × 4 status × 8 condition × 5 channel · v15.12 持仓量异动）
//
// 留待 Mac 切机：UserNotifications channel · NSSound channel（替换对应 LoggingChannel）
// M5 持久化已接入：alerts 走 SQLiteAlertConfigStore（.task 异步 load · .onChange 异步 save · nil 才 fallback Mock · 空数组合法）
//                  history 走 SQLiteAlertHistoryStore（.task 异步 load · 空库 fallback Mock · evaluator 接入后写库）
// 留待 M5：AlertEvaluator onTick 实接 · 真实触发后 store.append → UI 自动刷新（监听机制）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import AlertCore
import StoreCore

/// 消除 Mac 端 SwiftUI.Alert（deprecated 但仍存在）与 AlertCore.Alert 命名歧义
/// Linux 编译跳过整个 SwiftUI 块 · 不暴露此冲突 · Mac 必须显式限定
/// 注：默认 internal 而非 private · 否则文件内 internal 属性（如 AlertFormDraft.alert: Alert?）违反"private 类型用于更宽访问级别属性"规则
typealias Alert = AlertCore.Alert

// MARK: - Tab 切换

private enum AlertTab: String, CaseIterable, Identifiable {
    case list    = "预警列表"
    case history = "触发历史"
    case console = "通知日志"
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
    @State private var consoleLog: [String] = []
    @State private var dispatcher: NotificationDispatcher = NotificationDispatcher()

    /// M5 持久化：load 完成前 isLoaded=false · 期间 alerts mutation 不触发 save（避免 onChange 把 Mock 写覆盖真数据）
    @State private var isLoaded: Bool = false

    /// v11.0+1 · evaluator observe stream 监听任务 · onDisappear cancel
    @State private var evaluatorObserveTask: Task<Void, Never>?

    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics
    @Environment(\.alertEvaluator) private var alertEvaluator

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
            // M5 启动加载：alerts 优先从 SQLiteAlertConfigStore 加载 · nil（首次启动）才 fallback Mock · 空数组合法保留
            if let store = storeManager?.alertConfig,
               let loaded = (try? await store.load()) ?? nil {
                alerts = loaded
            } else {
                alerts = MockAlerts.generate()
            }
            isLoaded = true
            // M5 持久化：history 优先从 SQLiteAlertHistoryStore 加载 · 协议非 Optional · try? 失败 fallback Mock
            // 空数组合法（用户清空 / evaluator 未触发但已开启 store）· 与 alerts 加载语义一致
            if let store = storeManager?.alertHistory,
               let loaded = try? await store.allHistory() {
                historyEntries = loaded
            } else {
                historyEntries = MockAlertHistory.generate()
            }
            await registerChannels()
            // v11.0+1 · evaluator wiring：alerts 加载后全部 addAlert · 启动 observe 监听真实触发
            await syncAlertsToEvaluator(newValue: alerts, oldValue: [])
            startEvaluatorObserve()
        }
        .onChange(of: alerts) { newValue in
            // M5 自动持久化：每次 alerts 变化异步 save（add/edit/delete/toggle/markTriggered 都覆盖）
            guard isLoaded, let store = storeManager?.alertConfig else { return }
            Task { try? await store.save(newValue) }
            // v11.0+1 · evaluator 同步（diff add/update/remove · updateAlert 内部保 lastTriggeredAt）
            Task { await syncAlertsToEvaluator(newValue: newValue, oldValue: []) }
        }
        .onDisappear {
            evaluatorObserveTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .alertAddedFromChart)) { notification in
            // v13.18 ChartScene 右键画线创建的预警 → 加入 alerts list（自动 onChange save + evaluator sync）
            guard let alert = notification.object as? Alert else { return }
            // 防重复（同 ID 已存在 → 跳过）
            if alerts.contains(where: { $0.id == alert.id }) { return }
            alerts.append(alert)
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
        let counts = alerts.reduce(into: (active: 0, triggered: 0, paused: 0)) { acc, a in
            switch a.status {
            case .active:    acc.active += 1
            case .triggered: acc.triggered += 1
            case .paused:    acc.paused += 1
            case .cancelled: break
            }
        }
        return HStack(spacing: 24) {
            Text("🔔 预警面板").font(.title2).bold()
            Divider().frame(height: 24)
            stat("总数", "\(alerts.count)")
            stat("活跃", "\(counts.active)", color: .green)
            stat("已触发", "\(counts.triggered)", color: .red)
            stat("已暂停", "\(counts.paused)", color: .secondary)
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
        case .console:
            consoleLogList
        }
    }

    /// 注册 5 个 LoggingNotificationChannel · Mac 切机时把 .systemNotice / .sound 替换为真实 channel
    private func registerChannels() async {
        for kind in NotificationChannelKind.allCases {
            let channel = LoggingNotificationChannel(kind: kind) { msg in
                Task { @MainActor in
                    appendConsoleLog("[\(kind.rawValue)] \(msg)")
                }
            }
            await dispatcher.register(channel)
        }
    }

    @MainActor
    private func appendConsoleLog(_ line: String) {
        let ts = Self.timeFormatter.string(from: Date())
        consoleLog.append("\(ts) | \(line)")
        if consoleLog.count > 100 {
            consoleLog.removeFirst(consoleLog.count - 100)
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
                Text("操作").frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(alerts, id: \.id) { alert in
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
            statusBadge(a.status).frame(width: 70, alignment: .center)
            Text(a.channels.map(\.shortLabel).sorted().joined(separator: "·"))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            Text("\(Int(a.cooldownSeconds))s")
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)
            rowActions(a).frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func rowActions(_ a: Alert) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await testTrigger(a) }
            } label: {
                Image(systemName: "paperplane.circle").foregroundColor(.purple)
            }
            .buttonStyle(.borderless)
            .help("测试触发（走 channel 通知 + 加历史）")

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
                Image(systemName: "square.and.pencil").foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .help("编辑")

            Button {
                deleteAlert(a)
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
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

    /// 模拟触发一次预警 · dispatch 走已注册的 channels + 标记 status + 写入 historyEntries
    private func testTrigger(_ a: Alert) async {
        let event = NotificationEvent(
            alertID: a.id,
            alertName: a.name,
            instrumentID: a.instrumentID,
            triggerPrice: Self.testTriggerPrice(a.condition),
            triggeredAt: Date(),
            message: "测试触发 · \(a.condition.displayDescription)"
        )
        await dispatcher.dispatch(event, to: a.channels)
        markAlertTriggered(a, at: event.triggeredAt)
        appendHistoryEntry(from: a, event: event)
        // 埋点：alert 触发 · test=true 区分 Mock 触发（Stage B 接 evaluator 真触发时记 test=false）
        if let service = analytics {
            _ = try? await service.record(
                .alertTrigger,
                userID: FuturesTerminalApp.anonymousUserID,
                properties: [
                    "alert_name": a.name,
                    "instrument": a.instrumentID,
                    "test": "true"
                ]
            )
        }
    }

    private func markAlertTriggered(_ a: Alert, at: Date) {
        guard let idx = alerts.firstIndex(where: { $0.id == a.id }) else { return }
        var copy = alerts[idx]
        copy.status = .triggered
        copy.lastTriggeredAt = at
        alerts[idx] = copy
    }

    private func appendHistoryEntry(from a: Alert, event: NotificationEvent) {
        let entry = AlertHistoryEntry(
            alertID: a.id,
            alertName: a.name,
            instrumentID: a.instrumentID,
            conditionSnapshot: a.condition,
            triggeredAt: event.triggeredAt,
            triggerPrice: event.triggerPrice,
            message: event.message
        )
        historyEntries.insert(entry, at: 0)
        // M5 持久化：testTrigger 走此路径（不通过 evaluator）· evaluator 真触发由 fire() 内部 history.append 写库 + observe stream 推 UI
        if let store = storeManager?.alertHistory {
            Task { try? await store.append(entry) }
        }
    }

    // MARK: - v11.0+1 · evaluator wiring

    /// 同步 alerts 数组到 evaluator · diff add/update/remove
    /// updateAlert 内部保留 lastTriggeredAt（用户改 condition/name 不应重置冷却）
    /// 参数 oldValue 当前未用（每次重新查 evaluator.allAlerts() 作为真实旧 set）· 保留接口扩展空间
    private func syncAlertsToEvaluator(newValue: [Alert], oldValue: [Alert]) async {
        guard let evaluator = alertEvaluator else { return }
        let existing = await evaluator.allAlerts()
        let existingIDs = Set(existing.map(\.id))
        let newIDs = Set(newValue.map(\.id))
        for id in existingIDs.subtracting(newIDs) {
            await evaluator.removeAlert(id: id)
        }
        for alert in newValue {
            if existingIDs.contains(alert.id) {
                _ = await evaluator.updateAlert(alert)
            } else {
                await evaluator.addAlert(alert)
            }
        }
    }

    /// 启动 observe stream · 收 evaluator 真触发 event → UI insert（store.append 已 evaluator 内部完成）
    private func startEvaluatorObserve() {
        guard let evaluator = alertEvaluator, evaluatorObserveTask == nil else { return }
        evaluatorObserveTask = Task {
            for await event in await evaluator.observe() {
                let entry = AlertHistoryEntry(
                    alertID: event.alertID,
                    alertName: event.alertName,
                    instrumentID: event.instrumentID,
                    conditionSnapshot: alerts.first(where: { $0.id == event.alertID })?.condition ?? .priceAbove(0),
                    triggeredAt: event.triggeredAt,
                    triggerPrice: event.triggerPrice,
                    message: event.message
                )
                await MainActor.run {
                    historyEntries.insert(entry, at: 0)
                }
            }
        }
    }

    /// 按 condition 生成测试触发价（让 displayDescription 显示有意义的数字）
    private static func testTriggerPrice(_ c: AlertCondition) -> Decimal {
        switch c {
        case .priceAbove(let p):                return p + 1
        case .priceBelow(let p):                return p - 1
        case .priceCrossAbove(let p):           return p
        case .priceCrossBelow(let p):           return p
        case .horizontalLineTouched(_, let p):  return p
        case .volumeSpike, .openInterestSpike, .priceMoveSpike:  return 0
        case .indicator:                        return 0
        }
    }

    /// 状态徽章（圆角 + 白字 + 颜色背景）
    private func statusBadge(_ s: AlertStatus) -> some View {
        Text(s.displayLabel)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(s.badgeColor.opacity(0.8))
            .cornerRadius(3)
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
                emptyState(icon: "clock.arrow.circlepath", text: "暂无触发历史")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyEntries, id: \.id) { entry in
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
            Text(Self.timeFormatter.string(from: e.triggeredAt))
                .frame(width: 150, alignment: .leading)
                .foregroundColor(.secondary)
            Text(e.alertName).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.instrumentID).frame(width: 60, alignment: .leading)
            Text(fmtDecimal(e.triggerPrice))
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

    // MARK: - 通知日志 Tab

    private var consoleLogList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LoggingNotificationChannel 输出（最近 100 条 · UserNotifications/NSSound 留 Mac 切机）")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("清空") { consoleLog.removeAll() }
                    .disabled(consoleLog.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            if consoleLog.isEmpty {
                emptyState(icon: "terminal", text: "暂无通知输出 · 点击预警行 📤 测试触发")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(consoleLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text(text).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部提示

    private var footerHint: some View {
        HStack(spacing: 16) {
            Label("已注册 5 channel（内/通/声/控/文 · LoggingChannel）", systemImage: "bell.badge")
            Spacer()
            Text("v1 mock · UserNotifications/NSSound 待 Mac · M5 接 AlertEvaluator + 持久化")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}

// MARK: - 添加 / 编辑 预警 Sheet

/// 8 类可编辑 condition（horizontalLineTouched 需 drawingID 选择 · 留 v2）
private enum ConditionKind: String, CaseIterable, Identifiable {
    case priceAbove          = "价格 >"
    case priceBelow          = "价格 <"
    case priceCrossAbove     = "上穿"
    case priceCrossBelow     = "下穿"
    case volumeSpike         = "成交量异常"
    case openInterestSpike   = "持仓量异常"
    case priceMoveSpike      = "价格急动"
    case indicator           = "指标条件"
    var id: String { rawValue }

    static func of(_ c: AlertCondition) -> ConditionKind {
        switch c {
        case .priceAbove:            return .priceAbove
        case .priceBelow:            return .priceBelow
        case .priceCrossAbove:       return .priceCrossAbove
        case .priceCrossBelow:       return .priceCrossBelow
        case .horizontalLineTouched: return .priceAbove   // v2 加 horizontalLine kind 时改
        case .volumeSpike:           return .volumeSpike
        case .openInterestSpike:     return .openInterestSpike
        case .priceMoveSpike:        return .priceMoveSpike
        case .indicator:             return .indicator
        }
    }
}

/// Sheet 表单草稿（聚合字段 · 替代零散 @State · v2 加新 condition kind 单点扩展）
private struct AlertFormDraft {
    var name: String = ""
    var instrumentID: String = "RB0"
    var status: AlertStatus = .active
    var cooldownSeconds: Int = 60

    var conditionKind: ConditionKind = .priceAbove
    var priceThreshold: Double = 3900
    var volumeMultiple: Double = 3
    var volumeWindowBars: Int = 20
    // v15.12 WP-52 v3 持仓量异动字段（与 volume 分开 · 显式优于复用避免切换 conditionKind 串值）
    var oiMultiple: Double = 1.5
    var oiWindowBars: Int = 20
    var movePercent: Double = 1
    var moveSeconds: Int = 60

    // 指标条件预警字段（v15.x · 仅 conditionKind == .indicator 用到）
    var indicatorKind: IndicatorKind = .ma
    var indicatorParam0: Double = 20    // MA period / EMA period / MACD fast / RSI period
    var indicatorParam1: Double = 26    // MACD slow（其他指标忽略）
    var indicatorParam2: Double = 9     // MACD signal（其他指标忽略）
    var indicatorPeriod: KLinePeriod = .minute5
    var indicatorEventTag: IndicatorEventTag = .priceCrossAbove
    var indicatorRSIThreshold: Double = 70

    var channels: Set<NotificationChannelKind> = [.inApp, .systemNotice]

    init(from alert: Alert? = nil) {
        guard let a = alert else { return }
        name = a.name
        instrumentID = a.instrumentID
        status = a.status
        cooldownSeconds = Int(a.cooldownSeconds)
        conditionKind = ConditionKind.of(a.condition)
        loadConditionParams(from: a.condition)
        channels = a.channels
    }

    private mutating func loadConditionParams(from c: AlertCondition) {
        switch c {
        case .priceAbove(let p), .priceBelow(let p),
             .priceCrossAbove(let p), .priceCrossBelow(let p):
            priceThreshold = NSDecimalNumber(decimal: p).doubleValue
        case .horizontalLineTouched(_, let p):
            priceThreshold = NSDecimalNumber(decimal: p).doubleValue
        case .volumeSpike(let m, let n):
            volumeMultiple = NSDecimalNumber(decimal: m).doubleValue
            volumeWindowBars = n
        case .openInterestSpike(let m, let n):
            oiMultiple = NSDecimalNumber(decimal: m).doubleValue
            oiWindowBars = n
        case .priceMoveSpike(let p, let s):
            movePercent = NSDecimalNumber(decimal: p).doubleValue
            moveSeconds = s
        case .indicator(let spec):
            indicatorKind = spec.indicator
            indicatorPeriod = spec.period
            // params 按 indicatorParam0/1/2 顺序加载（每条预警按 indicatorKind 决定填几位 · MACD=3 / 其他=1）
            if spec.params.count >= 1 { indicatorParam0 = NSDecimalNumber(decimal: spec.params[0]).doubleValue }
            if spec.params.count >= 2 { indicatorParam1 = NSDecimalNumber(decimal: spec.params[1]).doubleValue }
            if spec.params.count >= 3 { indicatorParam2 = NSDecimalNumber(decimal: spec.params[2]).doubleValue }
            switch spec.event {
            case .priceCrossAboveLine: indicatorEventTag = .priceCrossAbove
            case .priceCrossBelowLine: indicatorEventTag = .priceCrossBelow
            case .macdGoldenCross:     indicatorEventTag = .macdGolden
            case .macdDeathCross:      indicatorEventTag = .macdDeath
            case .rsiCrossAbove(let t):
                indicatorEventTag = .rsiCrossAbove
                indicatorRSIThreshold = NSDecimalNumber(decimal: t).doubleValue
            case .rsiCrossBelow(let t):
                indicatorEventTag = .rsiCrossBelow
                indicatorRSIThreshold = NSDecimalNumber(decimal: t).doubleValue
            }
        }
    }

    func toCondition() -> AlertCondition {
        switch conditionKind {
        case .priceAbove:      return .priceAbove(Decimal(priceThreshold))
        case .priceBelow:      return .priceBelow(Decimal(priceThreshold))
        case .priceCrossAbove: return .priceCrossAbove(Decimal(priceThreshold))
        case .priceCrossBelow: return .priceCrossBelow(Decimal(priceThreshold))
        case .volumeSpike:
            return .volumeSpike(multiple: Decimal(volumeMultiple), windowBars: volumeWindowBars)
        case .openInterestSpike:
            return .openInterestSpike(multiple: Decimal(oiMultiple), windowBars: oiWindowBars)
        case .priceMoveSpike:
            return .priceMoveSpike(percentThreshold: Decimal(movePercent), windowSeconds: moveSeconds)
        case .indicator:
            let params: [Decimal]
            switch indicatorKind {
            case .macd: params = [Decimal(indicatorParam0), Decimal(indicatorParam1), Decimal(indicatorParam2)]
            default:    params = [Decimal(indicatorParam0)]
            }
            let event: IndicatorEvent
            switch indicatorEventTag {
            case .priceCrossAbove: event = .priceCrossAboveLine
            case .priceCrossBelow: event = .priceCrossBelowLine
            case .macdGolden:      event = .macdGoldenCross
            case .macdDeath:       event = .macdDeathCross
            case .rsiCrossAbove:   event = .rsiCrossAbove(Decimal(indicatorRSIThreshold))
            case .rsiCrossBelow:   event = .rsiCrossBelow(Decimal(indicatorRSIThreshold))
            }
            let spec = IndicatorAlertSpec(indicator: indicatorKind, params: params, event: event, period: indicatorPeriod)
            return .indicator(spec)
        }
    }
}

/// 指标事件的扁平 tag（UI 表单用 · 与 IndicatorEvent 之间双向映射 · RSI 阈值单独存 indicatorRSIThreshold）
private enum IndicatorEventTag: String, CaseIterable, Identifiable {
    case priceCrossAbove = "价格上穿单线"
    case priceCrossBelow = "价格下穿单线"
    case macdGolden      = "MACD 金叉"
    case macdDeath       = "MACD 死叉"
    case rsiCrossAbove   = "RSI 上穿阈值"
    case rsiCrossBelow   = "RSI 下穿阈值"
    var id: String { rawValue }
}

struct AddOrEditAlertSheet: View {
    let editing: Alert?
    let onSave: (Alert) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlertFormDraft

    init(editing: Alert?, onSave: @escaping (Alert) -> Void) {
        self.editing = editing
        self.onSave = onSave
        self._draft = State(initialValue: AlertFormDraft(from: editing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editing == nil ? "添加预警" : "编辑预警")
                .font(.title2).bold().padding(.bottom, 12)

            Form {
                Section("基本") {
                    TextField("名称（必填）", text: $draft.name)
                    TextField("合约", text: $draft.instrumentID)
                    Picker("状态", selection: $draft.status) {
                        ForEach(AlertStatus.allCases, id: \.self) { s in
                            Text(s.displayLabel).tag(s)
                        }
                    }
                }

                Section("条件") {
                    Picker("类型", selection: $draft.conditionKind) {
                        ForEach(ConditionKind.allCases) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    conditionParams
                }

                Section("通知通道") {
                    ForEach(NotificationChannelKind.allCases, id: \.self) { kind in
                        Toggle(kind.displayLabel, isOn: bindingForChannel(kind))
                    }
                    HStack {
                        Text("冷却（秒）")
                        TextField("", value: $draft.cooldownSeconds, format: .number)
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
                    .disabled(draft.name.isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    @ViewBuilder
    private var conditionParams: some View {
        switch draft.conditionKind {
        case .priceAbove, .priceBelow, .priceCrossAbove, .priceCrossBelow:
            HStack {
                Text("阈值价格")
                TextField("", value: $draft.priceThreshold, format: .number)
                    .frame(width: 120)
            }
        case .volumeSpike:
            HStack {
                Text("倍数 ≥")
                TextField("", value: $draft.volumeMultiple, format: .number)
                    .frame(width: 80)
                Text("近")
                TextField("", value: $draft.volumeWindowBars, format: .number)
                    .frame(width: 60)
                Text("期均值")
            }
        case .openInterestSpike:
            HStack {
                Text("倍数 ≥")
                TextField("", value: $draft.oiMultiple, format: .number)
                    .frame(width: 80)
                Text("近")
                TextField("", value: $draft.oiWindowBars, format: .number)
                    .frame(width: 60)
                Text("期均值")
            }
        case .priceMoveSpike:
            HStack {
                Text("变化 ≥")
                TextField("", value: $draft.movePercent, format: .number)
                    .frame(width: 80)
                Text("% / 窗口")
                TextField("", value: $draft.moveSeconds, format: .number)
                    .frame(width: 60)
                Text("秒")
            }
        case .indicator:
            indicatorParams
        }
    }

    @ViewBuilder
    private var indicatorParams: some View {
        Picker("指标", selection: $draft.indicatorKind) {
            ForEach(IndicatorKind.allCases, id: \.self) { k in
                Text(k.displayName).tag(k)
            }
        }
        .onChange(of: draft.indicatorKind) { newKind in
            // 切换指标时按默认参数重置 + 选默认事件
            let defaults = newKind.defaultParams
            if defaults.count >= 1 { draft.indicatorParam0 = NSDecimalNumber(decimal: defaults[0]).doubleValue }
            if defaults.count >= 2 { draft.indicatorParam1 = NSDecimalNumber(decimal: defaults[1]).doubleValue }
            if defaults.count >= 3 { draft.indicatorParam2 = NSDecimalNumber(decimal: defaults[2]).doubleValue }
            switch newKind {
            case .ma, .ema: draft.indicatorEventTag = .priceCrossAbove
            case .macd:     draft.indicatorEventTag = .macdGolden
            case .rsi:      draft.indicatorEventTag = .rsiCrossAbove
            }
        }

        Picker("周期", selection: $draft.indicatorPeriod) {
            ForEach(KLinePeriod.allCases, id: \.self) { p in
                Text(p.displayName).tag(p)
            }
        }

        // 参数表单按指标种类显示对应字段数
        switch draft.indicatorKind {
        case .ma:
            HStack {
                Text("MA 周期")
                TextField("", value: $draft.indicatorParam0, format: .number).frame(width: 80)
            }
        case .ema:
            HStack {
                Text("EMA 周期")
                TextField("", value: $draft.indicatorParam0, format: .number).frame(width: 80)
            }
        case .macd:
            HStack {
                Text("快线")
                TextField("", value: $draft.indicatorParam0, format: .number).frame(width: 60)
                Text("慢线")
                TextField("", value: $draft.indicatorParam1, format: .number).frame(width: 60)
                Text("信号")
                TextField("", value: $draft.indicatorParam2, format: .number).frame(width: 60)
            }
        case .rsi:
            HStack {
                Text("RSI 周期")
                TextField("", value: $draft.indicatorParam0, format: .number).frame(width: 80)
            }
        }

        Picker("事件", selection: $draft.indicatorEventTag) {
            ForEach(supportedEventTags(for: draft.indicatorKind), id: \.self) { tag in
                Text(tag.rawValue).tag(tag)
            }
        }

        if draft.indicatorEventTag == .rsiCrossAbove || draft.indicatorEventTag == .rsiCrossBelow {
            HStack {
                Text("阈值")
                TextField("", value: $draft.indicatorRSIThreshold, format: .number).frame(width: 80)
            }
        }
    }

    private func supportedEventTags(for kind: IndicatorKind) -> [IndicatorEventTag] {
        switch kind {
        case .ma, .ema: return [.priceCrossAbove, .priceCrossBelow]
        case .macd:     return [.macdGolden, .macdDeath]
        case .rsi:      return [.rsiCrossAbove, .rsiCrossBelow]
        }
    }

    private func bindingForChannel(_ kind: NotificationChannelKind) -> Binding<Bool> {
        Binding(
            get: { draft.channels.contains(kind) },
            set: { isOn in
                if isOn { draft.channels.insert(kind) } else { draft.channels.remove(kind) }
            }
        )
    }

    private func save() {
        let alert = Alert(
            id: editing?.id ?? UUID(),
            name: draft.name,
            instrumentID: draft.instrumentID.isEmpty ? "RB0" : draft.instrumentID,
            condition: draft.toCondition(),
            status: draft.status,
            channels: draft.channels,
            cooldownSeconds: TimeInterval(draft.cooldownSeconds),
            createdAt: editing?.createdAt ?? Date(),
            lastTriggeredAt: editing?.lastTriggeredAt
        )
        onSave(alert)
        dismiss()
    }
}

// MARK: - Enum 扩展（仅 MainApp UI 用 · 不污染 AlertCore）

extension AlertStatus {
    /// 中文标签（badge + Picker 共用）
    var displayLabel: String {
        switch self {
        case .active:    return "活跃"
        case .triggered: return "已触发"
        case .paused:    return "暂停"
        case .cancelled: return "已取消"
        }
    }

    var badgeColor: Color {
        switch self {
        case .active:    return .green
        case .triggered: return .red
        case .paused:    return .orange
        case .cancelled: return .secondary
        }
    }
}

extension NotificationChannelKind {
    /// 单字简写（列表通道列展示）
    var shortLabel: String {
        switch self {
        case .inApp:        return "内"
        case .systemNotice: return "通"
        case .sound:        return "声"
        case .console:      return "控"
        case .file:         return "文"
        }
    }

    /// 完整中文名（Form Toggle 标题用）
    var displayLabel: String {
        switch self {
        case .inApp:        return "App 内浮窗"
        case .systemNotice: return "系统通知中心"
        case .sound:        return "声音"
        case .console:      return "控制台日志"
        case .file:         return "文件日志"
        }
    }
}

extension AlertCondition {
    /// 简短中文描述（列表 / 历史展示用）
    var displayDescription: String {
        switch self {
        case .priceAbove(let p):                return "价格 > \(fmtDecimal(p))"
        case .priceBelow(let p):                return "价格 < \(fmtDecimal(p))"
        case .priceCrossAbove(let p):           return "上穿 \(fmtDecimal(p))"
        case .priceCrossBelow(let p):           return "下穿 \(fmtDecimal(p))"
        case .horizontalLineTouched(_, let p):  return "触线 \(fmtDecimal(p))"
        case .volumeSpike(let m, let n):        return "成交量 ≥ \(fmtDecimal(m))× / \(n)期"
        case .openInterestSpike(let m, let n):  return "持仓量 ≥ \(fmtDecimal(m))× / \(n)期"
        case .priceMoveSpike(let p, let s):     return "急动 ≥ \(fmtDecimal(p))% / \(s)秒"
        case .indicator(let spec):              return spec.displayDescription
        }
    }
}

/// file-private · 整数无小数 · 非整数 2 位 · displayDescription / row 列共用
private func fmtDecimal(_ v: Decimal) -> String {
    let n = NSDecimalNumber(decimal: v).doubleValue
    if abs(n - n.rounded()) < 0.01 { return String(format: "%.0f", n) }
    return String(format: "%.2f", n)
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

    /// 历史模板（替代 6-tuple · 字段自描述 · 不易写错）
    private struct HistoryTemplate {
        let name: String
        let instrumentID: String
        let triggerPrice: Decimal
        let condition: AlertCondition
        let message: String
        let secondsAgo: Double
    }

    /// 12 条 mock 触发记录 · 时间倒序近 24 小时
    static func generate() -> [AlertHistoryEntry] {
        let now = Date()
        let mockIDs = (0..<6).map { _ in UUID() }
        let templates: [HistoryTemplate] = [
            .init(name: "螺纹突破 3900",       instrumentID: "RB0", triggerPrice: 3905,
                  condition: .priceAbove(3900),
                  message: "RB0 价格 3905 > 3900",                  secondsAgo: -300),
            .init(name: "黄金上穿 460",        instrumentID: "AU0", triggerPrice: 460.5,
                  condition: .priceCrossAbove(460),
                  message: "AU0 上穿 460",                          secondsAgo: -1200),
            .init(name: "铜下穿 72000",        instrumentID: "CU0", triggerPrice: 71850,
                  condition: .priceCrossBelow(72000),
                  message: "CU0 下穿 72000",                        secondsAgo: -3600),
            .init(name: "螺纹成交量异常",      instrumentID: "RB0", triggerPrice: 3920,
                  condition: .volumeSpike(multiple: 3, windowBars: 20),
                  message: "RB0 成交量 3.2× 近 20 期均值",          secondsAgo: -7200),
            .init(name: "黄金 60 秒急动 1%",   instrumentID: "AU0", triggerPrice: 462,
                  condition: .priceMoveSpike(percentThreshold: 1, windowSeconds: 60),
                  message: "AU0 60 秒涨 1.2%",                      secondsAgo: -10800),
            .init(name: "沪深 300 跌破 3450",  instrumentID: "IF0", triggerPrice: 3445,
                  condition: .priceBelow(3450),
                  message: "IF0 价格 3445 < 3450",                  secondsAgo: -14400),
            .init(name: "螺纹突破 3900",       instrumentID: "RB0", triggerPrice: 3902,
                  condition: .priceAbove(3900),
                  message: "RB0 价格 3902 > 3900（重复）",          secondsAgo: -18000),
            .init(name: "RB0 触水平线 3850",   instrumentID: "RB0", triggerPrice: 3850.5,
                  condition: .horizontalLineTouched(drawingID: UUID(), price: 3850),
                  message: "RB0 触水平线 3850",                     secondsAgo: -25200),
            .init(name: "黄金上穿 460",        instrumentID: "AU0", triggerPrice: 460.3,
                  condition: .priceCrossAbove(460),
                  message: "AU0 再次上穿 460",                      secondsAgo: -32400),
            .init(name: "螺纹成交量异常",      instrumentID: "RB0", triggerPrice: 3895,
                  condition: .volumeSpike(multiple: 3, windowBars: 20),
                  message: "RB0 成交量 4.1× 异常",                  secondsAgo: -50400),
            .init(name: "沪深 300 跌破 3450",  instrumentID: "IF0", triggerPrice: 3448,
                  condition: .priceBelow(3450),
                  message: "IF0 跌破触发",                          secondsAgo: -68400),
            .init(name: "铜下穿 72000",        instrumentID: "CU0", triggerPrice: 71990,
                  condition: .priceCrossBelow(72000),
                  message: "CU0 边界下穿",                          secondsAgo: -86400),
        ]
        return templates.enumerated().map { (i, t) in
            AlertHistoryEntry(
                alertID: mockIDs[i % mockIDs.count],
                alertName: t.name,
                instrumentID: t.instrumentID,
                conditionSnapshot: t.condition,
                triggeredAt: now.addingTimeInterval(t.secondsAgo),
                triggerPrice: t.triggerPrice,
                message: t.message
            )
        }
    }
}

/// v13.18 ChartScene 创建画线预警 → 通知 AlertWindow 同步到 alerts list（持久化 + evaluator）
extension Notification.Name {
    public static let alertAddedFromChart = Notification.Name("alertAddedFromChart")
}

#endif
