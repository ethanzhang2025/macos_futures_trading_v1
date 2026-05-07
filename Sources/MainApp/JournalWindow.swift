// MainApp · 交易日志面板（WP-53 UI · commit 4/4 · 标签搜索 + 月度统计 · WP-53 收官）
//
// commit 1 已交付：⌘J 双 Tab + Mock 13 trades + 5 journals
// commit 2 已交付：CSV 导入面板（NSOpenPanel + DealCSVParser + 格式 Picker + 错误展示）
// commit 3 已交付：日志编辑器 + JournalGenerator 自动生成 + contextMenu + confirmationDialog
// commit 4 本次新增：
// - 搜索框（toolbar · 空格分隔多 query · AND 匹配 title/reason/lesson/tags · localizedCaseInsensitiveContains）
// - 视图模式 Picker（列表 / 月度统计 · segmented · toolbar 内）
// - 月度统计视图：按 createdAt 月份聚合卡片（篇数 / 情绪分布 5 类彩点 / 偏差分布 8 类 / top5 热门标签）
// - aggregateMonthly + MonthlyAggregate fileprivate struct（filter + 聚合）
// - 搜索作用于列表和月度（filteredJournals computed · 上游统一过滤 · viewMode 仅切换渲染）
//
// 留待 v2：季度视图 / 倒排索引搜索 / 标签自动补全（v1 用 contains 已够）
// 留待 M5：StoreManager 注入 SQLiteJournalStore（已就绪 · trades + journals CRUD）替换 Mock

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import JournalCore
import Shared
import StoreCore

// MARK: - Tab 切换

private enum JournalTab: String, CaseIterable, Identifiable {
    case trades   = "成交记录"
    case journals = "交易日志"
    var id: String { rawValue }
}

// MARK: - 日志视图模式（commit 4/4）

private enum JournalViewMode: String, CaseIterable, Identifiable {
    case list    = "列表"
    case monthly = "月度"
    var id: String { rawValue }
}

// MARK: - 成交记录排序（v15.23 batch174）

private enum TradeSortKey: String, CaseIterable, Identifiable {
    case timeDesc   = "时间 ↓"
    case timeAsc    = "时间 ↑"
    case priceDesc  = "成交价 ↓"
    case volumeDesc = "数量 ↓"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeDesc, .timeAsc: return "clock"
        case .priceDesc:          return "yensign.circle"
        case .volumeDesc:         return "number"
        }
    }
}

// MARK: - 日志排序（v15.23 batch164 · 与 TrainingHistory sortKey 对齐）

private enum JournalSortKey: String, CaseIterable, Identifiable {
    case updatedDesc    = "更新 ↓"
    case createdDesc    = "创建 ↓"
    case titleAsc       = "标题 A→Z"
    case emotionGroup   = "按情绪"
    case deviationGroup = "按偏差"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .updatedDesc:    return "clock.arrow.circlepath"
        case .createdDesc:    return "calendar"
        case .titleAsc:       return "textformat.abc"
        case .emotionGroup:   return "face.smiling"
        case .deviationGroup: return "exclamationmark.triangle"
        }
    }
}

// MARK: - 月度聚合（commit 4/4）

private struct MonthlyAggregate: Identifiable {
    let month: String                          // "2026-04"
    let count: Int
    let emotionCounts: [JournalEmotion: Int]
    let deviationCounts: [JournalDeviation: Int]
    let topTags: [String]                      // 出现次数 top 5

    var id: String { month }
}

// MARK: - 日志 Sheet 状态（commit 3/4）

private enum JournalSheetState: Identifiable {
    case createJournal
    case editJournal(TradeJournal)
    case generatorPreview([TradeJournal])

    var id: String {
        switch self {
        case .createJournal:           return "create"
        case .editJournal(let j):      return "edit-\(j.id)"
        case .generatorPreview:        return "gen-preview"
        }
    }
}

// MARK: - CSV 导入解析结果

private enum ImportParseOutcome {
    /// 文件级 OK · trades 是成功转换的 · rowErrors 是 toTrade 失败的行级错误描述
    case success(trades: [Trade], rowErrors: [String])
    /// 文件级解析失败（编码 / 表头缺列 / 不支持格式）
    case fileError(DealCSVError)

    var addCount: Int {
        if case .success(let trades, _) = self { return trades.count }
        return 0
    }
}

// MARK: - 主窗口

struct JournalWindow: View {

    @State private var trades: [Trade] = []
    @State private var journals: [TradeJournal] = []
    @State private var selectedTab: JournalTab = .trades

    // CSV 导入状态（commit 2/4）
    @State private var importURL: URL?
    @State private var importFormat: DealCSVFormat = .wenhua
    @State private var importOutcome: ImportParseOutcome?

    // 日志编辑 + 自动生成状态（commit 3/4）
    @State private var journalSheetState: JournalSheetState?
    @State private var pendingDeleteJournal: TradeJournal?
    @State private var selectedJournalIDs: Set<TradeJournal.ID> = []

    // 搜索 + 视图模式（commit 4/4）
    @State private var searchText: String = ""
    @State private var journalViewMode: JournalViewMode = .list

    // v15.23 batch164 · 排序（与 TrainingHistory sortKey 对齐 · @AppStorage 持久化）
    @AppStorage("viewState.v1.journal.sortKey") private var sortKeyRaw: String = JournalSortKey.updatedDesc.rawValue
    private var sortKey: JournalSortKey { JournalSortKey(rawValue: sortKeyRaw) ?? .updatedDesc }

    // v15.23 batch165 · 情绪 filter（nil = 全部 · 与 TrainingHistory pattern filter 对齐）
    @State private var filterEmotion: JournalEmotion? = nil

    // v15.23 batch166 · 偏差 filter（nil = 全部）
    @State private var filterDeviation: JournalDeviation? = nil

    // v15.23 batch167 · 帮助面板（⌘⇧? · 4 大新窗口 UX 一致）
    @State private var showHelpSheet: Bool = false

    // v15.23 batch170 · 月度卡片点击跳 list + 月份 filter（"yyyy-MM" 格式 · nil 不限）
    @State private var filterMonth: String? = nil

    // v15.23 batch171 · trades 表合约 filter（nil = 全部 · 自动列举现有 instrumentIDs）
    @State private var filterTradeInstrument: String? = nil

    // v15.23 batch174 · trades 表排序（@AppStorage 持久化）
    @AppStorage("viewState.v1.journal.tradeSortKey") private var tradeSortKeyRaw: String = TradeSortKey.timeDesc.rawValue
    private var tradeSortKey: TradeSortKey { TradeSortKey(rawValue: tradeSortKeyRaw) ?? .timeDesc }

    // v15.23 batch175 · trade ID filter（点击 trade 行查看关联日志 · 仅显示 tradeIDs.contains 的 journals）
    @State private var filterTradeID: UUID? = nil

    // v15.23 batch175 · trades 表选中（用于行级 contextMenu）
    @State private var selectedTradeIDs: Set<Trade.ID> = []

    // v15.23 batch177 · trades 表搜索（合约 / 方向 / 开平 / 来源 · 多 query AND）
    @State private var tradeSearchText: String = ""

    /// M5 持久化：load 完成前 isLoaded=false · 期间 mutation 不触发 save（避免 onChange 把 Mock 写覆盖真数据）
    @State private var isLoaded: Bool = false

