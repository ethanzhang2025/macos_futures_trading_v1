// MainApp · 预警面板 Scene（WP-52 UI · 8 alerts × 4 status × 8 condition × 5 channel · v15.12 持仓量异动）
//
// v15.17 完成：NotificationChannels.swift 提供 SystemNoticeChannel + SoundChannel + InAppOverlayChannel macOS 实现
// FuturesTerminalApp 注入 dispatcher · 用户预警真触发 toast + 系统通知 + Glass 声音三通道
// M5 持久化已接入：alerts 走 SQLiteAlertConfigStore（.task 异步 load · .onChange 异步 save · nil 才 fallback Mock · 空数组合法）
//                  history 走 SQLiteAlertHistoryStore（.task 异步 load · 空库 fallback Mock · evaluator 接入后写库）
// 留待 M5+：AlertEvaluator onTick 实接 · 真实触发后 store.append → UI 自动刷新（监听机制）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import Shared
import DataCore
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
    var displayName: String { L(rawValue) }
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
    @State private var alertInstrumentFilter: String = ""   // "" = 全部 · 否则只显示指定合约
    /// v15.69 · 条件类型过滤（segmented · 全部 / 价格类 / 价差类 / 指标类）
    @State private var conditionTypeFilter: ConditionTypeFilter = .all

    enum ConditionTypeFilter: String, CaseIterable, Identifiable {
        case all       // 全部
        case price     // 价格类（priceAbove/Below/Cross/MoveSpike/Breakout/horizontalLine）
        case spread    // 价差偏离
        case indicator // 指标条件
        case extras    // 异动 · 成交量/持仓量

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .all:       return "全部"
            case .price:     return "价格类"
            case .spread:    return "价差类"
            case .indicator: return "指标类"
            case .extras:    return "异动"
            }
        }

        func matches(_ c: AlertCondition) -> Bool {
            switch (self, c) {
            case (.all, _): return true
            case (.price, .priceAbove), (.price, .priceBelow),
                 (.price, .priceCrossAbove), (.price, .priceCrossBelow),
                 (.price, .priceMoveSpike), (.price, .priceBreakoutHigh),
                 (.price, .priceBreakoutLow), (.price, .horizontalLineTouched):
                return true
            case (.spread, .spreadDeviation): return true
            case (.indicator, .indicator): return true
            case (.extras, .volumeSpike), (.extras, .openInterestSpike):
                return true
            default: return false
            }
        }
    }
    /// v15.20 batch57 · 多选批量操作 · alertRow checkbox 状态 · 走 AlertBatchOperator 纯函数
    @State private var selectedAlertIDs: Set<UUID> = []
    /// v15.20 batch69 · 列表排序（@AppStorage 持久化 · 重启保留 · 默认 .manual 创建顺序）
    @AppStorage("viewState.v1.alert.sortFieldRaw") private var alertSortFieldRaw: String = AlertSortField.manual.rawValue
    @AppStorage("viewState.v1.alert.sortAscending") private var alertSortAscending: Bool = true
    /// v15.21 batch90 · 新建预警默认 cooldown 秒数（trader 工作流个性化 · 持久化）
    @AppStorage("viewState.v1.alert.defaultCooldownSeconds") private var defaultCooldownSeconds: Int = 60

    private var alertSortField: AlertSortField {
        AlertSortField(rawValue: alertSortFieldRaw) ?? .manual
    }
    private func setAlertSortField(_ field: AlertSortField) {
        alertSortFieldRaw = field.rawValue
    }
    /// v15.20 batch62 · 历史 row 展开 · 显示完整触发详情
    @State private var expandedHistoryID: UUID?
    @State private var historyEntries: [AlertHistoryEntry] = []
    @State private var historyWindow: AlertHistoryFilter.Window = .all
    @State private var historySearchText: String = ""   // v15.19 batch46 · 按预警名搜索
    /// 缓存：filteredHistory + summary 一次算多处用 · 避免每次 body re-eval 重算
    @State private var filteredHistory: [AlertHistoryEntry] = []
    @State private var historySummary = AlertHistoryStatistics.Summary(total: 0, byInstrument: [], byKind: [], byHour: [:])
    @State private var selectedTab: AlertTab = .list
    @State private var sheetState: SheetState?
    @State private var consoleLog: [String] = []
    @State private var dispatcher: NotificationDispatcher = NotificationDispatcher()

    /// M5 持久化：load 完成前 isLoaded=false · 期间 alerts mutation 不触发 save（避免 onChange 把 Mock 写覆盖真数据）
    @State private var isLoaded: Bool = false

    /// v11.0+1 · evaluator observe stream 监听任务 · onDisappear cancel
    @State private var evaluatorObserveTask: Task<Void, Never>?

    /// v15.21 batch93 · 历史 tab 搜索框聚焦（⌘F 触发 · trader 高频快搜）
    @FocusState private var isHistorySearchFocused: Bool
    /// v15.21 batch135 · 删除确认对话框（防止 trash 按钮误点丢失复杂条件预警）
    @State private var pendingDeleteAlert: Alert?
    /// v15.21 batch95 · 列表 tab 搜索框（按预警名 / 合约 / 条件描述模糊匹配）
    @State private var alertSearchText: String = ""
    @FocusState private var isAlertSearchFocused: Bool

    /// v15.23 batch193 · 帮助面板（⌘⇧? · 主窗口 UX 一致补完）
    @State private var showHelpSheet: Bool = false

    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics
    @Environment(\.alertEvaluator) private var alertEvaluator
    @Environment(\.openWindow) private var openWindow
    /// v17.6 · Shell 嵌入模式（隐藏顶部 header · 由 Shell PrimaryTabBar 统一管理）
    @Environment(\.isHostedInShell) private var isHostedInShell

    var body: some View {
        VStack(spacing: 0) {
            if !isHostedInShell {
                header
                Divider()
            }
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
            recomputeHistoryCache()
        }
        .onChange(of: historyEntries) { _ in recomputeHistoryCache() }
        .onChange(of: historyWindow) { _ in recomputeHistoryCache() }
        .onChange(of: historySearchText) { _ in recomputeHistoryCache() }
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
        // v15.21 batch128 · 跨窗口联动 · WatchlistWindow / ChartScene 触发 → 自动切 list tab + filter 合约
        .onReceive(NotificationCenter.default.publisher(for: .alertWindowFilterToInstrument)) { notification in
            guard let id = notification.object as? String else { return }
            selectedTab = .list
            alertInstrumentFilter = id
            alertSearchText = ""    // 清搜索 · 让 instrument filter 全权显示
        }
        // v15.21 batch135 · 单条删除确认对话框（防 trash 按钮 / contextMenu "删除…" 误点 · 与 watchlist groupRow 一致）
        .confirmationDialog(
            "删除预警？",
            isPresented: Binding(
                get: { pendingDeleteAlert != nil },
                set: { if !$0 { pendingDeleteAlert = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteAlert
        ) { alert in
            Button("删除「\(alert.name)」", role: .destructive) {
                deleteAlert(alert)
                pendingDeleteAlert = nil
            }
            Button("取消", role: .cancel) { pendingDeleteAlert = nil }
        } message: { alert in
            Text("\(alert.instrumentID) · \(alert.condition.displayDescription)")
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .add:
                AddOrEditAlertSheet(editing: nil, defaultCooldownSeconds: defaultCooldownSeconds) { newAlert in
                    alerts.append(newAlert)
                }
            case .edit(let alert):
                AddOrEditAlertSheet(editing: alert, defaultCooldownSeconds: defaultCooldownSeconds) { updated in
                    if let idx = alerts.firstIndex(where: { $0.id == updated.id }) {
                        alerts[idx] = updated
                    }
                }
            }
        }
        // v15.23 batch193 · 帮助面板（⌘⇧? · 主窗口 UX 一致补完）
        .sheet(isPresented: $showHelpSheet) { helpSheet }
        .background(
            Group {
                Button("") { showHelpSheet = true }
                    .keyboardShortcut("?", modifiers: [.command, .shift])
                // v15.23 batch204 · ⌘1/⌘2/⌘3 切 tab（与 JournalWindow/TrainingWindow 模式一致）
                Button("") { selectedTab = .list }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("") { selectedTab = .history }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("") { selectedTab = .console }
                    .keyboardShortcut("3", modifiers: [.command])
            }
            .opacity(0)
        )
    }

    // MARK: - v15.23 batch193 · 帮助面板（与 ReviewWindow / WorkspaceWindow / JournalWindow / WatchlistWindow 模式一致）

    private static let helpGroups: [(String, [(String, String)])] = [
        ("📑 Tab 切换", [
            ("⌘1 (batch204)", "切到「预警列表」"),
            ("⌘2 (batch204)", "切到「触发历史」"),
            ("⌘3 (batch204)", "切到「通知日志」"),
            ("段控制 Picker", "顶部 segmented picker 直接点击"),
        ]),
        ("➕ 添加 / 编辑预警", [
            ("➕ 按钮", "添加新预警（弹 sheet · 价格 / 指标 / 区间 / 复合 4 类条件）"),
            ("contextMenu", "编辑 / 暂停 / 复制 / 删除"),
            ("跨窗口创建", "ChartScene 画线后右键创建预警（v13.18+）"),
            ("跨窗口查看 (batch201)", "右键 → 在主图查看「instrumentID」· 切 ChartScene + 联动合约"),
        ]),
        ("🔍 搜索 / 筛选", [
            ("⌘F", "聚焦搜索框（list 或 history tab · 自动判断当前）"),
            ("Esc", "清空搜索 + 选择"),
            ("instrument filter", "WatchlistWindow / ChartScene 触发跨窗口 filter（v15.21 batch128）"),
        ]),
        ("📦 批量操作", [
            ("AlertBatchOperator", "批量启用 / 暂停 / setChannels / setCooldown（v15.21 batch127）"),
            ("contextMenu 多选", "右键批量操作"),
        ]),
        ("📤 导出（v15.23 batch198/207）", [
            ("Header 导出按钮 / ⌘E", "alerts 配置 CSV（8 字段 · BOM · Excel 中文友好）"),
            ("文件名", "alerts配置-N条-yyyy-MM-dd.csv"),
            ("用途", "trader 备份 / 团队分享 / 报税审计"),
        ]),
        ("📊 统计与反馈", [
            ("header stat", "总数 / 活跃 / 已触发 / 已暂停 + 24h / 本周触发活跃度"),
            ("toast 反馈", "添加 / 删除 / 暂停 等操作 toast 提示（v15.21 batch134）"),
            ("测距三态 toast", "触发 / 关闭 / 误差超限"),
        ]),
        ("⌨️ 通用", [
            ("⌘⇧?", "唤出本帮助面板（v15.23 batch193）"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 预警面板全功能").font(.title2).bold()
                Spacer()
                Button("关闭") { showHelpSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.helpGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.0).font(.headline)
                            ForEach(group.1, id: \.0) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(item.0)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 200, alignment: .leading)
                                    Text(item.1).font(.system(size: 12))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 580, idealWidth: 680, minHeight: 480, idealHeight: 600)
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
            stat(L("总数"), "\(alerts.count)")
            stat(L("活跃"), "\(counts.active)", color: .green)
            stat(L("已触发"), "\(counts.triggered)", color: .red)
            stat(L("已暂停"), "\(counts.paused)", color: .secondary)
            // v15.20 batch79 · 触发活跃度统计（24h / 本周 · trader 看预警系统是否活跃）
            Divider().frame(height: 24)
            stat(L("24h 触发"), "\(triggerCounts.last24h)", color: triggerCounts.last24h > 0 ? .orange : .secondary)
            stat(L("本周触发"), "\(triggerCounts.thisWeek)", color: .secondary)
            Spacer()
            Menu {
                Button("添加预警…") { sheetState = .add }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Text("📋 一键创建模板（trader 常用）").font(.caption).foregroundColor(.secondary)
                ForEach(AlertPreset.allCases) { preset in
                    Button(preset.displayName) { presentPresetSheet(preset) }
                        .tooltip(preset.helpText)
                }
                Divider()
                Button("全部 6 类一次创建…") { presentPresetSheet(nil) }
                    .tooltip("一次创建 6 类常用预警 · 适合新合约入场快速布防")
            } label: {
                Label("添加", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 80)
            .tooltip("添加预警 / 一键模板")

            // v15.23 batch198 · 导出 alerts 配置 CSV（trader 备份 / 团队分享）
            // v15.23 batch207 · 加 ⌘E 快捷键
            Button {
                exportAlertsCSV()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("e", modifiers: [.command])
            .tooltip("导出预警配置 CSV（含 BOM Excel 友好 · 8 字段 · ⌘E）")
            .disabled(alerts.isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    /// v15.23 batch198 · 导出当前 alerts 列表为 CSV
    @MainActor
    private func exportAlertsCSV() {
        guard !alerts.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.title = L("导出预警配置 CSV")
        panel.prompt = L("导出")
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "alerts配置-\(alerts.count)条-\(dateStr).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AlertConfigCSVExporter.exportData(alerts).write(to: url)
            Toast.info("导出成功", "\(alerts.count) 条预警 → \(url.lastPathComponent)")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    /// 一键模板入口 · NSAlert 让用户填合约 + 当前价 → 批量 emit alertAddedFromChart
    /// - Parameter preset: nil = 全部 6 类一次性创建 · 否则只创建该单一 preset
    @MainActor
    private func presentPresetSheet(_ preset: AlertPreset?) {
        let nsAlert = NSAlert()
        let title = preset?.displayName ?? "一次创建全部 6 类"
        nsAlert.messageText = "📋 \(title)"
        nsAlert.informativeText = L("输入合约 + 当前价 · 自动用合理默认创建预警 · 创建后可在列表编辑")
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.frame = NSRect(x: 0, y: 0, width: 260, height: 70)
        let instField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        instField.placeholderString = L("合约（如 RB0 / IF0）")
        instField.stringValue = "RB0"
        let priceField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        priceField.placeholderString = L("当前价（涨跌停 ±5% 基准）")
        priceField.stringValue = "3500"
        container.addArrangedSubview(instField)
        container.addArrangedSubview(priceField)
        nsAlert.accessoryView = container
        nsAlert.addButton(withTitle: L("创建"))
        nsAlert.addButton(withTitle: L("取消"))
        guard nsAlert.runModal() == .alertFirstButtonReturn else { return }
        let inst = instField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inst.isEmpty, let priceDouble = Double(priceField.stringValue) else { return }
        let lastPrice = Decimal(priceDouble)
        let presets: [AlertPreset] = preset.map { [$0] } ?? AlertPreset.allCases
        let newAlerts = AlertPreset.makeAlerts(presets, instrumentID: inst, lastPrice: lastPrice)
        for alert in newAlerts {
            NotificationCenter.default.post(name: .alertAddedFromChart, object: alert)
        }
        Toast.info("已创建 \(newAlerts.count) 条预警", "在列表中可逐条编辑 / 暂停 / 删除。")
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
                Text(t.displayName).tag(t)
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

    /// 当前 alerts 中出现的全部 instrumentID（升序去重）· 用于 Picker
    private var availableInstruments: [String] {
        Array(Set(alerts.map(\.instrumentID))).sorted()
    }

    /// 应用合约筛选 + v15.20 batch69 排序 + v15.21 batch95 搜索 + v15.69 条件类型过滤
    private var filteredAlerts: [Alert] {
        var scoped = alertInstrumentFilter.isEmpty ? alerts : alerts.filter { $0.instrumentID == alertInstrumentFilter }
        // v15.69 · 条件类型过滤
        if conditionTypeFilter != .all {
            scoped = scoped.filter { conditionTypeFilter.matches($0.condition) }
        }
        // batch95 · 名/合约/条件描述 模糊匹配（不区分大小写 · 空字符串跳过过滤）
        let q = alertSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            scoped = scoped.filter {
                $0.name.lowercased().contains(q)
                    || $0.instrumentID.lowercased().contains(q)
                    || $0.condition.displayDescription.lowercased().contains(q)
            }
        }
        return AlertSorter.sort(scoped, field: alertSortField, ascending: alertSortAscending)
    }

    /// v15.69 · 各条件类型当前 alerts 数量（segmented label 用 · 显 "(N)"）
    private func conditionTypeCount(_ filter: ConditionTypeFilter) -> Int {
        if filter == .all { return alerts.count }
        return alerts.lazy.filter { filter.matches($0.condition) }.count
    }

    /// v15.20 batch79 · 触发活跃度统计（24h / 本周 · 走 historyEntries 触发时间过滤）
    private var triggerCounts: (last24h: Int, thisWeek: Int) {
        let now = Date()
        let day = now.addingTimeInterval(-24 * 3600)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        cal.firstWeekday = 2   // 周一作周起（中国习惯 · 与 AlertHistoryFilter.range 一致）
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? day
        var d24 = 0
        var dWeek = 0
        for entry in historyEntries {
            if entry.triggeredAt >= day { d24 += 1 }
            if entry.triggeredAt >= weekStart { dWeek += 1 }
        }
        return (d24, dWeek)
    }

    private var alertsList: some View {
        VStack(spacing: 0) {
            // v15.19 batch42 · 合约筛选 + v15.20 batch57 · 批量操作 toolbar · v15.21 batch95 加搜索框
            HStack(spacing: 8) {
                // v15.21 batch95 · 搜索框（按预警名 / 合约 / 条件描述 模糊匹配 · ⌘F 聚焦 · Esc 清空）
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("搜索预警（⌘F）", text: $alertSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .focused($isAlertSearchFocused)
                    if !alertSearchText.isEmpty {
                        Button { alertSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.escape, modifiers: [])
                        .tooltip("清空搜索（Esc）")
                    }
                }
                Button("") { isAlertSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                // v15.69 · 条件类型过滤（segmented）
                Picker("", selection: $conditionTypeFilter) {
                    ForEach(ConditionTypeFilter.allCases) { f in
                        Text("\(f.displayName) (\(conditionTypeCount(f)))").tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .tooltip("按条件类型过滤 · 价格类/价差类/指标类/异动")
                Text("合约筛选").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $alertInstrumentFilter) {
                    Text("全部 (\(alerts.count))").tag("")
                    ForEach(availableInstruments, id: \.self) { inst in
                        let count = alerts.lazy.filter { $0.instrumentID == inst }.count
                        Text("\(inst) (\(count))").tag(inst)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                if !selectedAlertIDs.isEmpty {
                    Divider().frame(height: 16)
                    Text("已选 \(selectedAlertIDs.count) 条")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.blue)
                    Button("批量暂停") { batchPauseSelected() }
                        .buttonStyle(.borderless)
                        .tooltip("把选中的 active/triggered 预警转为 paused")
                    Button("批量恢复") { batchResumeSelected() }
                        .buttonStyle(.borderless)
                        .tooltip("把选中的 paused 预警转为 active")
                    Button("批量复制") { batchDuplicateSelected() }
                        .buttonStyle(.borderless)
                        .tooltip("每条复制一份 · 名后缀（副本）· 默认 paused")
                    Button("重置冷却") { batchResetCooldownSelected() }
                        .buttonStyle(.borderless)
                        .tooltip("清 lastTriggeredAt · triggered 回 active · 立即可再触发")
                    // v15.21 batch127 · 批量改通道 + 改 cooldown（trader 实战：开盘前/关键时段统一调整）
                    Menu("批量通道") {
                        Button("仅 inApp（静音盘中）")    { batchSetChannelsSelected([.inApp]) }
                        Button("inApp + 系统通知")       { batchSetChannelsSelected([.inApp, .systemNotice]) }
                        Button("inApp + 声音")          { batchSetChannelsSelected([.inApp, .sound]) }
                        Button("全通道（关键 alert）")    { batchSetChannelsSelected(Set(NotificationChannelKind.allCases)) }
                    }
                    .tooltip("批量替换选中预警的通道（覆盖式 · 不合并）")
                    Menu("批量 cooldown") {
                        Button("30 秒（高频）")  { batchSetCooldownSelected(30) }
                        Button("60 秒（默认）")  { batchSetCooldownSelected(60) }
                        Button("5 分钟（趋势）") { batchSetCooldownSelected(300) }
                        Button("30 分钟（长波段）") { batchSetCooldownSelected(1800) }
                    }
                    .tooltip("批量调整选中预警的 cooldown 秒数")
                    Button("批量删除") { batchDeleteSelected() }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .tooltip("彻底删除选中的预警")
                    Button("清空选择") { selectedAlertIDs.removeAll() }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.escape, modifiers: [])
                        .tooltip("取消所有选中（Esc）")
                }
                Spacer()
                // v15.20 batch69 · 排序 Menu（持久化 · 同字段切升降）
                Menu {
                    ForEach(AlertSortField.allCases, id: \.rawValue) { field in
                        Button(action: {
                            if alertSortField == field { alertSortAscending.toggle() }
                            else { setAlertSortField(field); alertSortAscending = true }
                        }) {
                            let arrow = alertSortField == field ? (alertSortAscending ? " ↑" : " ↓") : ""
                            Text(field.displayName + arrow)
                        }
                    }
                } label: {
                    let arrow = alertSortAscending ? "↑" : "↓"
                    Label("排序 \(alertSortField.displayName) \(alertSortField == .manual ? "" : arrow)",
                          systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
                .tooltip("按字段排序 · 同字段再选切升降序")
                if filteredAlerts.allSatisfy({ selectedAlertIDs.contains($0.id) }) && !filteredAlerts.isEmpty {
                    Button("全不选") { selectedAlertIDs.subtract(filteredAlerts.map(\.id)) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .tooltip("全部取消选中（⌘⇧A）")
                } else {
                    Button("全选") { selectedAlertIDs.formUnion(filteredAlerts.map(\.id)) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .tooltip("全选当前显示的预警（⌘A）")
                }
                // v15.21 batch99 · ⌘A 全选 / ⌘⇧A 全不选 · 不可见快捷键 · trader 批量操作前快速选齐
                Button("") { selectedAlertIDs.formUnion(filteredAlerts.map(\.id)) }
                    .keyboardShortcut("a", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                Button("") { selectedAlertIDs.subtract(filteredAlerts.map(\.id)) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                Text("当前显示 \(filteredAlerts.count) / \(alerts.count) 条")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            HStack(spacing: 8) {
                // v15.20 batch57 · 多选 checkbox 列
                Text("☑").frame(width: 18, alignment: .center)
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("合约 / 价差").frame(width: 100, alignment: .leading)  // v15.63 · 60 → 100 容纳 spread name
                Text("条件").frame(width: 220, alignment: .leading)         // v15.63 · 200 → 220 容纳 spread |z| 描述
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
                    ForEach(filteredAlerts, id: \.id) { alert in
                        alertRow(alert)
                        Divider()
                    }
                }
            }
        }
    }

    /// v15.63 · spread alert 显价差对名 + 图标 · 普通 alert 显裸 instrumentID
    @ViewBuilder
    private func instrumentColumn(for a: Alert) -> some View {
        if case let .spreadDeviation(id, cal, _) = a.condition {
            HStack(spacing: 4) {
                Image(systemName: cal ? "calendar" : "arrow.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(cal ? .cyan : .orange)
                Text(AlertCondition.spreadDisplayName(id: id, isCalendar: cal))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
            .tooltip(cal ? "跨期价差对 · 关联近月 \(a.instrumentID)" : "跨品种价差对 · 关联 \(a.instrumentID)")
        } else {
            Text(a.instrumentID)
        }
    }

    private func alertRow(_ a: Alert) -> some View {
        HStack(spacing: 8) {
            // v15.20 batch57 · 多选 checkbox（点击切换 selectedAlertIDs）
            Image(systemName: selectedAlertIDs.contains(a.id) ? "checkmark.square.fill" : "square")
                .foregroundColor(selectedAlertIDs.contains(a.id) ? .blue : .secondary)
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedAlertIDs.contains(a.id) {
                        selectedAlertIDs.remove(a.id)
                    } else {
                        selectedAlertIDs.insert(a.id)
                    }
                }
            // v15.21 batch125 · row 字段 .tooltip() tooltip · trader 列宽 truncate 时鼠标悬停看完整
            Text(a.name).frame(maxWidth: .infinity, alignment: .leading)
                .tooltip(a.name.count > 30 ? a.name : "")   // 长名才提示 · 短名不打扰
            // v15.63 · spread alert 显 价差对名 + 图标 · 普通 alert 显 instrumentID
            instrumentColumn(for: a)
                .frame(width: 100, alignment: .leading)
            Text(a.condition.displayDescription).frame(width: 220, alignment: .leading)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .tooltip(a.condition.displayDescription)    // 完整条件 · 复杂指标条件经常超 200px
            // v15.21 batch116 · 状态 badge 点击切换 active/paused（最直观入口 · 与"暂停"按钮 / contextMenu 三入口）
            statusBadgeWithAge(a)
                .frame(width: 70, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { toggleStatus(a) }
                .tooltip("点击切换暂停 / 恢复（cancelled 状态不响应）")
            Text(a.channels.map(\.shortLabel).sorted().joined(separator: "·"))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
                .tooltip(a.channels.map(\.displayLabel).sorted().joined(separator: " / "))   // batch125 · 通道全名
            Text("\(Int(a.cooldownSeconds))s")
                .frame(width: 50, alignment: .trailing)
                .foregroundColor(.secondary)
            rowActions(a).frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // v15.21 batch107 · 双击 row → 编辑预警 sheet（trader 流畅工作流 · 与 batch102 watchlist groupRow 一致）
        .onTapGesture(count: 2) { sheetState = .edit(a) }
        // v15.20 batch73 · 右键 contextMenu 完整操作集（与 row buttons 互补 · 含 batch72 重置冷却 + 复制 + 选中辅助）
        .contextMenu {
            Button("测试触发") { Task { await testTrigger(a) } }
            Button(a.status == .paused ? "恢复" : "暂停") { toggleStatus(a) }
                .disabled(a.status == .cancelled)
            Button("重置冷却") { resetCooldownSingle(a) }
                .disabled(a.lastTriggeredAt == nil && a.status != .triggered)
            Divider()
            Button("编辑…（双击 row 也行）") { sheetState = .edit(a) }
            Button("复制 alert 名") { copyAlertName(a) }
            // v15.23 batch201 · 在主图查看（切到 ChartScene + post .watchlistInstrumentSelected）
            Button("在主图查看「\(a.instrumentID)」") { openInstrumentInChart(a.instrumentID) }
            Divider()
            if selectedAlertIDs.contains(a.id) {
                Button("从选中移除") { selectedAlertIDs.remove(a.id) }
            } else {
                Button("加入选中") { selectedAlertIDs.insert(a.id) }
            }
            Divider()
            Button("删除…", role: .destructive) { pendingDeleteAlert = a }   // v15.21 batch135 · 弹确认
        }
    }

    /// v15.20 batch73 · 单条重置冷却（contextMenu 用 · 复用 batch72 batch operator 单 ID 集合）
    private func resetCooldownSingle(_ a: Alert) {
        alerts = AlertBatchOperator.resetCooldown(ids: [a.id], in: alerts)
    }

    /// v15.20 batch73 · 复制 alert 名到剪贴板
    private func copyAlertName(_ a: Alert) {
        Pasteboard.copy(a.name)
    }

    /// v15.23 batch201 · 在主图查看（切到 ChartScene + 触发合约联动 · 与 WatchlistWindow openInstrumentInChart 同模式）
    @MainActor
    private func openInstrumentInChart(_ instrumentID: String) {
        openWindow(id: "chart")
        NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: instrumentID)
        Toast.info("已切到主图", "\(instrumentID)")
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
            .tooltip("测试触发（走 channel 通知 + 加历史）")

            Button {
                toggleStatus(a)
            } label: {
                Image(systemName: a.status == .paused ? "play.circle" : "pause.circle")
                    .foregroundColor(a.status == .paused ? .green : .orange)
            }
            .buttonStyle(.borderless)
            .tooltip(a.status == .paused ? "恢复" : "暂停")
            .disabled(a.status == .cancelled)

            Button {
                sheetState = .edit(a)
            } label: {
                Image(systemName: "square.and.pencil").foregroundColor(.blue)
            }
            .buttonStyle(.borderless)
            .tooltip("编辑")

            Button {
                pendingDeleteAlert = a   // v15.21 batch135 · 弹确认对话框防误删
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .tooltip("删除（弹确认）")
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
        selectedAlertIDs.remove(a.id)
        // v15.21 batch134 · 删除反馈 toast（trader 不可逆操作 · 至少有视觉确认）
        Toast.info("已删除预警", "\(a.name) · \(a.instrumentID)")
    }

    // MARK: - v15.20 batch57 · 批量操作（走 AlertBatchOperator 纯函数）

    private func batchPauseSelected() {
        alerts = AlertBatchOperator.pause(ids: selectedAlertIDs, in: alerts)
    }

    private func batchResumeSelected() {
        alerts = AlertBatchOperator.resume(ids: selectedAlertIDs, in: alerts)
    }

    private func batchDeleteSelected() {
        let count = selectedAlertIDs.count
        alerts = AlertBatchOperator.delete(ids: selectedAlertIDs, in: alerts)
        selectedAlertIDs.removeAll()
        // v15.21 batch134 · 批量删除反馈 toast
        if count > 0 {
            Toast.info("已批量删除", "\(count) 条预警已删除")
        }
    }

    private func batchDuplicateSelected() {
        let result = AlertBatchOperator.duplicate(ids: selectedAlertIDs, in: alerts)
        alerts = result.alerts
        selectedAlertIDs = result.newIDs    // 自动跳到新副本以便后续操作
    }

    /// v15.21 batch127 · 批量改通道 / cooldown（走 AlertBatchOperator · UI 走 toolbar Menu）
    private func batchSetChannelsSelected(_ channels: Set<NotificationChannelKind>) {
        alerts = AlertBatchOperator.setChannels(ids: selectedAlertIDs, channels: channels, in: alerts)
    }

    private func batchSetCooldownSelected(_ seconds: Int) {
        alerts = AlertBatchOperator.setCooldown(ids: selectedAlertIDs, seconds: seconds, in: alerts)
    }

    private func batchResetCooldownSelected() {
        alerts = AlertBatchOperator.resetCooldown(ids: selectedAlertIDs, in: alerts)
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
    /// v15.16 hotfix #11：alerts 查找移入 MainActor.run · 之前在 Task 内直接读 @State 是 Swift 6 严格并发风险
    private func startEvaluatorObserve() {
        guard let evaluator = alertEvaluator, evaluatorObserveTask == nil else { return }
        evaluatorObserveTask = Task {
            for await event in await evaluator.observe() {
                await MainActor.run {
                    let condition = alerts.first(where: { $0.id == event.alertID })?.condition ?? .priceAbove(0)
                    let entry = AlertHistoryEntry(
                        alertID: event.alertID,
                        alertName: event.alertName,
                        instrumentID: event.instrumentID,
                        conditionSnapshot: condition,
                        triggeredAt: event.triggeredAt,
                        triggerPrice: event.triggerPrice,
                        message: event.message
                    )
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
        case .priceBreakoutHigh, .priceBreakoutLow:  return 0   // v15.19+ batch16 · onBar 评估 · 测试触发价 0
        case .spreadDeviation:                  return 0   // v15.57 · placeholder · 不参与测试触发
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

    /// v15.20 batch80 · status badge + 最近触发距今（trader 看每条 alert 上次触发时刻）
    /// lastTriggeredAt nil → 仅显 badge · 否则 badge 上方显微"5m" / "2h" / "3d"
    @ViewBuilder
    private func statusBadgeWithAge(_ a: Alert) -> some View {
        VStack(spacing: 2) {
            statusBadge(a.status)
            if let last = a.lastTriggeredAt {
                Text(Self.compactAge(from: last))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// v15.20 batch80 · 紧凑距今格式（"5m" / "2h" / "3d" / "<1m"）· 行内 9pt 显示用
    static func compactAge(from date: Date, now: Date = Date()) -> String {
        let secs = max(0, now.timeIntervalSince(date))
        if secs < 60 {        return "<1m" }
        if secs < 3600 {      return "\(Int(secs / 60))m" }
        if secs < 86400 {     return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86400))d"
    }

    // MARK: - 触发历史列表

    /// 重算 filteredHistory + historySummary（historyEntries / historyWindow / historySearchText 变时调用）
    private func recomputeHistoryCache() {
        var filtered = AlertHistoryFilter.apply(historyEntries, window: historyWindow)
        let search = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            filtered = filtered.filter {
                $0.alertName.localizedCaseInsensitiveContains(search)
                    || $0.instrumentID.localizedCaseInsensitiveContains(search)
            }
        }
        filteredHistory = filtered
        historySummary = AlertHistoryStatistics.summarize(filtered)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            historyToolbar
            if !filteredHistory.isEmpty {
                historySummaryStrip
                historyHourChart   // v15.19 batch32 · 24h 触发分布 mini bar
            }
            historyTableHeader

            if filteredHistory.isEmpty {
                emptyState(icon: "clock.arrow.circlepath", text: "当前窗口无触发历史")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredHistory, id: \.id) { entry in
                            historyRow(entry)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    /// v15.19 batch32 · 24 小时触发分布 mini bar chart（trader 一眼看自己什么时段触发预警最多）
    /// 高度 36 · 高度等比 visible max · 中国期货活跃时段（早 9-11 / 午 13-15 / 夜 21-23）应有明显起伏
    private var historyHourChart: some View {
        let buckets = historySummary.byHour
        let maxCount = buckets.values.max() ?? 1
        return HStack(alignment: .bottom, spacing: 1) {
            Text("24h")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            ForEach(0..<24, id: \.self) { h in
                let count = buckets[h] ?? 0
                let ratio = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
                VStack(spacing: 2) {
                    Spacer()
                    Rectangle()
                        .fill(barColorForHour(h, hasData: count > 0))
                        .frame(height: max(2, 30 * ratio))
                    Text("\(h)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .tooltip(count > 0 ? "\(h):00 触发 \(count) 次" : "\(h):00 无触发")
            }
        }
        .frame(height: 50)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// 中国期货活跃时段染色（活跃 9-11/13-15/21-23 染主色 · 其他染浅）
    private func barColorForHour(_ h: Int, hasData: Bool) -> Color {
        guard hasData else { return Color.secondary.opacity(0.18) }
        let active = (9...11).contains(h) || (13...15).contains(h) || (21...23).contains(h)
        return active ? Color.orange.opacity(0.85) : Color.blue.opacity(0.65)
    }

    /// 时间窗口 segmented + 搜索 + 导出（trader 模式分析入口）
    private var historyToolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $historyWindow) {
                ForEach(AlertHistoryFilter.Window.allCases) { w in
                    Text(w.rawValue).tag(w)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            // v15.19 batch46 · 搜索框（按预警名 / 合约名 · 不区分大小写）· v15.21 batch93 加 ⌘F 聚焦
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField("搜索预警名 / 合约（⌘F）", text: $historySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($isHistorySearchFocused)
                if !historySearchText.isEmpty {
                    Button { historySearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape, modifiers: [])
                    .tooltip("清空搜索（Esc）")
                }
            }
            // v15.21 batch93 · ⌘F 聚焦搜索框（视觉零占用 · 仅快捷键拦截）
            Button("") { isHistorySearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            Spacer()
            Text("共 \(filteredHistory.count) 条 · 全量 \(historyEntries.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Button("导出 CSV…") { exportHistoryCSV() }
                .disabled(filteredHistory.isEmpty)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .tooltip("导出当前筛选窗口的触发历史为 CSV · ⌘⇧E")
            // v15.21 batch111 · 复制为 Markdown 表格（不弹保存 · 直接 Pasteboard · trader 贴 IM/邮件）
            Button("复制 Markdown") { copyHistoryAsMarkdown() }
                .disabled(filteredHistory.isEmpty)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .tooltip("复制当前筛选窗口的触发历史为 Markdown 表格到剪贴板（⌘⇧C）")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// 分组统计 strip（按合约 + 按条件类型 · trader 一眼看自己触发模式）
    private var historySummaryStrip: some View {
        let s = historySummary
        return HStack(spacing: 16) {
            if !s.byInstrument.isEmpty {
                summaryGroup(label: "合约", chips: s.byInstrument.prefix(5).map { ($0.key, $0.count) })
            }
            if !s.byKind.isEmpty {
                summaryGroup(label: "类型", chips: s.byKind.prefix(6).map { ($0.key.rawValue, $0.count) })
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func summaryGroup(label: String, chips: [(String, Int)]) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundColor(.secondary)
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                HStack(spacing: 3) {
                    Text(chip.0).font(.caption)
                    Text("\(chip.1)").font(.caption.bold())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.14))
                .cornerRadius(4)
            }
        }
    }

    private var historyTableHeader: some View {
        HStack(spacing: 8) {
            Text("时间").frame(width: 150, alignment: .leading)
            Text("预警").frame(maxWidth: .infinity, alignment: .leading)
            Text("合约 / 价差").frame(width: 100, alignment: .leading)  // v15.66 · 同 alertRow 一致
            Text("触发价").frame(width: 80, alignment: .trailing)
            Text("条件").frame(width: 220, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    /// v15.21 batch111 · 复制当前筛选窗口的触发历史为 Markdown 表格（直接 Pasteboard · 不弹保存）
    @MainActor
    private func copyHistoryAsMarkdown() {
        let entries = filteredHistory
        guard !entries.isEmpty else { return }
        var lines: [String] = []
        lines.append("| 时间 | 预警 | 合约 | 触发价 | 条件 | 通道 |")
        lines.append("|---|---|---|---|---|---|")
        for e in entries {
            let t = Self.timeFormatter.string(from: e.triggeredAt)
            let price = fmtDecimal(e.triggerPrice)
            let condition = e.conditionSnapshot.displayDescription
            lines.append("| \(t) | \(e.alertName) | \(e.instrumentID) | \(price) | \(condition) | - |")
        }
        Pasteboard.copy(lines.joined(separator: "\n"))
        Toast.info("已复制", "\(entries.count) 条触发历史 → Markdown 表格已在剪贴板。")
    }

    /// AlertHistory CSV 导出（NSSavePanel · UTF-8 BOM · trader 报税 / 复盘归档）
    @MainActor
    private func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.title = L("导出预警触发历史")
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "alert_history_\(dateFmt.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entriesToExport = filteredHistory
        let data = AlertHistoryCSVExporter.exportData(entriesToExport)
        do {
            try data.write(to: url, options: .atomic)
            Toast.info("导出成功",
                       "已导出 \(entriesToExport.count) 条触发历史（窗口：\(historyWindow.rawValue)）到 \(url.lastPathComponent)。")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    /// v15.66 · 历史 row spread alert instrumentColumn（同 v15.63 alertRow 渲染）
    @ViewBuilder
    private func historyInstrumentColumn(for e: AlertHistoryEntry) -> some View {
        if case let .spreadDeviation(id, cal, _) = e.conditionSnapshot {
            HStack(spacing: 4) {
                Image(systemName: cal ? "calendar" : "arrow.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(cal ? .cyan : .orange)
                Text(AlertCondition.spreadDisplayName(id: id, isCalendar: cal))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
        } else {
            Text(e.instrumentID)
        }
    }

    private func historyRow(_ e: AlertHistoryEntry) -> some View {
        let isExpanded = expandedHistoryID == e.id
        let alertStillExists = alerts.contains { $0.id == e.alertID }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                // v15.21 batch122 · 时间字段 hover 显示完整含秒 + Unix timestamp（trader 精确到秒看触发时刻）
                Text(Self.timeFormatter.string(from: e.triggeredAt))
                    .frame(width: 138, alignment: .leading)
                    .foregroundColor(.secondary)
                    .tooltip("Unix 时间戳：\(Int(e.triggeredAt.timeIntervalSince1970))（已含秒级精度）")
                Text(e.alertName).frame(maxWidth: .infinity, alignment: .leading)
                // v15.66 · 历史 row 同 alertRow 一致：spread alert 显价差对名 + 图标
                historyInstrumentColumn(for: e)
                    .frame(width: 100, alignment: .leading)
                Text(fmtDecimal(e.triggerPrice))
                    .frame(width: 80, alignment: .trailing)
                    .foregroundColor(.red.opacity(0.8))
                Text(e.conditionSnapshot.displayDescription)
                    .frame(width: 220, alignment: .leading)
                    .foregroundColor(.secondary)
                // v15.21 batch122 · 末尾加触发距今 age（与 alert row batch80 一致 · trader 看历史新旧度）
                Text(Self.compactAge(from: e.triggeredAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                expandedHistoryID = isExpanded ? nil : e.id
            }
            // v15.20 batch77 · 历史 row 右键 contextMenu · v15.21 batch132 · 复制项收成 Menu
            .contextMenu {
                Menu("📋 复制") {
                    Button("详情") { copyHistoryDetail(e) }
                    Button("时间戳") { copyHistoryTimestamp(e) }
                    Button("本条一行（紧凑）") {
                        let line = "\(Self.timeFormatter.string(from: e.triggeredAt)) | \(e.alertName) | \(e.instrumentID) @ \(fmtDecimal(e.triggerPrice)) | \(e.conditionSnapshot.displayDescription)"
                        Pasteboard.copy(line)
                    }
                }
                if alertStillExists {
                    Button("跳到对应预警") {
                        selectedTab = .list
                        selectedAlertIDs = [e.alertID]
                        alertInstrumentFilter = ""
                    }
                }
                Button(isExpanded ? "收起详情" : "展开详情") {
                    expandedHistoryID = isExpanded ? nil : e.id
                }
                Divider()
                Button("删除此条历史", role: .destructive) {
                    historyEntries.removeAll { $0.id == e.id }
                }
            }
            if isExpanded {
                historyExpandedDetail(e)
            }
        }
    }

    /// v15.20 batch77 · 复制单条历史的时间戳（IM 同步触发时刻）
    private func copyHistoryTimestamp(_ e: AlertHistoryEntry) {
        Pasteboard.copy(Self.timeFormatter.string(from: e.triggeredAt))
    }

    /// v15.20 batch62 · 历史 row 展开详情面板（trader 复盘触发时刻完整信息）
    @ViewBuilder
    private func historyExpandedDetail(_ e: AlertHistoryEntry) -> some View {
        let relativeAge = Self.relativeAgeFormatter.localizedString(for: e.triggeredAt, relativeTo: Date())
        let alertStillExists = alerts.contains { $0.id == e.alertID }
        let currentAlertStatus = alerts.first { $0.id == e.alertID }?.status
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 24) {
                detailColumn("触发时间", value: Self.timeFormatter.string(from: e.triggeredAt) + " (\(relativeAge))")
                detailColumn("触发价格", value: fmtDecimal(e.triggerPrice), bold: true, color: .red.opacity(0.85))
                detailColumn("合约", value: e.instrumentID)
                Spacer()
            }
            HStack(alignment: .top, spacing: 24) {
                detailColumn("完整条件", value: e.conditionSnapshot.displayDescription)
                detailColumn("预警当前状态", value: currentAlertStatus.map(statusLabel) ?? "已删除", color: alertStillExists ? .primary : .orange)
                Spacer()
            }
            if !e.message.isEmpty {
                Text("说明：\(e.message)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button("复制详情") { copyHistoryDetail(e) }
                    .buttonStyle(.borderless)
                    .tooltip("把完整触发信息复制到剪贴板（IM/邮件分享）")
                if alertStillExists {
                    Button("跳到预警列表") {
                        selectedTab = .list
                        selectedAlertIDs = [e.alertID]
                        alertInstrumentFilter = ""
                    }
                    .buttonStyle(.borderless)
                    .tooltip("切到预警 Tab · 选中并清除合约筛选以确保可见")
                }
                Spacer()
                Button("收起") { expandedHistoryID = nil }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.07))
    }

    private func detailColumn(_ label: String, value: String, bold: Bool = false, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .fontWeight(bold ? .semibold : .regular)
                .foregroundColor(color)
        }
    }

    private func statusLabel(_ s: AlertStatus) -> String {
        switch s {
        case .active:    return L("活跃")
        case .triggered: return L("已触发（冷却中）")
        case .paused:    return L("已暂停")
        case .cancelled: return L("已取消")
        }
    }

    private func copyHistoryDetail(_ e: AlertHistoryEntry) {
        let lines: [String] = [
            "🔔 \(e.alertName)",
            "时间：\(Self.timeFormatter.string(from: e.triggeredAt))",
            "合约：\(e.instrumentID)",
            "价格：\(fmtDecimal(e.triggerPrice))",
            "条件：\(e.conditionSnapshot.displayDescription)",
            "说明：\(e.message)"
        ]
        Pasteboard.copy(lines.joined(separator: "\n"))
    }

    private static let relativeAgeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateTimeStyle = .named
        return f
    }()

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

/// 10 类可编辑 condition（horizontalLineTouched 需 drawingID 选择 · 留 v2）
/// v15.19+ batch16 · 加 priceBreakoutHigh / priceBreakoutLow（Donchian 突破）
/// v15.57 · 加 spreadDeviation · sheet 不开放手动创建（picker hide · 由 ⌘⌥W + 按钮入口）
private enum ConditionKind: String, CaseIterable, Identifiable {
    case priceAbove          = "价格 >"
    case priceBelow          = "价格 <"
    case priceCrossAbove     = "上穿"
    case priceCrossBelow     = "下穿"
    case priceBreakoutHigh   = "突破前 N 根高"
    case priceBreakoutLow    = "跌破前 N 根低"
    case volumeSpike         = "成交量异常"
    case openInterestSpike   = "持仓量异常"
    case priceMoveSpike      = "价格急动"
    case indicator           = "指标条件"
    case spreadDeviation     = "价差偏离"
    var id: String { rawValue }

    /// sheet picker 仅露 9 类用户可编辑（spreadDeviation 由 ⌘⌥W 一键加预警入口创建）
    static var sheetEditableCases: [ConditionKind] {
        Self.allCases.filter { $0 != .spreadDeviation }
    }

    static func of(_ c: AlertCondition) -> ConditionKind {
        switch c {
        case .priceAbove:            return .priceAbove
        case .priceBelow:            return .priceBelow
        case .priceCrossAbove:       return .priceCrossAbove
        case .priceCrossBelow:       return .priceCrossBelow
        case .priceBreakoutHigh:     return .priceBreakoutHigh
        case .priceBreakoutLow:      return .priceBreakoutLow
        case .horizontalLineTouched: return .priceAbove   // v2 加 horizontalLine kind 时改
        case .volumeSpike:           return .volumeSpike
        case .openInterestSpike:     return .openInterestSpike
        case .priceMoveSpike:        return .priceMoveSpike
        case .indicator:             return .indicator
        case .spreadDeviation:       return .spreadDeviation
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
    // v15.19+ batch16 · Donchian 突破字段
    var breakoutPeriod: KLinePeriod = .minute15
    var breakoutLookback: Int = 20

    // 指标条件预警字段（v15.x · 仅 conditionKind == .indicator 用到）
    var indicatorKind: IndicatorKind = .ma
    var indicatorParam0: Double = 20    // MA period / EMA period / MACD fast / RSI period
    var indicatorParam1: Double = 26    // MACD slow（其他指标忽略）
    var indicatorParam2: Double = 9     // MACD signal（其他指标忽略）
    var indicatorPeriod: KLinePeriod = .minute5
    var indicatorEventTag: IndicatorEventTag = .priceCrossAbove
    var indicatorRSIThreshold: Double = 70

    var channels: Set<NotificationChannelKind> = [.inApp, .systemNotice]

    /// v15.21 batch90 · defaultCooldownSeconds 用于新建 alert 时初始 cooldown · trader Settings 持久化
    init(from alert: Alert? = nil, defaultCooldownSeconds: Int = 60) {
        guard let a = alert else {
            cooldownSeconds = defaultCooldownSeconds
            return
        }
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
        case .priceBreakoutHigh(let p, let n), .priceBreakoutLow(let p, let n):
            breakoutPeriod = p
            breakoutLookback = n
        case .spreadDeviation:
            // v15.57 · placeholder · sheet 不允许编辑 · 用户应从 ⌘⌥W 入口创建
            // loadConditionParams 仅在 edit 既有 alert 时调 · 此处保持默认值不读 spread params
            break
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
        case .priceBreakoutHigh:
            return .priceBreakoutHigh(period: breakoutPeriod, lookback: max(1, breakoutLookback))
        case .priceBreakoutLow:
            return .priceBreakoutLow(period: breakoutPeriod, lookback: max(1, breakoutLookback))
        case .spreadDeviation:
            // v15.57 · sheet 不开放手动创建 · 兜底返 priceAbove(0) 不会被实际使用
            return .priceAbove(0)
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
    let defaultCooldownSeconds: Int
    let onSave: (Alert) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AlertFormDraft
    /// v15.21 batch90 · 持久化默认 cooldown · 仅新建预警时"设为默认"按钮可写
    @AppStorage("viewState.v1.alert.defaultCooldownSeconds") private var storedDefaultCooldown: Int = 60

    init(editing: Alert?, defaultCooldownSeconds: Int = 60, onSave: @escaping (Alert) -> Void) {
        self.editing = editing
        self.defaultCooldownSeconds = defaultCooldownSeconds
        self.onSave = onSave
        self._draft = State(initialValue: AlertFormDraft(from: editing, defaultCooldownSeconds: defaultCooldownSeconds))
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
                        ForEach(ConditionKind.sheetEditableCases) { k in
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
                        // v15.21 batch90 · 仅新建预警时显示"设为默认"按钮 · 写 @AppStorage 持久化
                        if editing == nil {
                            Button("设为默认") {
                                storedDefaultCooldown = max(0, draft.cooldownSeconds)
                            }
                            .buttonStyle(.borderless)
                            .tooltip("把当前冷却秒数保存为新预警默认值（持久化 · 重启保留）")
                            .disabled(draft.cooldownSeconds == storedDefaultCooldown)
                        }
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
        case .priceBreakoutHigh, .priceBreakoutLow:
            // v15.19+ batch16 · Donchian 通道突破（trader 顺势启动经典）· period 选周期 + lookback 回看根数
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("周期")
                    Picker("", selection: $draft.breakoutPeriod) {
                        ForEach(KLinePeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    Text("回看")
                    TextField("", value: $draft.breakoutLookback, format: .number)
                        .frame(width: 60)
                    Text("根（不含本根）")
                }
                Text("close > 前 N 根 high · trader Donchian 通道突破信号")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .indicator:
            indicatorParams
        case .spreadDeviation:
            // v15.57 · spread 由 ⌘⌥W 一键加预警入口创建 · sheet 不展示参数表单
            EmptyView()
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
        case .active:    return L("活跃")
        case .triggered: return L("已触发")
        case .paused:    return L("暂停")
        case .cancelled: return L("已取消")
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
        case .inApp:        return L("内")
        case .systemNotice: return L("通")
        case .sound:        return L("声")
        case .console:      return L("控")
        case .file:         return L("文")
        }
    }

    /// 完整中文名（Form Toggle 标题用）
    var displayLabel: String {
        switch self {
        case .inApp:        return L("App 内浮窗")
        case .systemNotice: return L("系统通知中心")
        case .sound:        return L("声音")
        case .console:      return L("控制台日志")
        case .file:         return L("文件日志")
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
        case .priceBreakoutHigh(let p, let n):  return "突破 \(p.displayName) 前 \(n) 根高"
        case .priceBreakoutLow(let p, let n):   return "跌破 \(p.displayName) 前 \(n) 根低"
        case .indicator(let spec):              return spec.displayDescription
        case .spreadDeviation(let id, let cal, let z):
            // v15.63 · 价差对名（反查 SpreadPresets / CalendarSpreadPresets 拿真名）
            let displayName = AlertCondition.spreadDisplayName(id: id, isCalendar: cal)
            let kindLabel = cal ? "跨期" : "跨品种"
            return "[\(kindLabel)] \(displayName) · |z| ≥ \(fmtDecimal(z))"
        }
    }

    /// v15.63 · spreadID 反查显示名（"rb-hc" → "螺纹热卷"）· 不命中 fallback ID
    static func spreadDisplayName(id: String, isCalendar: Bool) -> String {
        if isCalendar {
            return CalendarSpreadPresets.byID[id]?.name ?? id
        }
        return SpreadPresets.byID[id]?.name ?? id
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
/// v15.21 batch128 · WatchlistWindow / ChartScene → AlertWindow filter 到指定合约（跨窗口工作流闭环）
extension Notification.Name {
    public static let alertAddedFromChart = Notification.Name("alertAddedFromChart")
    public static let alertWindowFilterToInstrument = Notification.Name("alertWindowFilterToInstrument")
    /// v15.21 batch131 · ChartScene → WatchlistWindow 加合约到默认/当前 group（跨窗口工作流闭环）
    public static let watchlistAddInstrument = Notification.Name("watchlistAddInstrument")
}

#endif
