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
                JournalEditorSheet(editing: nil, trades: trades) { saveJournal($0) }
            case .editJournal(let journal):
                JournalEditorSheet(editing: journal, trades: trades) { updateJournal($0) }
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
            Spacer()
            Button {
                presentImportPanel()
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .help("导入交割单 CSV（⌘⇧M · 文华 / 通用格式）")

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

    // MARK: - Tab 栏

    private var tabBar: some View {
        Picker("", selection: $selectedTab) {
            ForEach(JournalTab.allCases) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .labelsHidden()
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .trades:   tradesTable
        case .journals: journalsContent
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

            Spacer()

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 成交记录 Tab

    private var tradesTable: some View {
        Table(trades) {
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
                Divider()
                Button("删除", role: .destructive) {
                    pendingDeleteJournal = journal
                }
            }
        }
    }

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
                        MonthlyCard(aggregate: agg)
                    }
                }
                .padding(16)
            }
        }
    }

    /// 过滤：空格分隔多个 query · AND 匹配（所有 query 都需命中 title / reason / lesson / tags 任一字段）
    /// 大小写不敏感 · v1 简单 contains（v2 留倒排索引）
    private var filteredJournals: [TradeJournal] {
        let queries = searchText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !queries.isEmpty else { return journals }
        return journals.filter { j in
            queries.allSatisfy { q in
                j.title.localizedCaseInsensitiveContains(q)
                    || j.reason.localizedCaseInsensitiveContains(q)
                    || j.lesson.localizedCaseInsensitiveContains(q)
                    || j.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("⌘⇧M 导入 · ⌘⇧J 新建 · ⌘⇧A 自动生成 · 搜索 + 月度聚合 · M5 接 SQLiteJournalStore")
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
                    try? await service.record(
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
                    Text("\(trade.volume) @ \(trade.price)")
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

    @Environment(\.dismiss) private var dismiss
    @State private var draft: JournalDraft
    @State private var tradesExpanded: Bool

    init(editing: TradeJournal?, trades: [Trade], onSave: @escaping (TradeJournal) -> Void) {
        self.editing = editing
        self.trades = trades
        self.onSave = onSave
        self._draft = State(initialValue: JournalDraft(from: editing))
        self._tradesExpanded = State(initialValue: editing?.tradeIDs.isEmpty == false)
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

                Section("教训 / 复盘结论") {
                    TextEditor(text: $draft.lesson)
                        .frame(minHeight: 60)
                        .font(.body)
                }

                Section("标签（用空格分隔）") {
                    TextField("如：日内 趋势跟随 RB", text: $draft.tagsString)
                        .textFieldStyle(.roundedBorder)
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
                    onSave(draft.toJournal(existing: editing))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 720)
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
            Text("\(trade.volume)手 @ \(trade.price)")
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