    @Environment(\.storeManager) private var storeManager
    @Environment(\.analytics) private var analytics

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 880, idealWidth: 1100, minHeight: 520, idealHeight: 720)
        .task {
            // M5 持久化：load 真实 trades + journals · 失败 / 空库 fallback Mock · 加载完成后允许 onChange 自动 save
            if let store = storeManager?.journal {
                let loadedTrades = (try? await store.loadAllTrades()) ?? []
                let loadedJournals = (try? await store.loadAllJournals()) ?? []
                if !loadedTrades.isEmpty || !loadedJournals.isEmpty {
                    trades = loadedTrades
                    journals = loadedJournals
                    isLoaded = true
                    return
                }
            }
            // fallback Mock（首启 / store 不可用 / 库空时）
            if trades.isEmpty {
                let mock = MockJournalData.generate()
                trades = mock.trades
                journals = mock.journals
            }
            isLoaded = true
        }
        .onChange(of: trades) { newValue in
            // M5 自动持久化：trades UPSERT 全量批量（saveTrades 内 INSERT OR REPLACE · 重复 id 更新）
            // 删除点（如果有）需在 mutation 处显式调 store.deleteTrade(id:) · onChange 不能 DELETE
            // 空数组合法（用户清空意图）· saveTrades([]) 内是 no-op · 与 alerts 持久化语义对齐
            guard isLoaded, let store = storeManager?.journal else { return }
            Task { try? await store.saveTrades(newValue) }
        }
        .onChange(of: journals) { newValue in
            // M5 自动持久化：journals 逐个 saveJournal（INSERT OR REPLACE · 协议无批量 saveJournals）
            // 删除已通过 deleteJournal(_:) 内显式 store.deleteJournal(id:) 处理（line 584）
            guard isLoaded, let store = storeManager?.journal else { return }
            Task {
                for j in newValue {
                    try? await store.saveJournal(j)
                }
            }
        }
        .sheet(isPresented: importSheetBinding) {
            if let url = importURL, let outcome = importOutcome {
                ImportSheet(
                    fileName: url.lastPathComponent,
                    format: $importFormat,
                    outcome: outcome,
                    onFormatChange: { _ in parseImport() },
                    onCancel: cancelImport,
                    onConfirm: confirmImport
                )
            }
        }
        .sheet(item: $journalSheetState) { state in
            switch state {
            case .createJournal:
                JournalEditorSheet(editing: nil, trades: trades, existingTagsByFrequency: tagsByFrequency) { saveJournal($0) }
            case .editJournal(let journal):
                JournalEditorSheet(editing: journal, trades: trades, existingTagsByFrequency: tagsByFrequency) { updateJournal($0) }
            case .generatorPreview(let drafts):
                GeneratorPreviewSheet(drafts: drafts) { batchAddJournals($0) }
            }
        }
        .confirmationDialog(
            "删除日志？",
            isPresented: deleteJournalConfirmBinding,
            titleVisibility: .visible,
            presenting: pendingDeleteJournal
        ) { journal in
            Button("删除「\(journal.title)」", role: .destructive) {
                deleteJournal(journal)
            }
            Button("取消", role: .cancel) {
                pendingDeleteJournal = nil
            }
        } message: { journal in
            Text("日志将永久移除（关联的 \(journal.tradeIDs.count) 笔成交不受影响 · A09 单向引用）。")
        }
        .sheet(isPresented: $showHelpSheet) { helpSheet }
        .background(
            Group {
                Button("") { selectedTab = .trades }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("") { selectedTab = .journals }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("") { showHelpSheet = true }
                    .keyboardShortcut("?", modifiers: [.command, .shift])
                // v15.23 batch168 · ⌘⇧C 复制选中日志的 markdown（避开 ⌘C 与 Table 默认复制冲突）
                Button("") {
                    if selectedTab == .journals,
                       journalViewMode == .list,
                       selectedJournalIDs.count == 1,
                       let id = selectedJournalIDs.first,
                       let j = journals.first(where: { $0.id == id }) {
                        copySingleJournalMarkdown(j)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .opacity(0)
        )
    }

    private var importSheetBinding: Binding<Bool> {
        Binding(
            get: { importURL != nil },
            set: { if !$0 { cancelImport() } }
        )
    }

    private var deleteJournalConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteJournal != nil },
            set: { if !$0 { pendingDeleteJournal = nil } }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 24) {
            Text("📔 交易日志").font(.title2).bold()
            Divider().frame(height: 24)
            stat("总成交", "\(trades.count) 笔")
            stat("总日志", "\(journals.count) 篇")
            // v15.23 batch172 · 今日 / 本周 chip（trader 一眼看节奏）
            todayWeekChips
            Spacer()
            Button {
                presentImportPanel()
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help("导入交割单 CSV（⌘⇧M · 文华 / 通用格式）")

            // v15.18 · 导出 CSV 菜单（闭合持仓 / Trade 流水二选一）
            Menu {
                Button("闭合持仓 CSV（PositionMatcher 配对结果）") {
                    presentExportPanel(kind: .closedPosition)
                }
                Button("Trade 流水 CSV（原始成交记录）") {
                    presentExportPanel(kind: .tradeFlow)
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            .disabled(trades.isEmpty)
            .help("导出 CSV · 含 BOM · Excel 中文友好")

            Text("commit 4/4 · WP-53 收官")
                .font(.caption2)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.18))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 14, design: .monospaced))
        }
    }

    /// v15.23 batch172 · 今日 + 本周 chip（trader 看节奏 · trades 按 timestamp · journals 按 updatedAt）
    @ViewBuilder
    private var todayWeekChips: some View {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let weekStart = cal.date(byAdding: .day, value: -7, to: now) ?? now

        let tradesToday = trades.filter { cal.isDateInToday($0.timestamp) }.count
        let journalsToday = journals.filter { cal.isDateInToday($0.updatedAt) }.count
        let tradesWeek = trades.filter { $0.timestamp >= weekStart }.count
        let journalsWeek = journals.filter { $0.updatedAt >= weekStart }.count

        HStack(spacing: 6) {
            chipPill("☀ 今日", "\(tradesToday) 成 / \(journalsToday) 日", color: .orange,
                     active: tradesToday > 0 || journalsToday > 0)
            chipPill("📅 本周", "\(tradesWeek) 成 / \(journalsWeek) 日", color: .blue,
                     active: tradesWeek > 0 || journalsWeek > 0)
        }
    }

    private func chipPill(_ leading: String, _ trailing: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(leading).font(.caption2).bold()
            Text(trailing).font(.caption2).monospacedDigit()
        }
        .foregroundColor(active ? color : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((active ? color : .gray).opacity(active ? 0.15 : 0.08))
        .clipShape(Capsule())
        .help("\(leading) · 成交 / 日志（成交按 timestamp · 日志按 updatedAt · 本周近 7 天）")
    }

    // MARK: - Tab 栏

    /// v15.23 batch167 · tab 数 badge + ⌘1/⌘2 视觉提示（与训练 ⌘1/⌘2/⌘3 对齐）
    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(JournalTab.allCases) { t in
                let count = t == .trades ? trades.count : journals.count
                Text("\(t.rawValue) \(count)").tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .labelsHidden()
        .help("⌘1 成交记录 · ⌘2 交易日志 · ⌘⇧? 帮助")
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .trades:   tradesContent
        case .journals: journalsContent
        }
    }

    // MARK: - 成交记录 Tab 容器（v15.23 batch171 · toolbar + Table）

    @ViewBuilder
    private var tradesContent: some View {
        VStack(spacing: 0) {
            tradesToolbar
            Divider()
            tradesTable
        }
    }

    /// v15.23 batch171 · 合约 filter Menu · 自动从 trades 列举唯一 instrumentIDs
    /// v15.23 batch177 · 加搜索框
    private var tradesToolbar: some View {
        HStack(spacing: 12) {
            // v15.23 batch177 · 搜索框（合约/方向/开平/来源 · 空格 AND）
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 合约 / 方向 / 开平 / 来源（空格 AND）", text: $tradeSearchText)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 280)

            let instruments = Array(Set(trades.map { $0.instrumentID })).sorted()

            Menu {
                Button("\(filterTradeInstrument == nil ? "✓ " : "")全部合约") { filterTradeInstrument = nil }
                if !instruments.isEmpty { Divider() }
                ForEach(instruments, id: \.self) { id in
                    let isOn = filterTradeInstrument == id
                    let n = trades.filter { $0.instrumentID == id }.count
                    Button("\(isOn ? "✓ " : "")\(id) · \(n)") { filterTradeInstrument = id }
                }
            } label: {
                Label(filterTradeInstrument ?? "全部合约（\(instruments.count) 种）", systemImage: "doc.text.magnifyingglass")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 180)
            .help("合约筛选（自动从导入的成交列举）")
            .disabled(trades.isEmpty)

            // v15.23 batch174 · 排序 Menu（4 档 · 持久化）
            Menu {
                ForEach(TradeSortKey.allCases) { k in
                    let isOn = tradeSortKey == k
                    Button("\(isOn ? "✓ " : "")\(k.rawValue)") { tradeSortKeyRaw = k.rawValue }
                }
            } label: {
                Label(tradeSortKey.rawValue, systemImage: tradeSortKey.icon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 120)
            .help("成交排序方式（4 档 · 持久化）")
            .disabled(trades.isEmpty)

            Spacer()

            Text("\(filteredTrades.count) / \(trades.count) 笔")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// v15.23 batch171/174/177 · 应用合约 filter + 搜索 + 排序
    private var filteredTrades: [Trade] {
        var base: [Trade] = trades
        if let id = filterTradeInstrument {
            base = base.filter { $0.instrumentID == id }
        }
        // v15.23 batch177 · 搜索：合约 / 方向 / 开平 / 来源 · 空格分隔多 query · AND
        let queries = tradeSearchText.split(whereSeparator: \.isWhitespace).map(String.init)
        if !queries.isEmpty {
            base = base.filter { t in
                let haystack = "\(t.instrumentID) \(t.direction.displayName) \(t.offsetFlag.displayName) \(sourceLabel(t.source))"
                return queries.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
            }
        }
        switch tradeSortKey {
        case .timeDesc:   return base.sorted { $0.timestamp > $1.timestamp }
        case .timeAsc:    return base.sorted { $0.timestamp < $1.timestamp }
        case .priceDesc:  return base.sorted { $0.price > $1.price }
        case .volumeDesc: return base.sorted { $0.volume > $1.volume }
        }
    }

    // MARK: - 交易日志 Tab 容器（toolbar + Table）

    @ViewBuilder
    private var journalsContent: some View {
        VStack(spacing: 0) {
            journalsToolbar
            Divider()
            switch journalViewMode {
            case .list:    journalsTable
            case .monthly: monthlyView
            }
        }
    }

    private var journalsToolbar: some View {
        HStack(spacing: 12) {
            Button {
                journalSheetState = .createJournal
            } label: {
                Label("新建日志", systemImage: "plus.bubble")
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            .help("新建日志（⌘⇧J）")

            Button {
                presentAutoGenerate()
            } label: {
                Label("自动生成", systemImage: "wand.and.stars")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .help("从成交记录自动生成日志草稿（⌘⇧A · 按合约 + 8h 时间窗口聚合）")
            .disabled(trades.isEmpty)

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 标题 / 原因 / 教训 / 标签（空格 AND）", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(width: 280)

            // v15.23 batch165 · 情绪 filter Menu（5 类 + 全部 · 应用到 list 和 monthly 双模式）
            Menu {
                Button("\(filterEmotion == nil ? "✓ " : "")全部") { filterEmotion = nil }
                Divider()
                ForEach(JournalEmotion.allCases, id: \.self) { e in
                    let isOn = filterEmotion == e
                    Button("\(isOn ? "✓ " : "")\(e.displayName)") { filterEmotion = e }
                }
            } label: {
                Label(filterEmotion?.displayName ?? "全部情绪", systemImage: "face.smiling")
                    .foregroundColor(filterEmotion?.color ?? .secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .help("情绪筛选（5 类 · 全部）")

            // v15.23 batch166 · 偏差 filter Menu（8 类 + 全部）
            Menu {
                Button("\(filterDeviation == nil ? "✓ " : "")全部") { filterDeviation = nil }
                Divider()
                ForEach(JournalDeviation.allCases, id: \.self) { d in
                    let isOn = filterDeviation == d
                    Button("\(isOn ? "✓ " : "")\(d.displayName)") { filterDeviation = d }
                }
            } label: {
                Label(filterDeviation?.displayName ?? "全部偏差", systemImage: "exclamationmark.triangle")
                    .foregroundColor(filterDeviation == nil ? .secondary : (filterDeviation == .asPlanned ? .green : .orange))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .help("偏差筛选（8 类 · 全部）")

            Spacer()

            // v15.23 batch169 · 月报导出 Menu（复制到剪贴板 / 保存为 .md · filter 应用到导出）
            Menu {
                Button("复制到剪贴板") { exportMonthlyReport(toFile: false) }
                Button("保存为 .md 文件…") { exportMonthlyReport(toFile: true) }
            } label: {
                Label("导出月报", systemImage: "doc.text")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 100)
            .help("月报 4 段 markdown · 当前 filter 自动应用")
            .disabled(journals.isEmpty)

            // v15.23 batch164 · 排序 Menu（5 档 · 仅列表模式有意义 · 月度模式按月份排序固定）
            Menu {
                ForEach(JournalSortKey.allCases) { k in
                    let isOn = sortKey == k
                    Button("\(isOn ? "✓ " : "")\(k.rawValue)") { sortKeyRaw = k.rawValue }
                }
            } label: {
                Label(sortKey.rawValue, systemImage: sortKey.icon)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 110)
            .help("排序方式（5 档 · 持久化）")
            .disabled(journalViewMode != .list)

            Picker("视图", selection: $journalViewMode) {
                ForEach(JournalViewMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .labelsHidden()

            if !selectedJournalIDs.isEmpty && journalViewMode == .list {
                Text("已选 \(selectedJournalIDs.count) 篇")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // v15.23 batch175 · trade filter chip（点击 X 清除 · 高亮关联日志来自 trades 跳转）
            if let tid = filterTradeID, let trade = trades.first(where: { $0.id == tid }) {
                HStack(spacing: 4) {
                    Image(systemName: "link.circle.fill")
                        .font(.caption2)
                    Text("关联：\(trade.instrumentID) \(trade.direction.displayName)\(trade.offsetFlag.displayName)")
                        .font(.caption2)
                    Button {
                        filterTradeID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.15))
                .clipShape(Capsule())
                .help("仅显示关联此成交的日志 · ✕ 清除")
            }

            // v15.23 batch170 · 月份 filter chip（点击 X 清除）
            if let m = filterMonth {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.caption2)
                    Text(m)
                        .font(.caption2)
                        .monospacedDigit()
                    Button {
                        filterMonth = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
                .help("月份过滤 · 点 ✕ 清除")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 成交记录 Tab

    private var tradesTable: some View {
        Table(filteredTrades, selection: $selectedTradeIDs) {
            TableColumn("合约") { t in
                Text(t.instrumentID).fontWeight(.medium)
            }
            .width(min: 70, ideal: 80)

            TableColumn("方向") { t in
                Text(t.direction.displayName)
                    .foregroundColor(t.direction == .buy ? .red : .green)
            }
            .width(min: 50, ideal: 60)

            TableColumn("开/平") { t in
                Text(t.offsetFlag.displayName)
            }
            .width(min: 60, ideal: 70)

            TableColumn("成交价") { t in
                Text(formatDecimal(t.price, fractionDigits: 1))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 90)

            TableColumn("数量") { t in
                Text("\(t.volume)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 60)

            TableColumn("手续费") { t in
                Text(formatDecimal(t.commission, fractionDigits: 2))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 80)

            TableColumn("时间") { t in
                Text(Self.timestampFormatter.string(from: t.timestamp))
                    .foregroundColor(.secondary)
            }
            .width(min: 130, ideal: 150)

            TableColumn("来源") { t in
                Text(sourceLabel(t.source))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            }
            .width(min: 60, ideal: 70)
        }
        .font(.system(.body, design: .monospaced))
        // v15.23 batch175 · 单选成交时右键查看关联日志
        .contextMenu(forSelectionType: Trade.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let trade = trades.first(where: { $0.id == id }) {
                let count = journals.filter { $0.tradeIDs.contains(id) }.count
                Button("查看关联日志（\(count) 篇）") {
                    showRelatedJournals(for: trade)
                }
                .disabled(count == 0)
            }
        }
    }

    /// v15.23 batch175 · 切到 journals tab + 设 trade filter（高亮关联日志）
    private func showRelatedJournals(for trade: Trade) {
        filterTradeID = trade.id
        // 清掉其他 filter 避免空集
        filterMonth = nil
        filterEmotion = nil
        filterDeviation = nil
        searchText = ""
        journalViewMode = .list
        selectedTab = .journals
        let count = journals.filter { $0.tradeIDs.contains(trade.id) }.count
        Toast.info("已切到关联日志", "\(trade.instrumentID) · \(count) 篇")
    }

    // MARK: - 交易日志 Tab

    private var journalsTable: some View {
        Table(filteredJournals, selection: $selectedJournalIDs) {
            TableColumn("标题") { j in
                Text(j.title).fontWeight(.medium)
            }
            .width(min: 220, ideal: 280)

            TableColumn("成交") { j in
                Text("\(j.tradeIDs.count) 笔")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 70)

            TableColumn("情绪") { j in
                Text(j.emotion.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(j.emotion.color.opacity(0.18))
                    .foregroundColor(j.emotion.color)
                    .clipShape(Capsule())
            }
            .width(min: 70, ideal: 80)

            TableColumn("偏差") { j in
                Text(j.deviation.displayName)
                    .font(.caption)
                    .foregroundColor(j.deviation == .asPlanned ? .green : .orange)
            }
            .width(min: 80, ideal: 100)

            TableColumn("标签") { j in
                Text(j.tags.sorted().joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("更新时间") { j in
                Text(Self.timestampFormatter.string(from: j.updatedAt))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 130, ideal: 150)
        }
        .contextMenu(forSelectionType: TradeJournal.ID.self) { ids in
            if ids.count == 1,
               let id = ids.first,
               let journal = journals.first(where: { $0.id == id }) {
                Button("编辑") {
                    journalSheetState = .editJournal(journal)
                }
                // v15.23 batch168 · 复制单篇 markdown 到剪贴板（trader 一键发微信群 / 笔记）
                Button("复制单篇分析（Markdown）") {
                    copySingleJournalMarkdown(journal)
                }
                Divider()
                Button("删除", role: .destructive) {
                    pendingDeleteJournal = journal
                }
            }
        }
    }

    /// v15.23 batch168 · 复制单篇 markdown 到剪贴板（NSPasteboard）
    private func copySingleJournalMarkdown(_ journal: TradeJournal) {
        let md = JournalMarkdownReport.generateSingle(journal, trades: trades)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        Toast.info("已复制单篇分析", "\(journal.title) · \(md.count) 字")
    }

    /// v15.23 batch169 · 月报 markdown 导出（剪贴板 / 文件二选一 · 应用 emotion + deviation + month filter）
    private func exportMonthlyReport(toFile: Bool) {
        let label = filterLabel
        let md = JournalMarkdownReport.generate(
            journals,
            filterEmotion: filterEmotion,
            filterDeviation: filterDeviation,
            filterMonth: filterMonth,
            filterLabel: label
        )
        if toFile {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "交易日志月报-\(Self.fileStampFormatter.string(from: Date())).md"
            panel.title = "保存月报"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
                Toast.info("月报已保存", url.lastPathComponent)
            } catch {
                Toast.error("保存失败", error.localizedDescription)
            }
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(md, forType: .string)
            let suffix = label.map { "（\($0)）" } ?? ""
            Toast.info("月报已复制\(suffix)", "\(md.count) 字 · \(filteredJournals.count) 篇")
        }
    }

    /// v15.23 batch173 · 历史标签按频率降序（编辑 sheet 自动补全建议来源）
    private var tagsByFrequency: [String] {
        var counts: [String: Int] = [:]
        for j in journals {
            for t in j.tags { counts[t, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// v15.23 batch169/170 · filterLabel：基于 emotion / deviation / month filter 拼接（nil 时不加标题后缀）
    private var filterLabel: String? {
        var parts: [String] = []
        if let m = filterMonth { parts.append(m) }
        if let e = filterEmotion { parts.append(e.displayName) }
        if let d = filterDeviation { parts.append(d.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - 月度视图（commit 4/4）

    @ViewBuilder
    private var monthlyView: some View {
        let aggregates = Self.aggregateMonthly(filteredJournals)
        if aggregates.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("无可聚合的日志").font(.title3).foregroundColor(.secondary)
                Text(searchText.isEmpty ? "添加日志后这里会按月汇总" : "搜索条件下没有匹配项")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(aggregates) { agg in
                        MonthlyCard(aggregate: agg) {
                            // v15.23 batch170 · 点击月卡 → 切 list + 设 filterMonth
                            filterMonth = agg.month
                            journalViewMode = .list
                            Toast.info("已切到列表", "\(agg.month) · \(agg.count) 篇")
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    /// 过滤：空格分隔多个 query · AND 匹配（所有 query 都需命中 title / reason / lesson / tags 任一字段）
    /// 大小写不敏感 · v1 简单 contains（v2 留倒排索引）
    /// v15.23 batch164 · filter 后再 apply sortKey（5 档）
    /// v15.23 batch165 · 加情绪 filter（filterEmotion · nil 不限）
    private var filteredJournals: [TradeJournal] {
        let queries = searchText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var base: [TradeJournal] = queries.isEmpty ? journals : journals.filter { j in
            queries.allSatisfy { q in
                j.title.localizedCaseInsensitiveContains(q)
                    || j.reason.localizedCaseInsensitiveContains(q)
                    || j.lesson.localizedCaseInsensitiveContains(q)
                    || j.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }
        }
        if let e = filterEmotion {
            base = base.filter { $0.emotion == e }
        }
        if let d = filterDeviation {
            base = base.filter { $0.deviation == d }
        }
        // v15.23 batch170 · 月份 filter（"yyyy-MM"）· 基于 createdAt
        if let m = filterMonth {
            base = base.filter { Self.monthFormatter.string(from: $0.createdAt) == m }
        }
        // v15.23 batch175 · trade ID filter（仅含关联该 trade 的日志）
        if let tid = filterTradeID {
            base = base.filter { $0.tradeIDs.contains(tid) }
        }
        return Self.sortJournals(base, by: sortKey)
    }

    /// v15.23 batch164 · 排序（5 档 · group 类型用 enum allCases 顺序 · tiebreak updatedAt desc）
    fileprivate static func sortJournals(_ items: [TradeJournal], by key: JournalSortKey) -> [TradeJournal] {
        switch key {
        case .updatedDesc:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .createdDesc:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .titleAsc:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .emotionGroup:
            let order = Dictionary(uniqueKeysWithValues:
                JournalEmotion.allCases.enumerated().map { ($1, $0) })
            return items.sorted { (a, b) in
                let ai = order[a.emotion] ?? 0
                let bi = order[b.emotion] ?? 0
                if ai != bi { return ai < bi }
                return a.updatedAt > b.updatedAt
            }
        case .deviationGroup:
            let order = Dictionary(uniqueKeysWithValues:
                JournalDeviation.allCases.enumerated().map { ($1, $0) })
            return items.sorted { (a, b) in
                let ai = order[a.deviation] ?? 0
                let bi = order[b.deviation] ?? 0
                if ai != bi { return ai < bi }
                return a.updatedAt > b.updatedAt
            }
        }
    }

    /// 按 createdAt 月份（"yyyy-MM"）聚合 · Asia/Shanghai 时区
    private static func aggregateMonthly(_ journals: [TradeJournal]) -> [MonthlyAggregate] {
        guard !journals.isEmpty else { return [] }
        var byMonth: [String: [TradeJournal]] = [:]
        for j in journals {
            byMonth[Self.monthFormatter.string(from: j.createdAt), default: []].append(j)
        }
        return byMonth.map { (month, items) in
            var emotionCounts: [JournalEmotion: Int] = [:]
            var deviationCounts: [JournalDeviation: Int] = [:]
            var tagCounts: [String: Int] = [:]
            for j in items {
                emotionCounts[j.emotion, default: 0] += 1
                deviationCounts[j.deviation, default: 0] += 1
                for t in j.tags {
                    tagCounts[t, default: 0] += 1
                }
            }
            let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)
            return MonthlyAggregate(
                month: month,
                count: items.count,
                emotionCounts: emotionCounts,
                deviationCounts: deviationCounts,
                topTags: topTags
            )
        }.sorted { $0.month > $1.month }
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - v15.23 batch167 · 帮助面板（4 大新窗口 UX 一致 · ⌘⇧? 唤出）

    private static let helpGroups: [(String, [(String, String)])] = [
        ("📑 Tab 切换", [
            ("⌘1", "切到「成交记录」"),
            ("⌘2", "切到「交易日志」"),
            ("⌘⇧?", "唤出本面板"),
        ]),
        ("📊 成交记录（v15.23 batch171/174/175）", [
            ("合约 filter Menu", "全部 / 各合约（自动列举 + 各合约笔数）"),
            ("排序 Menu", "时间 ↓/↑ · 成交价 ↓ · 数量 ↓（4 档 · 持久化）"),
            ("过滤计数", "右上角显示「N / 总数 笔」"),
            ("行右键 → 查看关联日志", "切到日志 tab + 紫色 chip · ✕ 清除"),
        ]),
        ("📥 导入 / 导出 / 自动生成", [
            ("⌘⇧M", "导入交割单 CSV（文华 / 通用）"),
            ("⌘⇧J", "新建日志"),
            ("⌘⇧A", "从成交记录自动生成日志草稿"),
            ("导出 CSV Menu", "闭合持仓 / Trade 流水 二选一 · 含 BOM Excel 友好"),
            ("导出月报 Menu (v15.23 batch169)", "4 段 markdown：概览 / 情绪 / 偏差 / 标签 top10 / 最近 30 · 应用当前 filter"),
        ]),
        ("🔍 搜索 / 筛选 / 排序（v15.23 batch164-166）", [
            ("搜索", "标题 / 原因 / 教训 / 标签 · 空格 AND · 大小写不敏感"),
            ("情绪 filter", "5 类（自信 / 犹豫 / 恐惧 / 贪婪 / 平静）+ 全部"),
            ("偏差 filter", "8 类（按计划 / 破止损 / 抢反弹 / 追高 ...）+ 全部"),
            ("排序", "更新 ↓ / 创建 ↓ / 标题 A→Z / 按情绪 / 按偏差（持久化）"),
        ]),
        ("📅 视图模式", [
            ("列表", "Table 显示日志条目（默认）"),
            ("月度", "按 createdAt 月份聚合 · 情绪/偏差/标签 top5"),
            ("月卡点击 (v15.23 batch170)", "点击月份卡片 → 跳列表 + 设月份过滤（chip 显示 · ✕ 清除）"),
        ]),
        ("✏️ 列表操作", [
            ("contextMenu", "编辑 / 复制单篇分析 / 删除"),
            ("⌘⇧C", "复制选中单篇 markdown 到剪贴板（v15.23 batch168）"),
        ]),
        ("📝 编辑 Sheet（v15.23 batch173/176）", [
            ("常用标签 chip", "点击追加历史 top 10 高频标签（自动空格分隔）"),
            ("⌘S / Return", "保存（标题非空才生效 · IDE 习惯 batch176）"),
            ("Esc", "取消"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 交易日志全功能").font(.title2).bold()
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("⌘1/⌘2 切 tab · ⌘⇧M 导入 · ⌘⇧J 新建 · ⌘⇧A 自动生成 · 搜索/情绪/偏差 filter + 5 档排序 + 月度聚合 · ⌘⇧? 帮助")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - CSV 导入流程（commit 2/4）

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择交割单 CSV 文件"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importURL = url
        importFormat = .wenhua
        parseImport()
    }

    /// v15.18 · 导出 CSV（闭合持仓 / Trade 流水二选一）
    private enum ExportKind {
        case closedPosition
        case tradeFlow
    }

    private func presentExportPanel(kind: ExportKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = "导出"
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)

        let data: Data
        switch kind {
        case .closedPosition:
            let (closed, _) = PositionMatcher.match(trades: trades)
            guard !closed.isEmpty else {
                let alert = NSAlert()
                alert.messageText = "无可导出闭合持仓"
                alert.informativeText = "当前 trades 全部为开仓 / 未配对 · 至少需有一对开+平才能生成"
                alert.runModal()
                return
            }
            panel.title = "导出闭合持仓 CSV"
            panel.nameFieldStringValue = "闭合持仓-\(dateStr).csv"
            data = ClosedPositionCSVExporter.exportData(closed)
        case .tradeFlow:
            panel.title = "导出 Trade 流水 CSV"
            panel.nameFieldStringValue = "trade流水-\(dateStr).csv"
            data = TradeCSVExporter.exportData(trades)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
        }
    }

    private func parseImport() {
        guard let url = importURL else { return }
        importOutcome = Self.parseCSV(url: url, format: importFormat)
    }

    private func cancelImport() {
        importURL = nil
        importOutcome = nil
    }

    private func confirmImport() {
        if case .success(let newTrades, _) = importOutcome {
            trades = (trades + newTrades).sorted { $0.timestamp > $1.timestamp }
            selectedTab = .trades
            // 埋点：CSV 导入是 Stage A 唯一新增 trade 入口（trades 数组的真实 mutation 信号）
            if let service = analytics {
                Task {
                    _ = try? await service.record(
                        .journalEntrySave,
                        userID: FuturesTerminalApp.anonymousUserID,
                        properties: ["import_count": "\(newTrades.count)"]
                    )
                }
            }
        }
        cancelImport()
    }

    /// 文件级 + 行级解析 · 文件级失败抛 fileError · 行级失败累积到 rowErrors（不中止）
    private static func parseCSV(url: URL, format: DealCSVFormat) -> ImportParseOutcome {
        do {
            let csvString = try String(contentsOf: url, encoding: .utf8)
            let raws = try DealCSVParser.parse(csvString, format: format)
            var trades: [Trade] = []
            var rowErrors: [String] = []
            for raw in raws {
                do {
                    trades.append(try raw.toTrade())
                } catch let e as DealCSVError {
                    rowErrors.append("第 \(raw.lineNumber) 行：\(e.description)")
                } catch {
                    rowErrors.append("第 \(raw.lineNumber) 行：未知错误")
                }
            }
            return .success(trades: trades, rowErrors: rowErrors)
        } catch let e as DealCSVError {
            return .fileError(e)
        } catch {
            return .fileError(.invalidEncoding)
        }
    }

    // MARK: - 日志 Mutations（commit 3/4）

    private func saveJournal(_ journal: TradeJournal) {
        journals.insert(journal, at: 0)
    }

    private func updateJournal(_ journal: TradeJournal) {
        if let idx = journals.firstIndex(where: { $0.id == journal.id }) {
            journals[idx] = journal
        }
    }

    private func deleteJournal(_ journal: TradeJournal) {
        journals.removeAll { $0.id == journal.id }
        selectedJournalIDs.remove(journal.id)
        pendingDeleteJournal = nil
        // M5 持久化：显式 deleteJournal · onChange 只能 UPSERT 不能 DELETE · 必须在删除点单独触发
        if isLoaded, let store = storeManager?.journal {
            Task { try? await store.deleteJournal(id: journal.id) }
        }
    }

    private func presentAutoGenerate() {
        let drafts = JournalGenerator.generateDrafts(from: trades)
        guard !drafts.isEmpty else { return }
        journalSheetState = .generatorPreview(drafts)
    }

    private func batchAddJournals(_ batch: [TradeJournal]) {
        journals = (batch + journals).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - 标签格式化

    private func sourceLabel(_ s: TradeSource) -> String {
        switch s {
        case .wenhua:  return "文华"
        case .generic: return "通用"
        case .manual:  return "手填"
        }
    }

    private func formatDecimal(_ d: Decimal, fractionDigits: Int) -> String {
        let nf = fractionDigits == 1 ? Self.priceFormatter : Self.feeFormatter
        return nf.string(from: d as NSDecimalNumber) ?? "\(d)"
    }

    private static let priceFormatter: NumberFormatter = makeDecimalFormatter(fractionDigits: 1)
    private static let feeFormatter: NumberFormatter = makeDecimalFormatter(fractionDigits: 2)

    private static func makeDecimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = fractionDigits
        nf.maximumFractionDigits = fractionDigits
        return nf
    }

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - JournalEmotion / JournalDeviation 显示扩展（commit 3/4 · sheet 共享）

fileprivate extension JournalEmotion {
    var displayName: String {
        switch self {
        case .confident: return "自信"
        case .hesitant:  return "犹豫"
        case .fearful:   return "恐惧"
        case .greedy:    return "贪婪"
        case .calm:      return "平静"
        }
    }

    var color: Color {
        switch self {
        case .confident: return .green
        case .hesitant:  return .orange
        case .fearful:   return .red
        case .greedy:    return .purple
        case .calm:      return .blue
        }
    }
}

fileprivate extension JournalDeviation {
    var displayName: String {
        switch self {
        case .asPlanned:     return "按计划"
        case .breakStopLoss: return "破止损"
        case .chaseRebound:  return "抢反弹"
        case .chaseHigh:     return "追高"
        case .catchFalling:  return "抄底"
        case .earlyExit:     return "过早离场"
        case .overTrade:     return "超额交易"
        case .other:         return "其他"
        }
    }
}

// MARK: - ImportSheet（commit 2/4）

private struct ImportSheet: View {

    let fileName: String
    @Binding var format: DealCSVFormat
    let outcome: ImportParseOutcome
    let onFormatChange: (DealCSVFormat) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入交割单").font(.title2).bold()

            Form {
                Section("文件") {
                    Text(fileName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Section("CSV 格式") {
                    Picker("格式", selection: $format) {
                        Text("文华财经").tag(DealCSVFormat.wenhua)
                        Text("通用 CSV").tag(DealCSVFormat.generic)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: format) { newFormat in
                        onFormatChange(newFormat)
                    }
                }

                Section("解析结果") {
                    outcomeView
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("添加 \(outcome.addCount) 笔") { onConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(outcome.addCount == 0)
            }
        }
        .padding(20)
        .frame(width: 580, height: 540)
    }

    @ViewBuilder
    private var outcomeView: some View {
        switch outcome {
        case .success(let trades, let rowErrors): successView(trades: trades, rowErrors: rowErrors)
        case .fileError(let error):               fileErrorView(error)
        }
    }

    private func successView(trades: [Trade], rowErrors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("解析到 \(trades.count) 笔成交", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)

            if !rowErrors.isEmpty {
                Label("\(rowErrors.count) 行解析失败 · 已跳过", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                rowErrorsList(rowErrors)
            }

            if !trades.isEmpty {
                Divider()
                Text("预览前 5 笔：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                previewList(trades.prefix(5))
            }
        }
    }

    private func fileErrorView(_ error: DealCSVError) -> some View {
        Label("解析失败：\(error.description)", systemImage: "xmark.octagon.fill")
            .foregroundColor(.red)
            .padding(.vertical, 8)
    }

    private func rowErrorsList(_ errors: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(errors.prefix(10), id: \.self) { msg in
                    Text("· \(msg)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if errors.count > 10 {
                    Text("... 余 \(errors.count - 10) 项").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxHeight: 80)
    }

    private func previewList(_ trades: ArraySlice<Trade>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(trades), id: \.id) { trade in
                HStack(spacing: 8) {
                    Text(trade.instrumentID)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                    Text(trade.direction.displayName)
                        .font(.caption)
                        .foregroundColor(trade.direction == .buy ? .red : .green)
                        .frame(width: 24)
                    Text(trade.offsetFlag.displayName)
                        .font(.caption)
                        .frame(width: 40)
                    Text("\(trade.volume) @ \(trade.price.description)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - JournalEditorSheet（commit 3/4 · add / edit 共用）

private struct JournalEditorSheet: View {

    let editing: TradeJournal?
    let trades: [Trade]
    let onSave: (TradeJournal) -> Void
    /// 关联成交 → EmotionAutoTagger 建议标签（PositionMatcher 配对一次 · sheet 生命期内复用）
    private let tagsByTradeID: [UUID: [EmotionAutoTagger.Tag]]
    /// v15.23 batch173 · 历史标签（按频率降序 · 用于自动补全建议）
    private let suggestedHistoryTags: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: JournalDraft
    @State private var tradesExpanded: Bool

    init(editing: TradeJournal?,
         trades: [Trade],
         existingTagsByFrequency: [String] = [],
         onSave: @escaping (TradeJournal) -> Void) {
        self.editing = editing
        self.trades = trades
        self.onSave = onSave
        self._draft = State(initialValue: JournalDraft(from: editing))
        self._tradesExpanded = State(initialValue: editing?.tradeIDs.isEmpty == false)
        self.suggestedHistoryTags = existingTagsByFrequency
        // 预算一次 · 后续 body 重渲只查 dict
        let (closed, _) = PositionMatcher.match(trades: trades)
        var map: [UUID: [EmotionAutoTagger.Tag]] = [:]
        for (pos, tags) in EmotionAutoTagger.tagAll(closed) where !tags.isEmpty {
            map[pos.openTradeID] = tags
            map[pos.closeTradeID] = tags
        }
        self.tagsByTradeID = map
    }

    /// v15.23 batch173 · 已输入的标签（避免在 suggestion 重复显示）
    private var currentDraftTags: Set<String> {
        Set(draft.tagsString.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// v15.23 batch173 · 显示 top 10 中尚未输入的历史标签
    private var availableHistoryTags: [String] {
        let drafted = currentDraftTags
        return suggestedHistoryTags.filter { !drafted.contains($0) }.prefix(10).map { $0 }
    }

    /// v15.23 batch173 · 点击建议把它追加到 tagsString（自动补空格分隔）
    private func appendTag(_ tag: String) {
        let trimmed = draft.tagsString.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.tagsString = trimmed.isEmpty ? tag : "\(trimmed) \(tag)"
    }

    /// 当前选中 tradeIDs 对应建议标签（按枚举顺序稳定 · O(N) 单遍）
    private var suggestedTags: [EmotionAutoTagger.Tag] {
        var seen = Set<EmotionAutoTagger.Tag>()
        for tid in draft.tradeIDs {
            for tag in tagsByTradeID[tid] ?? [] {
                seen.insert(tag)
            }
        }
        return EmotionAutoTagger.Tag.allCases.filter { seen.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "新建日志" : "编辑日志")
                .font(.title2)
                .bold()

            Form {
                Section("基本") {
                    TextField("标题（必填）", text: $draft.title)
                        .textFieldStyle(.roundedBorder)
                }

                Section("交易理由 / 决策依据") {
                    TextEditor(text: $draft.reason)
                        .frame(minHeight: 60)
                        .font(.body)
                }

                Section("情绪 + 偏差") {
                    Picker("情绪", selection: $draft.emotion) {
                        ForEach(JournalEmotion.allCases, id: \.self) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                    Picker("偏差", selection: $draft.deviation) {
                        ForEach(JournalDeviation.allCases, id: \.self) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                }

                // 自动建议（基于关联成交的 streak / avgWin/avgLoss / 持仓时长 → 6 类心理风险标签）
                if !suggestedTags.isEmpty {
                    Section("🤖 自动建议（基于关联成交的心理风险分析）") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    Text(tag.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.18))
                                        .cornerRadius(4)
                                }
                                Spacer()
                                Button("一键采纳") { draft.adopt(suggestedTags) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                            Text("采纳后 → 标签合并 + 情绪自动设为：\(suggestedTags[0].suggestedEmotion.displayName)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("教训 / 复盘结论") {
                    TextEditor(text: $draft.lesson)
                        .frame(minHeight: 60)
                        .font(.body)
                }

                Section("标签（用空格分隔）") {
                    TextField("如：日内 趋势跟随 RB", text: $draft.tagsString)
                        .textFieldStyle(.roundedBorder)
                    // v15.23 batch173 · 标签自动补全（基于历史 journals.tags · top10 频率降序）
                    if !availableHistoryTags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("常用标签（点击追加）")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(availableHistoryTags, id: \.self) { tag in
                                        Button {
                                            appendTag(tag)
                                        } label: {
                                            Text(tag)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.accentColor.opacity(0.15))
                                                .foregroundColor(.accentColor)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .help("追加 \(tag) 到当前标签")
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Section("关联成交（已选 \(draft.tradeIDs.count) 笔 / 共 \(trades.count) 可选）") {
                    DisclosureGroup("展开 / 收起", isExpanded: $tradesExpanded) {
                        ForEach(trades, id: \.id) { trade in
                            Toggle(isOn: bindingForTrade(trade.id)) {
                                tradeRow(trade)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "保存" : "更新") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidForSave)
            }
        }
        .padding(20)
        .frame(width: 620, height: 720)
        // v15.23 batch176 · ⌘S 保存（IDE 习惯）· 标题为空时按键无效
        .background(
            Button("") {
                if isValidForSave { saveAndDismiss() }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .opacity(0)
        )
    }

    private var isValidForSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAndDismiss() {
        onSave(draft.toJournal(existing: editing))
        dismiss()
    }

    private func bindingForTrade(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.tradeIDs.contains(id) },
            set: { isOn in
                if isOn { draft.tradeIDs.insert(id) } else { draft.tradeIDs.remove(id) }
            }
        )
    }

    private func tradeRow(_ trade: Trade) -> some View {
        HStack(spacing: 8) {
            Text(trade.instrumentID)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 72, alignment: .leading)
            Text(trade.direction.displayName)
                .font(.caption)
                .foregroundColor(trade.direction == .buy ? .red : .green)
                .frame(width: 24)
            Text(trade.offsetFlag.displayName)
                .font(.caption)
                .frame(width: 40)
            Text("\(trade.volume)手 @ \(trade.price.description)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(JournalWindow.timestampFormatter.string(from: trade.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

private struct JournalDraft {
    var title: String
    var reason: String
    var emotion: JournalEmotion
    var deviation: JournalDeviation
    var lesson: String
    var tagsString: String
    var tradeIDs: Set<UUID>

    /// 一键采纳建议（合并标签 + 用首个建议覆盖 emotion · 不存在则不动）
    mutating func adopt(_ tags: [EmotionAutoTagger.Tag]) {
        guard !tags.isEmpty else { return }
        let existing = Set(tagsString.split(whereSeparator: \.isWhitespace).map(String.init))
        let merged = existing.union(tags.map(\.displayName))
        tagsString = merged.sorted().joined(separator: " ")
        // 首个建议决定 emotion · 后续建议忽略（用户可手动改 picker）
        emotion = tags[0].suggestedEmotion
    }

    init(from editing: TradeJournal?) {
        if let j = editing {
            self.title = j.title
            self.reason = j.reason
            self.emotion = j.emotion
            self.deviation = j.deviation
            self.lesson = j.lesson
            self.tagsString = j.tags.sorted().joined(separator: " ")
            self.tradeIDs = Set(j.tradeIDs)
        } else {
            self.title = ""
            self.reason = ""
            self.emotion = .calm
            self.deviation = .asPlanned
            self.lesson = ""
            self.tagsString = ""
            self.tradeIDs = []
        }
    }

    func toJournal(existing: TradeJournal?) -> TradeJournal {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = Set(tagsString.split(whereSeparator: \.isWhitespace).map(String.init))
        let now = Date()
        if let j = existing {
            return TradeJournal(
                id: j.id,
                tradeIDs: Array(tradeIDs),
                title: trimmedTitle,
                reason: reason,
                emotion: emotion,
                deviation: deviation,
                lesson: lesson,
                tags: tags,
                createdAt: j.createdAt,
                updatedAt: now
            )
        }
        return TradeJournal(
            tradeIDs: Array(tradeIDs),
            title: trimmedTitle,
            reason: reason,
            emotion: emotion,
            deviation: deviation,
            lesson: lesson,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - GeneratorPreviewSheet（commit 3/4 · 自动生成草稿预览 + batch 添加）

private struct GeneratorPreviewSheet: View {

    let drafts: [TradeJournal]
    let onConfirm: ([TradeJournal]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDraftIDs: Set<TradeJournal.ID>

    init(drafts: [TradeJournal], onConfirm: @escaping ([TradeJournal]) -> Void) {
        self.drafts = drafts
        self.onConfirm = onConfirm
        self._selectedDraftIDs = State(initialValue: Set(drafts.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("自动生成日志草稿")
                    .font(.title2)
                    .bold()
                Spacer()
                Text("共 \(drafts.count) 篇 · 已选 \(selectedDraftIDs.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("全选") { selectedDraftIDs = Set(drafts.map(\.id)) }
                Button("反选") {
                    selectedDraftIDs = Set(drafts.map(\.id)).subtracting(selectedDraftIDs)
                }
                Spacer()
                Text("聚合规则：同合约 + 8h 时间窗口")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(drafts, id: \.id) { draft in
                        Toggle(isOn: bindingForDraft(draft.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.title)
                                    .font(.system(.body, design: .monospaced))
                                Text("\(draft.tradeIDs.count) 笔 · \(draft.reason.prefix(60))…")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加 \(selectedDraftIDs.count) 篇") {
                    let chosen = drafts.filter { selectedDraftIDs.contains($0.id) }
                    onConfirm(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDraftIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580, height: 540)
    }

    private func bindingForDraft(_ id: TradeJournal.ID) -> Binding<Bool> {
        Binding(
            get: { selectedDraftIDs.contains(id) },
            set: { isOn in
                if isOn { selectedDraftIDs.insert(id) } else { selectedDraftIDs.remove(id) }
            }
        )
    }
}

// MARK: - MonthlyCard（commit 4/4 · 月度聚合卡片）

private struct MonthlyCard: View {

    let aggregate: MonthlyAggregate
    /// v15.23 batch170 · 点击卡片跳 list + 设 month filter（nil 时无交互）
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(aggregate.month)
                    .font(.title3)
                    .bold()
                Text("· \(aggregate.count) 篇")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if onTap != nil {
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                        .help("点击跳转到列表 · 仅显示本月日志")
                }
            }

            HStack(alignment: .top, spacing: 24) {
                distributionColumn(
                    title: "情绪分布",
                    cases: JournalEmotion.allCases,
                    counts: aggregate.emotionCounts
                ) { emotion in
                    HStack(spacing: 6) {
                        Circle().fill(emotion.color).frame(width: 6, height: 6)
                        Text(emotion.displayName).font(.caption)
                    }
                }

                distributionColumn(
                    title: "偏差分布",
                    cases: JournalDeviation.allCases,
                    counts: aggregate.deviationCounts
                ) { deviation in
                    Text(deviation.displayName)
                        .font(.caption)
                        .foregroundColor(deviation == .asPlanned ? .green : .orange)
                }
            }

            if !aggregate.topTags.isEmpty {
                Text("热门标签：\(aggregate.topTags.joined(separator: " · "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    /// 单列分布（情绪 / 偏差共用）· 仅渲染 count > 0 的 case
    @ViewBuilder
    private func distributionColumn<Case: Hashable>(
        title: String,
        cases: [Case],
        counts: [Case: Int],
        @ViewBuilder label: @escaping (Case) -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            ForEach(cases, id: \.self) { c in
                if let n = counts[c], n > 0 {
                    HStack(spacing: 6) {
                        label(c)
                        Text("\(n)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mock 数据（commit 1 静态 · commit 2 CSV 导入接管 · M5 替换为 SQLiteJournalStore）

private enum MockJournalData {

    static func generate() -> (trades: [Trade], journals: [TradeJournal]) {
        let now = Date()
        let trades = generateTrades(anchor: now)
        let journals = generateJournals(now: now, trades: trades)
        return (trades, journals)
    }

    private struct Spec {
        let symbol: String
        let dir: Direction
        let off: OffsetFlag
        let price: String
        let vol: Int
        let fee: String
        let minutes: Int
        let source: TradeSource
        let ref: String
    }

    private static func generateTrades(anchor: Date) -> [Trade] {
        let specs: [Spec] = [
            // RB2510 日内 7 笔（最新 → 最旧）
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3251",   vol: 2, fee: "1.50",  minutes: -30,    source: .wenhua,  ref: "WH26042807"),
            Spec(symbol: "RB2510", dir: .sell, off: .close,          price: "3255",   vol: 4, fee: "1.50",  minutes: -55,    source: .wenhua,  ref: "WH26042806"),
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3248",   vol: 4, fee: "1.50",  minutes: -80,    source: .wenhua,  ref: "WH26042805"),
            Spec(symbol: "RB2510", dir: .buy,  off: .closeYesterday, price: "3243",   vol: 3, fee: "1.50",  minutes: -105,   source: .wenhua,  ref: "WH26042804"),
            Spec(symbol: "RB2510", dir: .sell, off: .open,           price: "3250",   vol: 3, fee: "1.50",  minutes: -130,   source: .wenhua,  ref: "WH26042803"),
            Spec(symbol: "RB2510", dir: .sell, off: .close,          price: "3252",   vol: 5, fee: "1.50",  minutes: -155,   source: .wenhua,  ref: "WH26042802"),
            Spec(symbol: "RB2510", dir: .buy,  off: .open,           price: "3245",   vol: 5, fee: "1.50",  minutes: -180,   source: .wenhua,  ref: "WH26042801"),
            // IF2509 跨日 3 笔
            Spec(symbol: "IF2509", dir: .sell, off: .open,           price: "3870.0", vol: 1, fee: "23.00", minutes: -1440,        source: .wenhua,  ref: "WH26042705"),
            Spec(symbol: "IF2509", dir: .sell, off: .close,          price: "3865.4", vol: 2, fee: "23.00", minutes: -1500,        source: .wenhua,  ref: "WH26042704"),
            Spec(symbol: "IF2509", dir: .buy,  off: .open,           price: "3852.0", vol: 2, fee: "23.00", minutes: -1560,        source: .wenhua,  ref: "WH26042703"),
            // AU2512 长线 2 笔
            Spec(symbol: "AU2512", dir: .sell, off: .close,          price: "619.0",  vol: 3, fee: "10.00", minutes: -1440 * 2,    source: .generic, ref: "GEN042602"),
            Spec(symbol: "AU2512", dir: .buy,  off: .open,           price: "612.5",  vol: 5, fee: "10.00", minutes: -1440 * 3,    source: .generic, ref: "GEN042601"),
            // CU2511 手动 1 笔
            Spec(symbol: "CU2511", dir: .buy,  off: .open,           price: "78650",  vol: 1, fee: "5.00",  minutes: -1440 - 30,   source: .manual,  ref: "MAN001")
        ]
        return specs.map { spec in
            Trade(
                tradeReference: spec.ref,
                instrumentID: spec.symbol,
                direction: spec.dir,
                offsetFlag: spec.off,
                price: Decimal(string: spec.price)!,
                volume: spec.vol,
                commission: Decimal(string: spec.fee)!,
                timestamp: anchor.addingTimeInterval(TimeInterval(spec.minutes * 60)),
                source: spec.source
            )
        }
    }

    private static func generateJournals(now: Date, trades: [Trade]) -> [TradeJournal] {
        let rbIDs = trades.filter { $0.instrumentID == "RB2510" }.map(\.id)
        let ifIDs = trades.filter { $0.instrumentID == "IF2509" }.map(\.id)
        let auIDs = trades.filter { $0.instrumentID == "AU2512" }.map(\.id)
        let cuIDs = trades.filter { $0.instrumentID == "CU2511" }.map(\.id)
        let allIDs = rbIDs + ifIDs + auIDs + cuIDs

        return [
            TradeJournal(
                tradeIDs: rbIDs,
                title: "RB0 日内三段操作 · 跟随 5min MA20 顺势",
                reason: "5min MA20 上行 · 价格回调到 MA20 上方建多单 · 上涨突破前高加仓",
                emotion: .confident,
                deviation: .asPlanned,
                lesson: "止损位放在 5min MA60 下方 · 跟住趋势没追高",
                tags: ["日内", "趋势跟随", "RB"],
                createdAt: now.addingTimeInterval(-60 * 60 * 2),
                updatedAt: now.addingTimeInterval(-60 * 60 * 1)
            ),
            TradeJournal(
                tradeIDs: ifIDs,
                title: "IF2509 日间持仓 · 周线 KDJ 顶背离试空",
                reason: "周线 KDJ 顶背离 · 试空头 · 准备放到下周",
                emotion: .hesitant,
                deviation: .earlyExit,
                lesson: "提前止盈错过后续 50 点跌幅 · 信号确认不应过早离场",
                tags: ["日间", "KDJ", "IF"],
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-86400)
            ),
            TradeJournal(
                tradeIDs: auIDs,
                title: "AU 长线 · 二次加仓追高",
                reason: "金价突破 615 + 美元指数走弱 · 加仓",
                emotion: .greedy,
                deviation: .chaseHigh,
                lesson: "追高位置太高 · 总盈亏好但加仓段亏 · 控制加仓节奏",
                tags: ["长线", "追高", "AU"],
                createdAt: now.addingTimeInterval(-86400 * 3),
                updatedAt: now.addingTimeInterval(-86400 * 2)
            ),
            TradeJournal(
                tradeIDs: cuIDs,
                title: "CU 手动录入 · 仓位试错",
                reason: "突破 78600 整数关 · 试多 1 手验证",
                emotion: .calm,
                deviation: .asPlanned,
                lesson: "仓位 1 手风险可控 · 验证后续可加",
                tags: ["试仓", "整数关", "CU"],
                createdAt: now.addingTimeInterval(-60 * 30),
                updatedAt: now.addingTimeInterval(-60 * 30)
            ),
            TradeJournal(
                tradeIDs: allIDs,
                title: "周复盘 · 4 月第 4 周",
                reason: "4 合约 13 笔成交 · 主要在 IF 提前离场损失明显",
                emotion: .calm,
                deviation: .other,
                lesson: "下周计划：减少 IF 操作 · 专注 RB 日内 · 控制频次",
                tags: ["周复盘", "总结"],
                createdAt: now.addingTimeInterval(-86400 / 2),
                updatedAt: now.addingTimeInterval(-86400 / 2)
            )
        ]
    }
}

#endif
