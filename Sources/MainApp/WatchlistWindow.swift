// MainApp · 自选合约面板（WP-43 UI · commit 4/4 · 主图联动 · 5 大 P1 工作流模块 UI 全部完成）
//
// commit 1 已交付：NavigationSplitView 双栏 · WatchlistBook 真模型 · Mock 3 组 9 合约
// commit 2 已交付：添加/删除/重命名 + GroupNameSheet/InstrumentIDSheet + contextMenu + confirmationDialog
// commit 3 已交付：拖拽排序（.draggable / .dropDestination · 分组重排 + 同组重排 + 跨组移动）
// commit 4 本次新增：
// - 双击合约行 → openWindow(id: "chart") + post .watchlistInstrumentSelected
// - supportedContracts 守卫：不支持的合约本地弹 .alert（不污染 ChartScene 的容错路径）
// - Notification.Name 跨窗口联动定义在文件末尾 internal extension（同 module 共享）
// - footerHint 提示语更新为"双击合约打开主图"
//
// ChartScene.swift commit 4 配套改动：body 加 .onReceive(.watchlistInstrumentSelected)
//   → 命中 supportedContracts → currentInstrumentID = id（task(id:) 自动重启 pipeline）
//
// M5 持久化已接入：StoreManager 注入 SQLiteWatchlistBookStore · .task 异步 load · .onChange 异步 save · store 不可用时 fallback Mock

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import AppKit
import UniformTypeIdentifiers
import Shared
import StoreCore
import DataCore
import AlertCore

// MARK: - Sheet 状态

private enum WatchlistSheetState: Identifiable {
    case addGroup
    case renameGroup(Watchlist)
    case addInstrument(groupID: UUID, groupName: String)

    var id: String {
        switch self {
        case .addGroup:                      return "add-group"
        case .renameGroup(let g):            return "rename-group-\(g.id)"
        case .addInstrument(let groupID, _): return "add-instrument-\(groupID)"
        }
    }
}

// MARK: - 拖拽 Hover 反馈位置
//
// instrumentSlot.beforeIndex == group.instrumentIDs.count 表示"插入末尾"（即 trailing drop zone）

private enum HoverTarget: Equatable, Hashable {
    case group(UUID)
    case instrumentSlot(groupID: UUID, beforeIndex: Int)
}

// MARK: - 主窗口

struct WatchlistWindow: View {

    @State private var book: WatchlistBook = MockWatchlistBook.generate()
    @State private var selectedGroupID: UUID?
    @State private var sheetState: WatchlistSheetState?
    @State private var pendingDeleteGroup: Watchlist?
    @State private var selectedInstruments: Set<String> = []
    @State private var hoverTarget: HoverTarget?
    @State private var unsupportedInstrumentAlert: String?

    /// M5 持久化：load 完成前 isLoaded=false · 期间 book mutation 不触发 save（避免 onChange 把 Mock 写覆盖真数据）
    @State private var isLoaded: Bool = false

    /// v12.4 真行情：合约 ID → SinaQuote 映射 · 周期 fetch 更新 · 空时 fallback MockQuote
    @State private var quotes: [String: SinaQuote] = [:]
    @State private var quoteFetchTask: Task<Void, Never>?

    /// v17.34 C5 · 合约旗标 store · UserDefaults 持久化 · didChangeNotification 跨窗口同步
    private let flagStore = InstrumentFlagStore()
    /// 旗标版本号 · UserDefaults 变化时 +1 触发 row 重渲（@State 不能直接观察 flagStore · 用 tick）
    @State private var flagsRevision: Int = 0
    /// v17.129 · 合约备注 store · UserDefaults 持久化 · didChangeNotification 跨窗口同步（与 flagStore 同模式）
    private let noteStore = InstrumentNoteStore()
    /// v17.129 · 待编辑备注的合约 · Identifiable 包装让 .sheet(item:) 兼容
    @State private var pendingNoteInstrumentID: NoteEditTarget?

    /// v17.42 C1 · 列可见性（持仓量 / 成交量 / 价差%）· 右键 📋 显示列 toggle · UserDefaults 跨窗口同步
    @State private var visibleColumns: Set<WatchlistColumn> = WatchlistColumnPreferences.load()

    /// v17.110 · 用户 K 线配色偏好（跟 ChartScene/Settings 同步 · 涨跌色 swap 用）
    @State private var candleColorMode: CandleColorMode = ChartSettingsStore.loadCandleColorMode()
    /// v17.122 · 用户字号档（跟 ChartScene/Settings 同步）
    @State private var chartFontSize: ChartFontSize = ChartSettingsStore.loadChartFontSize()

    // v17.110 · 涨跌色（跟 candleColorMode swap · 中国习惯红涨绿跌 / 国际相反）
    private var chartProfit: Color { ChartTheme.chartProfitColor(mode: candleColorMode) }
    private var chartLoss: Color { chartLossColor(mode: candleColorMode) }

    /// v15.78 · combo 异常周期 fetch · 30s 间隔（detector 是纯函数 · 不发网络请求）
    @State private var comboFetchTask: Task<Void, Never>?

    /// v12.17 文华自选导入预览（NSOpenPanel 选 .txt 解析后 · 用户确认前的 holding 状态）
    @State private var importPreview: ImportPreview?

    /// v15.20 batch55 · 自由粘贴合约 sheet 显隐（文本框 + 分组选择 + 实时解析预览）
    @State private var showQuickPasteSheet: Bool = false
    /// v15.21 batch91 · CSV 导入 sheet 预填文本（importWatchlistFromFile 把 .csv 内容塞进去 · 复用 QuickPasteSheet）
    @State private var quickPasteInitialText: String = ""
    /// v15.21 batch101 · 聚合视图合约搜索（lowercased contains · 不区分大小写 · 空字符串跳过过滤）
    @State private var aggregatedSearchText: String = ""
    @FocusState private var isAggregatedSearchFocused: Bool

    /// v15.23 batch192 · 帮助面板（⌘⇧? · 主窗口 UX 一致补完）
    @State private var showHelpSheet: Bool = false

    /// v15.20 batch59 · 排序字段（v15.20 batch60 · @AppStorage 持久化 · 重启保留）
    /// 默认 .manual 保持用户拖拽顺序 · 反序失败 fallback .manual
    @AppStorage("viewState.v1.watchlist.sortFieldRaw") private var sortFieldRaw: String = WatchlistSortField.manual.rawValue
    @AppStorage("viewState.v1.watchlist.sortAscending") private var sortAscending: Bool = false

    /// v15.20 batch61/76 · 跨分组聚合视图（trader 涨幅榜扫盘 · 不用切分组找涨幅大的）
    /// v15.20 batch76 · @AppStorage 持久化（重启保留 · trader 习惯使用聚合扫盘）
    @AppStorage("viewState.v1.watchlist.showAllAggregated") private var showAllAggregated: Bool = false

    /// v15.38 V2 · 高级过滤 preset（涨幅/跌幅/涨停/跌停/极端/活跃 · 默认全部）
    @AppStorage("viewState.v1.watchlist.filterPresetRaw") private var filterPresetRaw: String = WatchlistFilterPreset.all.rawValue
    private var filterPreset: WatchlistFilterPreset {
        WatchlistFilterPreset(rawValue: filterPresetRaw) ?? .all
    }
    private func setFilterPreset(_ preset: WatchlistFilterPreset) {
        filterPresetRaw = preset.rawValue
    }

    /// v15.38 V2 · 分组视图搜索文本（聚合视图原已有 aggregatedSearchText · 此为分组视图新增）
    @State private var groupSearchText: String = ""

    /// 解析 sortField · raw 不合法 fallback .manual（写入用 setSortField）
    private var sortField: WatchlistSortField {
        WatchlistSortField(rawValue: sortFieldRaw) ?? .manual
    }
    private func setSortField(_ field: WatchlistSortField) {
        sortFieldRaw = field.rawValue
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.storeManager) private var storeManager
    /// v17.6 · Shell 嵌入模式（接入协议 · WatchlistWindow 用 NavigationSplitView · 嵌入时按 Pane 尺寸自适应）
    @Environment(\.isHostedInShell) private var isHostedInShell

    /// v15.78 · 全市场 combo 异常映射 by instrumentID（与 SectorPresets.id "RB0" 对齐）
    /// @State 缓存避免每行重算（自选 50+ 合约时 SwiftUI 重渲性能保护）
    @State private var comboMap: [String: ComboAnomaly] = [:]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 480, idealHeight: 600)
        .animation(.easeInOut(duration: 0.22), value: book)
        .background(groupShortcuts)
        .task {
            // M5 启动加载：store 可用时尝试 load 真数据 · 失败 / 空库时保留 Mock · 加载完成后允许 onChange 自动 save
            // try? await load() 嵌套返回 WatchlistBook?? · 用 ?? nil flatten 成 WatchlistBook? 一次解构即可
            if let store = storeManager?.watchlistBook,
               let loaded = (try? await store.load()) ?? nil {
                book = loaded
            }
            isLoaded = true
            if selectedGroupID == nil {
                selectedGroupID = book.groups.first?.id
            }
            startQuoteFetch()
            // v15.78 · 加载 combo 异常映射 + 30s 周期刷新（与 quote fetch 节奏对齐）
            refreshComboMap()
            startComboFetch()
        }
        .onDisappear {
            quoteFetchTask?.cancel()
            quoteFetchTask = nil
            comboFetchTask?.cancel()
            comboFetchTask = nil
        }
        // v17.34 C5 · 跨窗口旗标同步（与 ChartTheme / SimulatedTradingStore 同模式）
        // v17.42 C1 · 列可见性也跨窗口同步（同一 UserDefaults.didChangeNotification）
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            flagsRevision += 1
            visibleColumns = WatchlistColumnPreferences.load()
            // v17.110 · 同步 K 线配色（PnL 涨跌色 swap）
            let newMode = ChartSettingsStore.loadCandleColorMode()
            if newMode != candleColorMode { candleColorMode = newMode }
            // v17.122 · 同步字号档
            let newFontSize = ChartSettingsStore.loadChartFontSize()
            if newFontSize != chartFontSize { chartFontSize = newFontSize }
        }
        .onChange(of: book) { newValue in
            // M5 自动持久化：每次 book 变化异步 save · isLoaded 守卫避免初始 Mock 误写覆盖真数据
            guard isLoaded, let store = storeManager?.watchlistBook else { return }
            Task { try? await store.save(newValue) }
        }
        .onChange(of: selectedGroupID) { _ in
            selectedInstruments.removeAll()
        }
        // v15.21 batch131 · 跨窗口加合约 · ChartScene 触发 → 加到当前选中 group（无选中则加到第一个）
        .onReceive(NotificationCenter.default.publisher(for: .watchlistAddInstrument)) { notification in
            guard let id = notification.object as? String,
                  let trimmed = id.trimmedOrNil?.uppercased() else { return }
            // 优先目标：当前选中分组 · 否则第一个分组 · 都没有时弹 sheet 让用户先建分组
            let targetGroupID: UUID? = selectedGroupID ?? book.groups.first?.id
            guard let groupID = targetGroupID,
                  let group = book.group(id: groupID) else {
                sheetState = .addGroup
                return
            }
            // 已存在则不重复
            if !group.instrumentIDs.contains(trimmed) {
                book.addInstrument(trimmed, to: groupID)
                Toast.info("已加入自选", "\(trimmed) → 「\(group.name)」")
            } else {
                Toast.info("已存在", "\(trimmed) 已在「\(group.name)」")
            }
            selectedGroupID = groupID   // 切到该 group 让 trader 看见
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .addGroup:
                GroupNameSheet(title: "添加分组", initialName: "", actionLabel: "保存") { name in
                    addGroup(name: name)
                }
            case .renameGroup(let group):
                GroupNameSheet(title: "重命名分组", initialName: group.name, actionLabel: "更新") { name in
                    renameGroup(group, to: name)
                }
            case .addInstrument(let groupID, let groupName):
                InstrumentIDSheet(groupName: groupName) { id in
                    addInstrument(id, to: groupID)
                }
            }
        }
        // v17.129 · 备注编辑 sheet（独立 binding 避免与 sheetState enum 重构）
        .sheet(item: $pendingNoteInstrumentID) { target in
            NoteEditSheet(
                instrumentID: target.id,
                initialNote: noteStore.note(for: target.id) ?? ""
            ) { newNote in
                noteStore.setNote(newNote, for: target.id)
                flagsRevision += 1   // 复用 tick 触发 row 重渲（@State 不能直接观察 noteStore）
            }
        }
        .confirmationDialog(
            "删除分组？",
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible,
            presenting: pendingDeleteGroup
        ) { group in
            Button("删除「\(group.name)」", role: .destructive) {
                deleteGroup(group)
            }
            Button("取消", role: .cancel) {
                pendingDeleteGroup = nil
            }
        } message: { group in
            Text("分组「\(group.name)」内的 \(group.instrumentIDs.count) 个合约将一并移除。该操作无法撤销。")
        }
        .alert(
            "暂不支持的合约",
            isPresented: unsupportedAlertBinding,
            presenting: unsupportedInstrumentAlert
        ) { _ in
            Button("好") { unsupportedInstrumentAlert = nil }
        } message: { id in
            Text("\(id) 暂不支持主图查看 · 当前主图仅支持 \(MarketDataPipeline.supportedContracts.joined(separator: " / "))")
        }
        // v15.23 batch192 · 帮助面板（⌘⇧? · 主窗口 UX 一致补完）
        .sheet(isPresented: $showHelpSheet) { helpSheet }
        .background(
            Button("") { showHelpSheet = true }
                .keyboardShortcut("?", modifiers: [.command, .shift])
                .opacity(0)
        )
    }

    // MARK: - v15.23 batch192 · 帮助面板（与 ReviewWindow / WorkspaceWindow / JournalWindow 模式一致）

    private static let helpGroups: [(String, [(String, String)])] = [
        ("📁 分组管理", [
            ("⌘⇧G", "添加分组"),
            ("⌘1-9", "切换 sidebar 第 N 个分组（v15.21 batch110）"),
            ("contextMenu", "重命名 / 删除分组"),
            ("拖拽排序", "同一分组内合约拖动重排"),
        ]),
        ("📥 加合约 / 导入", [
            ("⌘⇧I", "添加合约到当前分组"),
            ("⌘⇧V", "快速粘贴合约（任意分隔符 · 自动解析）"),
            ("导入 .txt / .csv", "文华格式 / 自由表格 · 双击末尾空白也可加合约（v15.21 batch88）"),
            ("跨窗口加合约", "ChartScene → 自选 通过 .watchlistAddInstrument 通知（v15.21 batch131）"),
        ]),
        ("📤 导出（v15.23 batch199）", [
            ("Header 导出 Menu", "当前分组 .txt / 全部分组合并 .txt（# 注释行分隔）"),
            ("当前分组 → 剪贴板", "复制为多行文本 · trader 一键粘到 IM / 邮件"),
            ("文件名", "自选-分组名-N个-日期.txt（文华格式兼容）"),
        ]),
        ("📊 报价 / 排序", [
            ("⌘R", "立即刷新报价（不等 5s 周期）"),
            ("排序", "manual / 涨幅 ↓ / 涨幅 ↑ / 价格 / 持仓 / 成交（持久化）"),
            ("聚合视图", "跨分组合并 · 一键扫盘涨幅榜（v15.20 batch61/76）"),
        ]),
        ("🔍 搜索 / 筛选", [
            ("⌘F", "聚焦聚合视图搜索框（v15.21 batch101 · 合约名 contains）"),
            ("Esc", "清空搜索"),
        ]),
        ("⌨️ 通用", [
            ("⌘⇧?", "唤出本帮助面板（v15.23 batch192）"),
            ("行 contextMenu", "ChartScene 主图打开 / 加预警 / 复制行 / 跨窗口联动"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 自选窗口全功能").font(.title2).bold()
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
                                        .font(.system(size: 12 + chartFontSize.sizeDelta, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 180, alignment: .leading)
                                    Text(item.1).font(.system(size: 12 + chartFontSize.sizeDelta))
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

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteGroup != nil },
            set: { if !$0 { pendingDeleteGroup = nil } }
        )
    }

    private var unsupportedAlertBinding: Binding<Bool> {
        Binding(
            get: { unsupportedInstrumentAlert != nil },
            set: { if !$0 { unsupportedInstrumentAlert = nil } }
        )
    }

    // MARK: - 左栏 · 分组列表

    /// v15.21 batch110 · ⌘1-9 切换 sidebar 第 N 个分组（trader 高频切组 · 与 ChartScene ⌘1-6 周期切独立窗口）
    private var groupShortcuts: some View {
        Group {
            ForEach(0..<9, id: \.self) { i in
                Button("") { selectGroupAtIndex(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func selectGroupAtIndex(_ index: Int) {
        guard index >= 0, index < book.groups.count else { return }
        selectedGroupID = book.groups[index].id
        showAllAggregated = false   // 切到具体分组自动退出聚合视图
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("自选分组").font(.headline)
                Spacer()
                // v15.21 batch109 · 立即刷新报价（⌘R · 与 5s 周期 task 并行 · 重要数据/会议前后强刷）
                Button {
                    refreshQuotesNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .tooltip("立即刷新报价（⌘⇧R · 不等 5s 周期）")
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button {
                    importWatchlistFromFile()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .tooltip("导入自选合约（.txt 文华格式 · .csv 自由表格）")

                // v15.23 batch199 · 导出分组合约列表（当前 / 全部 二选一）
                Menu {
                    if let groupID = selectedGroupID,
                       let group = book.group(id: groupID) {
                        Button("当前分组「\(group.name)」(\(group.instrumentIDs.count) 个)") {
                            exportGroupToFile(groupID: groupID)
                        }
                    }
                    Button("全部 \(book.groups.count) 个分组（合并）") {
                        exportAllGroupsToFile()
                    }
                    Divider()
                    Button("当前分组复制到剪贴板") {
                        copyCurrentGroupToPasteboard()
                    }
                    .disabled(selectedGroupID == nil)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 28)
                .tooltip("导出合约列表（.txt 文华兼容 · trader 备份/分享）")
                .disabled(book.groups.isEmpty)
                Button {
                    showQuickPasteSheet = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .tooltip("快速粘贴合约（⌘⇧V · 任意分隔符）")
                .keyboardShortcut("v", modifiers: [.command, .shift])
                Button {
                    sheetState = .addGroup
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .tooltip("添加分组（⌘⇧G）")
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // v15.20 batch61 · 跨分组聚合视图入口（涨幅榜扫盘）
            allAggregatedRow
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            List(selection: $selectedGroupID) {
                ForEach(Array(book.groups.enumerated()), id: \.element.id) { index, group in
                    groupRow(group, index: index)
                }
            }
            .listStyle(.sidebar)
        }
        .alert(
            "导入文华自选",
            isPresented: importPreviewBinding,
            presenting: importPreview
        ) { preview in
            Button("确认导入", role: .none) {
                applyImport(preview.parseResult)
            }
            Button("取消", role: .cancel) {
                importPreview = nil
            }
        } message: { preview in
            Text(preview.message)
        }
        .sheet(isPresented: $showQuickPasteSheet, onDismiss: { quickPasteInitialText = "" }) {
            QuickPasteSheet(
                groups: book.groups,
                defaultGroupID: selectedGroupID ?? book.groups.first?.id,
                initialText: quickPasteInitialText,
                onSubmit: applyQuickPaste
            )
        }
    }

    /// v15.20 batch55 · 把粘贴文本解析后追加到目标分组（不存在则新建）
    private func applyQuickPaste(_ text: String, _ targetGroupID: UUID?, _ newGroupName: String?) {
        let ids = QuickPasteParser.parse(text)
        guard !ids.isEmpty else { return }
        let groupID: UUID
        if let target = targetGroupID,
           book.groups.contains(where: { $0.id == target }) {
            groupID = target
        } else {
            let trimmed = newGroupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedName = trimmed.isEmpty ? "粘贴导入" : trimmed
            let newGroup = book.addGroup(name: resolvedName, now: Date())
            groupID = newGroup.id
        }
        for id in ids {
            _ = book.addInstrument(id, to: groupID, now: Date())
        }
    }

    /// v15.20 batch61 · 全部聚合视图入口 row（去重合约总数 + 高亮 active）
    private var allAggregatedRow: some View {
        let total = aggregatedInstrumentIDs.count
        let isActive = showAllAggregated
        return HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(isActive ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("全部 · 跨分组扫盘")
                    .font(.system(size: 12 + chartFontSize.sizeDelta, weight: isActive ? .semibold : .regular))
                Text("\(total) 个合约（去重）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            showAllAggregated.toggle()
            if showAllAggregated { selectedGroupID = nil }
        }
    }

    /// v15.20 batch61 · 跨所有分组的合约去重列表 · 委托 WatchlistBook.allInstrumentIDsDeduped
    private var aggregatedInstrumentIDs: [String] {
        book.allInstrumentIDsDeduped
    }

    private func groupRow(_ group: Watchlist, index: Int) -> some View {
        // v15.20 batch86 · 分组级涨跌统计（sidebar 一眼看每组状态）
        let pcts = group.instrumentIDs.compactMap { parseChangePct(changePctText(for: $0)) }
        let upCount = pcts.filter { $0 > 0 }.count
        let downCount = pcts.filter { $0 < 0 }.count
        // v17.36 C1 · 分组颜色染 folder icon（nil = 默认 accent）
        let groupColor = WatchlistColor.color(forIndex: group.colorIndex)
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(groupColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                HStack(spacing: 4) {
                    Text("\(group.instrumentIDs.count) 合约")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if !pcts.isEmpty {
                        Text("·").foregroundColor(.secondary).font(.caption2)
                        Text("↑\(upCount)").font(.caption2).foregroundColor(Self.priceColor(0.5))
                        Text("↓\(downCount)").font(.caption2).foregroundColor(Self.priceColor(-0.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(hoverTarget == .group(group.id) ? Color.accentColor.opacity(0.18) : Color.clear)
        .tag(group.id as UUID?)
        // v15.21 batch102 · 双击 sidebar groupRow → 直接重命名（trader 高频操作 · 与右键菜单互补）
        .onTapGesture(count: 2) {
            sheetState = .renameGroup(group)
        }
        .contextMenu {
            Button("重命名（双击也行）") {
                sheetState = .renameGroup(group)
            }
            // v15.21 batch104 · 复制整组合约代码 · 换行/逗号两种格式（trader IM 群发 / Excel 粘贴）
            Button("复制全部合约代码（换行）") {
                Pasteboard.copy(group.instrumentIDs.joined(separator: "\n"))
            }
            .disabled(group.instrumentIDs.isEmpty)
            Button("复制全部合约代码（逗号）") {
                Pasteboard.copy(group.instrumentIDs.joined(separator: ","))
            }
            .disabled(group.instrumentIDs.isEmpty)
            // v17.36 C1 · 分组颜色（8 预设 + 默认）· trader 视觉分类 主力/套利/股指 等
            Menu("🎨 分组颜色（当前 \(WatchlistColor.name(forIndex: group.colorIndex))）") {
                Button {
                    book.setGroupColor(id: group.id, colorIndex: nil)
                } label: {
                    HStack {
                        Image(systemName: "circle")
                        Text("默认")
                        if group.colorIndex == nil { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach(WatchlistColor.preset.indices, id: \.self) { i in
                    Button {
                        book.setGroupColor(id: group.id, colorIndex: i)
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(WatchlistColor.preset[i].color)
                            Text(WatchlistColor.preset[i].name)
                            if group.colorIndex == i { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Divider()
            Button("删除分组", role: .destructive) {
                pendingDeleteGroup = group
            }
        }
        .draggable(WatchlistGroupRef(id: group.id)) {
            dragPreview(systemImage: "folder", text: group.name)
        }
        .dropDestination(for: WatchlistGroupRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            return moveGroup(ref.id, before: index)
        } isTargeted: { isOver in
            updateHover(.group(group.id), active: isOver)
        }
        .dropDestination(for: WatchlistInstrumentRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            return moveInstrumentToGroupTail(ref, target: group.id)
        } isTargeted: { isOver in
            updateHover(.group(group.id), active: isOver)
        }
    }

    // MARK: - 右栏 · 合约表

    @ViewBuilder
    private var detail: some View {
        if showAllAggregated {
            aggregatedInstrumentList
        } else if let groupID = selectedGroupID, let group = book.group(id: groupID) {
            instrumentList(for: group)
        } else {
            emptyState(
                icon: "list.bullet.rectangle",
                title: "未选择分组",
                hint: "在左侧选择一个自选分组以查看合约"
            )
        }
    }

    /// v15.20 batch61 · 聚合视图 detail（跨分组扫盘 · 复用 sortableHeader + 排序状态 · 拖拽与添加禁用）
    /// v15.21 batch101 · 加搜索框（按合约 ID 模糊筛选 · ⌘F 聚焦）· 大量合约时快速定位
    private var aggregatedInstrumentList: some View {
        let allIDs = aggregatedInstrumentIDs
        // v15.38 V2 · filter preset（涨跌停/极端/活跃）+ 关键词联合过滤
        let filteredIDs = WatchlistFilter.filter(
            ids: allIDs,
            preset: filterPreset,
            keyword: aggregatedSearchText,
            changePctForID: currentChangePct,
            volumeForID: currentVolume
        )
        let sortedIDs = WatchlistSorter.sort(
            ids: filteredIDs,
            field: sortField,
            ascending: sortAscending,
            keyForID: keyForInstrument
        )
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chart.bar.fill").foregroundColor(.accentColor)
                Text("全部 · 跨分组扫盘")
                    .font(.title3).fontWeight(.semibold)
                Text("· \(sortedIDs.count)/\(allIDs.count) 合约")
                    .font(.caption).foregroundColor(.secondary)
                // v15.21 batch101 · 搜索框（⌘F 聚焦 · Esc 清空）
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("搜索合约（⌘F）", text: $aggregatedSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .focused($isAggregatedSearchFocused)
                    if !aggregatedSearchText.isEmpty {
                        Button { aggregatedSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.escape, modifiers: [])
                        .tooltip("清空搜索（Esc）")
                    }
                }
                Button("") { isAggregatedSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                // v15.38 V2 · 高级过滤 menu（涨幅/跌幅/涨停/跌停/极端/活跃 6 preset）
                filterPresetMenu
                Spacer()
                // v15.20 batch68 · 涨幅/跌幅前 N 一键批量预警（聚合扫盘 + AlertPreset 联动）
                Menu {
                    Button("涨幅前 5 → 涨停预警")  { batchAlertTopMovers(topN: 5,  ascending: false, preset: .limitUp) }
                    Button("涨幅前 10 → 涨停预警") { batchAlertTopMovers(topN: 10, ascending: false, preset: .limitUp) }
                    Divider()
                    Button("跌幅前 5 → 跌停预警")  { batchAlertTopMovers(topN: 5,  ascending: true,  preset: .limitDown) }
                    Button("跌幅前 10 → 跌停预警") { batchAlertTopMovers(topN: 10, ascending: true,  preset: .limitDown) }
                } label: {
                    Label("批量预警", systemImage: "bell.badge")
                }
                .tooltip("按涨跌幅排序后取前 N · 一键创建涨/跌停预警 · 默认 paused 防触发风暴")
                Button("退出聚合视图") { showAllAggregated = false }
                    .buttonStyle(.borderless)
                    .tooltip("回到分组视图")
            }
            .padding(16)

            Divider()
            // v15.38 V2 · 视图统计 HUD（涨跌家数 + 平均涨幅 + 涨停跌停 + 极值合约）
            statsHUD(for: sortedIDs)
            Divider()
            instrumentColumnsHeader
            Divider()

            if sortedIDs.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "尚无任何分组",
                    hint: "在左侧创建分组并添加合约"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedIDs, id: \.self) { id in
                            // 聚合视图不接受拖拽 · groupID 传 nil sentinel · instrumentRow 守卫不会调 reorder
                            aggregatedInstrumentRow(id: id)
                            Divider()
                        }
                    }
                }
            }
            Divider()
            footerHint
        }
    }

    /// v15.20 batch61 · 聚合视图 row（与 instrumentRow 同列宽 · 双击切主图 · 不带 reorder handle）
    private func aggregatedInstrumentRow(id: String) -> some View {
        let change = changePctText(for: id)
        let pctValue = parseChangePct(change)
        return HStack(spacing: 0) {
            Spacer().frame(width: 24)
            Text(id)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            Text(priceText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Self.priceColor(pctValue))
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 16)
            Text(change)
                .font(.system(.body, design: .monospaced))
                .fontWeight(abs(pctValue ?? 0) >= 2 ? .bold : .regular)
                .foregroundColor(Self.priceColor(pctValue))
                .frame(width: 80, alignment: .trailing)
                .tooltip(detailedChangeText(for: id))   // v15.21 batch133 · hover 显示绝对涨跌 + 振幅
            // v17.42 C1 · 可选列（与 instrumentRow 同款 · 跨视图统一）
            extraColumnsCells(for: id)
            Spacer().frame(width: 12)
            // v15.78 · combo 徽章（聚合视图同款 · 跨视图统一）
            comboWatchlistBadge(for: id)
                .frame(width: 56, alignment: .center)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openInstrumentInChart(id)
        }
        .contextMenu {
            Button("打开主图") { openInstrumentInChart(id) }
            // v15.21 batch128 · 跨窗口联动 · 看本合约预警（与单组 row 一致）
            Button("查看本合约预警") {
                NotificationCenter.default.post(name: .alertWindowFilterToInstrument, object: id)
                openWindow(id: "alert")
            }
            // v15.21 batch97 · 复制合约代码 / 最新价（与单组 row 一致）
            Button("复制合约代码 \(id)") { Pasteboard.copy(id) }
            Button("复制最新价 \(priceText(for: id))") { Pasteboard.copy(priceText(for: id)) }
            // v15.21 batch115 · 复制行所有信息（与单组 row 一致）
            Button("复制行所有信息") {
                let line = "\(id)  \(priceText(for: id))  \(changePctText(for: id))  持仓\(openInterestText(for: id))"
                Pasteboard.copy(line)
            }
            Divider()
            Menu("📋 创建预警模板") {
                ForEach(AlertPreset.allCases) { preset in
                    Button(preset.displayName) {
                        createAlertPreset(preset, instrumentID: id)
                    }
                }
            }
            // v17.42 C1 · 列自定义（与 instrumentRow 同款 · 跨视图统一）
            columnVisibilityMenu()
        }
    }

    private func instrumentList(for group: Watchlist) -> some View {
        let displayedIDs = sortedInstrumentIDs(for: group)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("· \(displayedIDs.count)/\(group.instrumentIDs.count) 合约")
                    .font(.caption)
                    .foregroundColor(.secondary)
                // v15.38 V2 · 分组视图搜索框（⌘F 同 aggregated 路径）
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("搜索", text: $groupSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    if !groupSearchText.isEmpty {
                        Button { groupSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .tooltip("清空搜索")
                    }
                }
                // v15.38 V2 · 高级过滤 menu
                filterPresetMenu
                Spacer()
                Button {
                    sheetState = .addInstrument(groupID: group.id, groupName: group.name)
                } label: {
                    Label("添加合约", systemImage: "plus")
                }
                .tooltip("添加合约到「\(group.name)」（⌘⇧I）")
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .padding(16)

            Divider()
            // v15.38 V2 · 视图统计 HUD
            statsHUD(for: displayedIDs)
            Divider()
            instrumentColumnsHeader
            Divider()

            if group.instrumentIDs.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "分组为空",
                    hint: "点击右上「添加合约」· 双击此处 · 或从左侧拖入"
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    sheetState = .addInstrument(groupID: group.id, groupName: group.name)
                }
            } else {
                List(selection: $selectedInstruments) {
                    ForEach(Array(sortedInstrumentIDs(for: group).enumerated()), id: \.element) { index, id in
                        instrumentRow(id: id, index: index, groupID: group.id)
                            .tag(id)
                    }
                    trailingDropZone(groupID: group.id, count: group.instrumentIDs.count)
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let label = removeMenuLabel(for: ids) {
                        Button(label, role: .destructive) {
                            removeInstruments(ids, from: group.id)
                        }
                    }
                }
            }

            Divider()
            footerHint
        }
    }

    private var instrumentColumnsHeader: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 24)
            sortableHeaderCell(L("合约"), field: .instrumentID, width: 100, alignment: .leading)
            sortableHeaderCell(L("最新价"), field: .lastPrice, width: 90, alignment: .trailing)
            Spacer().frame(width: 16)
            sortableHeaderCell(L("涨跌幅"), field: .changePct, width: 80, alignment: .trailing)
            // v17.42 C1 · 可选列 header（持仓 / 成交量 / 价差%）· 与 extraColumnsCells 同步可见
            extraColumnsHeader()
            // v15.38 V2 · 隐藏排序触发器（不占视觉空间 · 只供菜单/快捷键调用）
            sortableHeaderCell(L("涨跌"), field: .change, width: 0, alignment: .trailing)
                .hidden()
            sortableHeaderCell(L("振幅"), field: .amplitude, width: 0, alignment: .trailing)
                .hidden()
            Spacer()
            // v15.38 V2 · 排序菜单（一键切到隐藏字段）
            sortFieldMenu
        }
        .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    /// v15.38 V2 · 排序字段下拉菜单（除了 columns header 已可点击的 4 字段，加 3 个新字段入口）
    private var sortFieldMenu: some View {
        Menu {
            ForEach(WatchlistSortField.allCases, id: \.self) { field in
                Button {
                    if sortField == field {
                        sortAscending.toggle()
                    } else {
                        setSortField(field)
                        sortAscending = false
                    }
                } label: {
                    HStack {
                        Text(field.displayName)
                        if sortField == field {
                            Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        }
                    }
                }
            }
        } label: {
            Label(sortField.displayName, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 11 + chartFontSize.sizeDelta))
        }
        .menuStyle(.borderlessButton)
        .frame(width: 90)
        .tooltip("按字段排序：包含成交量 / 涨跌 / 振幅 等扩展字段")
    }

    /// v15.20 batch59 · 可点击表头单元格（同字段切升降序 · 异字段切到该字段降序起）
    private func sortableHeaderCell(_ title: String, field: WatchlistSortField, width: CGFloat, alignment: Alignment) -> some View {
        let isActive = sortField == field
        let arrow = isActive ? (sortAscending ? "↑" : "↓") : ""
        return Text("\(title)\(arrow)")
            .frame(width: width, alignment: alignment)
            .foregroundColor(isActive ? .accentColor : .secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                if isActive {
                    sortAscending.toggle()
                } else {
                    setSortField(field)
                    sortAscending = false   // 默认降序（涨幅榜从高到低）
                }
            }
            .tooltip("点击按\(title)排序 · 再点切升降序 · 拖拽行自动切回手动")
    }

    /// v15.20 batch59 · 按 sortField + sortAscending 排序合约 ID（v15.38 V2 加 filter preset + 分组搜索）
    private func sortedInstrumentIDs(for group: Watchlist) -> [String] {
        // 先 filter（preset + 关键词）· 再 sort
        let filtered = WatchlistFilter.filter(
            ids: group.instrumentIDs,
            preset: filterPreset,
            keyword: groupSearchText,
            changePctForID: currentChangePct,
            volumeForID: currentVolume
        )
        return WatchlistSorter.sort(
            ids: filtered,
            field: sortField,
            ascending: sortAscending,
            keyForID: keyForInstrument
        )
    }

    /// v15.20 batch59 · 数值字段 closure（v15.38 V2 扩展 volume/change/amplitude）
    private func keyForInstrument(_ id: String) -> Double? {
        switch sortField {
        case .lastPrice:
            return quotes[id].map { NSDecimalNumber(decimal: $0.lastPrice).doubleValue }
        case .changePct:
            return parseChangePct(changePctText(for: id))
        case .change:
            return quotes[id].map { NSDecimalNumber(decimal: $0.change).doubleValue }
        case .openInterest:
            return quotes[id].map { Double($0.openInterest) }
        case .volume:
            return quotes[id].map { Double($0.volume) }
        case .amplitude:
            // 振幅 = (high - low) / preSettlement
            guard let q = quotes[id] else { return nil }
            let hi = NSDecimalNumber(decimal: q.high).doubleValue
            let lo = NSDecimalNumber(decimal: q.low).doubleValue
            let pre = NSDecimalNumber(decimal: q.preSettlement).doubleValue
            guard pre > 1e-9 else { return nil }
            return (hi - lo) / pre * 100   // 百分比
        case .spread:
            // v17.33 C4 · 买卖价差% = (ask - bid) / last · last ≤ 0 / bid·ask 0 → nil 排末
            guard let q = quotes[id], q.bidPrice > 0, q.askPrice > 0 else { return nil }
            let bid = NSDecimalNumber(decimal: q.bidPrice).doubleValue
            let ask = NSDecimalNumber(decimal: q.askPrice).doubleValue
            let last = NSDecimalNumber(decimal: q.lastPrice).doubleValue
            guard last > 1e-9 else { return nil }
            return (ask - bid) / last * 100
        case .manual, .instrumentID:
            return nil   // sorter 不调 keyForID
        }
    }

    /// v15.38 V2 · 当前 quote 涨跌幅（filter / stats 用 · keyForInstrument 受 sortField 影响 · 此 helper 始终返回 changePct）
    private func currentChangePct(_ id: String) -> Double? {
        parseChangePct(changePctText(for: id))
    }

    /// v15.38 V2 · 当前 quote 成交量（filter active 用）
    private func currentVolume(_ id: String) -> Double? {
        quotes[id].map { Double($0.volume) }
    }

    // MARK: - v15.38 V2 · Filter Menu + Stats HUD

    /// 过滤 preset Menu（toolbar 用 · 6 个内置 preset · 选中 ✓ 标识）
    private var filterPresetMenu: some View {
        Menu {
            ForEach(WatchlistFilterPreset.allCases, id: \.self) { preset in
                Button {
                    setFilterPreset(preset)
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if filterPreset == preset {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(filterPreset == .all ? "过滤" : filterPreset.displayName,
                  systemImage: filterPreset == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
                .foregroundColor(filterPreset == .all ? .primary : .accentColor)
        }
        .tooltip("按涨跌幅 / 涨跌停 / 活跃度过滤合约")
    }

    /// 视图统计 HUD（涨跌家数 + 平均涨幅 + 涨停跌停数 + 极值合约 ID）
    /// 显示在视图顶部 · 一眼定位市场情绪
    @ViewBuilder
    private func statsHUD(for ids: [String]) -> some View {
        let stats = WatchlistStatsCalculator.compute(ids: ids, changePctForID: currentChangePct)
        if stats.total == 0 {
            EmptyView()
        } else {
            HStack(spacing: 14) {
                statBadge(systemImage: "arrow.up.circle.fill",
                         text: "\(stats.gainers) 涨", color: .red)
                statBadge(systemImage: "arrow.down.circle.fill",
                         text: "\(stats.losers) 跌", color: .green)
                if stats.unchanged > 0 {
                    statBadge(systemImage: "circle", text: "\(stats.unchanged) 平", color: .secondary)
                }
                if stats.limitUpCount > 0 {
                    statBadge(systemImage: "bolt.fill",
                             text: "\(stats.limitUpCount) 涨停", color: .red)
                }
                if stats.limitDownCount > 0 {
                    statBadge(systemImage: "bolt.fill",
                             text: "\(stats.limitDownCount) 跌停", color: .green)
                }
                Divider().frame(height: 14)
                Text("均 \(String(format: "%+.2f%%", stats.avgChangePct))")
                    .font(.caption.monospaced())
                    .foregroundColor(stats.avgChangePct >= 0 ? .red : .green)
                if let topG = stats.topGainerID {
                    Text("领涨 \(topG) \(String(format: "%+.1f%%", stats.topGainerPct))")
                        .font(.caption.monospaced())
                        .foregroundColor(.red.opacity(0.85))
                }
                if let topL = stats.topLoserID {
                    Text("领跌 \(topL) \(String(format: "%+.1f%%", stats.topLoserPct))")
                        .font(.caption.monospaced())
                        .foregroundColor(.green.opacity(0.85))
                }
                Spacer()
                // 偏向条（直观可视）
                bullBiasIndicator(stats.bullBias)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.05))
        }
    }

    private func statBadge(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.caption2).foregroundColor(color)
            Text(text).font(.caption.monospaced()).foregroundColor(color)
        }
    }

    /// 多空偏向条（-1..+1 · 红多 / 绿空 · trader 一眼看市场倾向）
    private func bullBiasIndicator(_ bias: Double) -> some View {
        let normalized = (bias + 1) / 2   // 映射到 [0, 1]
        return HStack(spacing: 2) {
            Text("情绪").font(.caption2).foregroundColor(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.green.opacity(0.25)).frame(width: 80, height: 8)
                Capsule().fill(bias >= 0 ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    .frame(width: max(2, CGFloat(normalized) * 80), height: 8)
            }
            Text(String(format: "%+.0f%%", bias * 100))
                .font(.caption.monospaced())
                .foregroundColor(bias >= 0 ? .red : .green)
                .frame(width: 36, alignment: .trailing)
        }
        .tooltip("多空偏向（涨家数 - 跌家数）/ 总数 · 红=偏多 · 绿=偏空")
    }

    private func instrumentRow(id: String, index: Int, groupID: UUID) -> some View {
        let change = changePctText(for: id)
        let pctValue = parseChangePct(change)
        // v15.21 batch130 · 极端涨跌幅警示（≥ 9% 接近涨跌停 · row outline 提示 · trader 视觉警觉）
        let isExtreme = abs(pctValue ?? 0) >= 9
        // v17.34 C5 · 当前合约旗标（持久化 InstrumentFlagStore · UserDefaults 跨窗口同步）
        let flag = flagStore.flag(for: id)
        // v17.129 · 当前合约备注（持久化 InstrumentNoteStore · 跨窗口同步）
        let note = noteStore.note(for: id)
        return HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 24)
            HStack(spacing: 4) {
                if flag != .none {
                    Text(flag.emoji)
                        .font(.system(size: 11 + chartFontSize.sizeDelta))
                        .tooltip(flag.displayName)
                }
                Text(id)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                // v17.129 · 备注 📝 小标识 · hover tooltip 显完整内容
                if let n = note {
                    Image(systemName: "note.text")
                        .font(.system(size: 10 + chartFontSize.sizeDelta))
                        .foregroundColor(.accentColor.opacity(0.85))
                        .tooltip(n)
                }
            }
                .frame(width: 100, alignment: .leading)
            Text(priceText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Self.priceColor(pctValue))
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 16)
            Text(change)
                .font(.system(.body, design: .monospaced))
                .fontWeight(abs(pctValue ?? 0) >= 2 ? .bold : .regular)
                .foregroundColor(Self.priceColor(pctValue))
                .frame(width: 80, alignment: .trailing)
                .tooltip(detailedChangeText(for: id))   // v15.21 batch133 · hover 显示绝对涨跌 + 振幅
            // v17.42 C1 · 可选列（持仓 / 成交量 / 价差%）· 右键 📋 显示列 toggle
            extraColumnsCells(for: id)
            Spacer().frame(width: 12)
            // v15.78 · combo 徽章（命中才显示 · 跨窗口视觉与 ⌘⌥H/B/N 一致）
            comboWatchlistBadge(for: id)
                .frame(width: 56, alignment: .center)
            Spacer()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // v15.21 batch130 · 极端 row 加 1px outline（红涨/绿跌 · trader 不看涨跌幅也能秒识别）
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isExtreme ? Self.priceColor(pctValue).opacity(0.6) : Color.clear, lineWidth: 1)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openInstrumentInChart(id)
        }
        .contextMenu {
            // v15.19 batch48 · 右键一键创建预警模板（联动 AlertPreset · 复用 alertAddedFromChart）
            Button("打开主图") { openInstrumentInChart(id) }
            // v15.21 batch128 · 跨窗口联动 · 看本合约预警（AlertWindow 自动 filter）
            Button("查看本合约预警") {
                NotificationCenter.default.post(name: .alertWindowFilterToInstrument, object: id)
                openWindow(id: "alert")
            }
            // v15.21 batch97 · 复制合约代码 / 最新价（trader 报单 / 截单 高频粘贴）
            Button("复制合约代码 \(id)") {
                Pasteboard.copy(id)
            }
            Button("复制最新价 \(priceText(for: id))") {
                Pasteboard.copy(priceText(for: id))
            }
            // v15.21 batch115 · 复制行所有信息（合约 + 价 + 涨跌 + 持仓 · 一行文本 · trader 截行情发邮件）
            Button("复制行所有信息") {
                let line = "\(id)  \(priceText(for: id))  \(changePctText(for: id))  持仓\(openInterestText(for: id))"
                Pasteboard.copy(line)
            }
            Divider()
            // v17.34 C5 · 旗标 / 评级（持久化 · 跨窗口同步）
            Menu("🚩 旗标 \(flag == .none ? "" : "（当前 \(flag.emoji)）")") {
                ForEach(InstrumentFlag.allCases, id: \.self) { f in
                    Button {
                        flagStore.setFlag(f, for: id)
                        flagsRevision += 1
                    } label: {
                        HStack {
                            Text(f.emoji.isEmpty ? "—" : f.emoji)
                            Text(f.displayName)
                            if flag == f {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Menu("📋 创建预警模板") {
                ForEach(AlertPreset.allCases) { preset in
                    Button(preset.displayName) {
                        createAlertPreset(preset, instrumentID: id)
                    }
                    .tooltip(preset.helpText)
                }
                Divider()
                Button("全部 6 类一次创建") {
                    createAllAlertPresets(instrumentID: id)
                }
            }
            // v17.129 · 备注编辑（trader 个人笔记 · 全局持久化 · 跨窗口同步）
            Button(note == nil ? "📝 添加备注" : "📝 编辑备注") {
                pendingNoteInstrumentID = NoteEditTarget(id: id)
            }
            if note != nil {
                Button("📝 删除备注") {
                    noteStore.setNote(nil, for: id)
                    flagsRevision += 1  // 复用 tick 触发 row 重渲
                }
            }
            // v17.42 C1 · 列自定义（toggle 持仓 / 成交量 / 价差% · UserDefaults 跨窗口同步）
            columnVisibilityMenu()
        }
        .overlay(alignment: .top) { insertionIndicator(at: groupID, index: index) }
        .draggable(WatchlistInstrumentRef(sourceGroupID: groupID, instrumentID: id)) {
            dragPreview(systemImage: "doc.text.fill", text: id)
        }
        .dropDestination(for: WatchlistInstrumentRef.self) { refs, _ in
            guard let ref = refs.first else { return false }
            return moveInstrumentToSlot(ref, targetGroupID: groupID, targetIndex: index)
        } isTargeted: { isOver in
            updateHover(.instrumentSlot(groupID: groupID, beforeIndex: index), active: isOver)
        }
    }

    private func trailingDropZone(groupID: UUID, count: Int) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 56)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { insertionIndicator(at: groupID, index: count) }
            .dropDestination(for: WatchlistInstrumentRef.self) { refs, _ in
                guard let ref = refs.first else { return false }
                return moveInstrumentToSlot(ref, targetGroupID: groupID, targetIndex: count)
            } isTargeted: { isOver in
                updateHover(.instrumentSlot(groupID: groupID, beforeIndex: count), active: isOver)
            }
            // v15.21 batch88 · 双击末尾空白区 → 添加合约 sheet（trader 流畅工作流 · ⌘⇧I 快捷键互补）
            .onTapGesture(count: 2) {
                guard let group = book.group(id: groupID) else { return }
                sheetState = .addInstrument(groupID: groupID, groupName: group.name)
            }
            .listRowSeparator(.hidden)
    }

    /// 行/末尾共用的 2px 蓝色横线提示（hover 命中目标 slot 时显现）
    private func insertionIndicator(at groupID: UUID, index: Int) -> some View {
        let isActive = hoverTarget == .instrumentSlot(groupID: groupID, beforeIndex: index)
        return Rectangle()
            .fill(Color.accentColor)
            .frame(height: isActive ? 2 : 0)
    }

    private func dragPreview(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func removeMenuLabel(for ids: Set<String>) -> String? {
        guard let first = ids.first else { return nil }
        if ids.count == 1 {
            return "从分组移除「\(first)」"
        }
        return "从分组移除选中的 \(ids.count) 个合约"
    }

    private var footerHint: some View {
        HStack(spacing: 12) {
            Text("双击合约打开主图 · 含主连续 + 活跃月份合约")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            // v15.20 batch78 · 状态汇总：分组数 / 合约总数 / 已染色统计
            statusSummary
            if !selectedInstruments.isEmpty {
                Divider().frame(height: 12)
                Text("已选 \(selectedInstruments.count) 个 · 右键移除")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// v15.20 batch78 · 自选状态汇总（分组数 / 合约总数 / 涨跌平统计 · trader 全局快览）
    private var statusSummary: some View {
        let totalGroups = book.groups.count
        let totalUnique = book.allInstrumentIDsDeduped.count
        let pcts = book.allInstrumentIDsDeduped.compactMap { parseChangePct(changePctText(for: $0)) }
        let upCount = pcts.filter { $0 > 0 }.count
        let downCount = pcts.filter { $0 < 0 }.count
        return HStack(spacing: 8) {
            Text("\(totalGroups) 组")
                .font(.caption2).foregroundColor(.secondary)
            Text("·").foregroundColor(.secondary)
            Text("\(totalUnique) 合约（去重）")
                .font(.caption2).foregroundColor(.secondary)
            if !pcts.isEmpty {
                Text("·").foregroundColor(.secondary)
                Text("涨 \(upCount)")
                    .font(.caption2).foregroundColor(Self.priceColor(0.5))   // 红
                Text("/")
                    .font(.caption2).foregroundColor(.secondary)
                Text("跌 \(downCount)")
                    .font(.caption2).foregroundColor(Self.priceColor(-0.5))  // 绿
            }
        }
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title).font(.title3).foregroundColor(.secondary)
            Text(hint).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Mutations · CRUD

    private func addGroup(name: String) {
        guard let trimmed = name.trimmedOrNil else { return }
        let group = book.addGroup(name: trimmed)
        selectedGroupID = group.id
    }

    private func renameGroup(_ group: Watchlist, to name: String) {
        guard let trimmed = name.trimmedOrNil, trimmed != group.name else { return }
        book.renameGroup(id: group.id, to: trimmed)
    }

    private func deleteGroup(_ group: Watchlist) {
        let wasSelected = selectedGroupID == group.id
        book.removeGroup(id: group.id)
        if wasSelected {
            selectedGroupID = book.groups.first?.id
        }
        pendingDeleteGroup = nil
    }

    private func addInstrument(_ id: String, to groupID: UUID) {
        guard let trimmed = id.trimmedOrNil?.uppercased() else { return }
        // v15.21 batch134 · 添加合约 toast 反馈（已存在 / 已加入 两态 · 与 batch131 跨窗口 add 一致）
        guard let group = book.group(id: groupID) else { return }
        if group.instrumentIDs.contains(trimmed) {
            Toast.info("已存在", "\(trimmed) 已在「\(group.name)」")
            return
        }
        book.addInstrument(trimmed, to: groupID)
        Toast.info("已添加", "\(trimmed) → 「\(group.name)」")
    }

    private func removeInstruments(_ ids: Set<String>, from groupID: UUID) {
        ids.forEach { book.removeInstrument($0, from: groupID) }
        selectedInstruments.subtract(ids)
    }

    // MARK: - Mutations · 拖拽

    /// "落在 targetIndex 前"语义 → Array.move 风格的 (from, to) 转换
    /// - 落在自己 / 紧邻自己之后 → no-op（返回 nil）
    /// - 落点在源之后 → -1 修正（删除源元素后下游索引前移）
    private static func resolveDropIndex(from: Int, target: Int) -> Int? {
        if target == from || target == from + 1 { return nil }
        return target > from ? target - 1 : target
    }

    /// 拖分组到目标位置（before: 落在目标行的"前面"）
    @discardableResult
    private func moveGroup(_ draggedID: UUID, before targetIndex: Int) -> Bool {
        defer { clearHover() }
        guard let from = book.groups.firstIndex(where: { $0.id == draggedID }),
              let to = Self.resolveDropIndex(from: from, target: targetIndex)
        else { return false }
        return book.moveGroup(from: from, to: to)
    }

    /// 同源同组（重排序）或跨源（移动）合约 · targetIndex 表示插入到该位置（落在该 row 前）
    @discardableResult
    private func moveInstrumentToSlot(_ ref: WatchlistInstrumentRef, targetGroupID: UUID, targetIndex: Int) -> Bool {
        defer { clearHover() }
        // v15.20 batch59 · 用户拖拽重排 → 自动切回 .manual（否则 sort 会立刻覆盖拖拽结果）
        if sortField != .manual { setSortField(.manual) }
        if ref.sourceGroupID == targetGroupID {
            guard let group = book.group(id: targetGroupID),
                  let from = group.instrumentIDs.firstIndex(of: ref.instrumentID),
                  let to = Self.resolveDropIndex(from: from, target: targetIndex)
            else { return false }
            return book.moveInstrument(in: targetGroupID, from: from, to: to)
        }
        let result = book.moveInstrument(
            ref.instrumentID,
            from: ref.sourceGroupID,
            to: targetGroupID,
            targetIndex: targetIndex
        )
        if result { selectedInstruments.remove(ref.instrumentID) }
        return result
    }

    /// 拖合约到分组行（sidebar）→ 移到目标组末尾（同组源 → no-op · 已在目标组同 ID → 仅删源）
    @discardableResult
    private func moveInstrumentToGroupTail(_ ref: WatchlistInstrumentRef, target targetGroupID: UUID) -> Bool {
        defer { clearHover() }
        if ref.sourceGroupID == targetGroupID { return false }
        let result = book.moveInstrument(
            ref.instrumentID,
            from: ref.sourceGroupID,
            to: targetGroupID,
            targetIndex: nil
        )
        if result { selectedInstruments.remove(ref.instrumentID) }
        return result
    }

    // MARK: - 主图联动（commit 4）

    /// 双击合约 → 打开/激活主图窗口 · 通过 NotificationCenter 推送给 ChartScene 切换合约
    /// 不支持的合约本地拦截（主图仅支持 supportedContracts · 不污染 ChartScene 容错路径）
    private func openInstrumentInChart(_ id: String) {
        guard MarketDataPipeline.supportedContracts.contains(id) else {
            unsupportedInstrumentAlert = id
            return
        }
        openWindow(id: "chart")
        NotificationCenter.default.post(name: .watchlistInstrumentSelected, object: id)
    }

    // MARK: - Hover 反馈

    private func updateHover(_ target: HoverTarget, active: Bool) {
        if active {
            hoverTarget = target
        } else if hoverTarget == target {
            hoverTarget = nil
        }
    }

    private func clearHover() {
        hoverTarget = nil
    }

    // MARK: - 文华自选 .txt 导入（v12.17 · WatchlistImporter UI 入口）

    /// 文华自选导入预览数据（NSOpenPanel 选文件 → 解析后展示给用户确认）
    private struct ImportPreview {
        let parseResult: WatchlistImportResult
        let message: String
    }

    private var importPreviewBinding: Binding<Bool> {
        Binding(
            get: { importPreview != nil },
            set: { if !$0 { importPreview = nil } }
        )
    }

    /// v15.21 batch91 · 双格式导入：.txt 文华自选（含 "{" 标头）走严格 · 否则（.csv / 自由 .txt）走 QuickPasteSheet 预填
    /// v15.23 batch199 · 单分组导出 .txt（每行一个合约 · 文华格式兼容）
    @MainActor
    private func exportGroupToFile(groupID: UUID) {
        guard let group = book.group(id: groupID) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.title = "导出分组「\(group.name)」"
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "自选-\(group.name)-\(group.instrumentIDs.count)个-\(dateStr).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = group.instrumentIDs.joined(separator: "\n") + "\n"
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            Toast.info("导出成功", "\(group.instrumentIDs.count) 个合约 → \(url.lastPathComponent)")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    /// v15.23 batch199 · 全部分组导出（每分组前面加 # 注释行 · 不影响导入解析）
    @MainActor
    private func exportAllGroupsToFile() {
        guard !book.groups.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.title = L("导出全部分组")
        let totalCount = book.groups.reduce(0) { $0 + $1.instrumentIDs.count }
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "自选-全部\(book.groups.count)分组-\(totalCount)个-\(dateStr).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines: [String] = []
        for group in book.groups {
            lines.append("# \(group.name) (\(group.instrumentIDs.count))")
            lines.append(contentsOf: group.instrumentIDs)
            lines.append("")  // 空行分隔
        }
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            Toast.info("导出成功", "\(book.groups.count) 分组 / \(totalCount) 合约 → \(url.lastPathComponent)")
        } catch {
            Toast.error("导出失败", error)
        }
    }

    /// v15.23 batch199 · 当前分组复制到剪贴板（NSPasteboard · trader 快速粘到 IM）
    @MainActor
    private func copyCurrentGroupToPasteboard() {
        guard let groupID = selectedGroupID,
              let group = book.group(id: groupID) else { return }
        let content = group.instrumentIDs.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        Toast.info("已复制", "「\(group.name)」\(group.instrumentIDs.count) 个合约")
    }

    private func importWatchlistFromFile() {
        let panel = NSOpenPanel()
        panel.title = L("导入自选合约（.txt 文华格式 · .csv 自由表格）")
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            importPreview = ImportPreview(
                parseResult: WatchlistImportResult(groups: []),
                message: "导入失败：\(error.localizedDescription)"
            )
            return
        }

        // 文华标头检测：含 "{" 走严格分组解析（保多分组结构）· 否则走 QuickPasteSheet 让 trader 选目标分组
        if text.contains("{") {
            let result = WatchlistImporter.parse(text)
            let groupSummary = result.groups.map { "「\($0.name)」\($0.instrumentIDs.count) 个" }.joined(separator: " / ")
            importPreview = ImportPreview(
                parseResult: result,
                message: "解析到 \(result.groups.count) 个分组 · 共 \(result.totalInstruments) 个合约：\n\(groupSummary)\n\n确认导入将合并到当前自选（同名分组追加去重 / 新分组新建）"
            )
        } else {
            // .csv / 无标头自由 .txt → 复用 QuickPasteSheet（QuickPasteParser 自动跳过纯数字 token + 表头列名）
            quickPasteInitialText = text
            showQuickPasteSheet = true
        }
    }

    private func applyImport(_ result: WatchlistImportResult) {
        guard !result.groups.isEmpty else {
            importPreview = nil
            return
        }
        _ = WatchlistImporter.merge(result, into: &book)
        importPreview = nil
    }

    // MARK: - 真行情拉取（v12.4 · 5s 周期 · 失败保留旧值 / 首次失败 fallback Mock）

    /// 启动周期 fetch · 自动包含 book 内全部去重合约 ID · 失败 silent · 5s 间隔
    /// v12.5 改用 fetchQuotesWithFallback：实时端点失败合约走 K 线 5min 末根伪实时（已交割 / sina 抖动场景）
    private func startQuoteFetch() {
        quoteFetchTask?.cancel()
        quoteFetchTask = Task { @MainActor in
            let sina = SinaMarketData()
            while !Task.isCancelled {
                let allIDs = Array(Set(book.groups.flatMap { $0.instrumentIDs }))
                if !allIDs.isEmpty {
                    let fetched = await sina.fetchQuotesWithFallback(symbols: allIDs)
                    var next = quotes
                    for q in fetched { next[q.symbol] = q }
                    quotes = next
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: - v15.78 · combo 异常映射周期刷新

    /// 启动 30s 周期刷 comboMap · detector 全是纯函数 · 60 品种 ~1ms · 不发网络
    private func startComboFetch() {
        comboFetchTask?.cancel()
        comboFetchTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshComboMap()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    @MainActor
    private func refreshComboMap() {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        let combos = ComboAnomalyAggregator.aggregate(events: result.events, minKinds: 3)
        comboMap = Dictionary(uniqueKeysWithValues: combos.map { ($0.instrumentID, $0) })
    }

    /// v15.78 · 用户合约名（"rb2509"）→ SectorPresets.id（"RB0"）映射兼容（与 SectorHUDInfo.matchInstrument 同模式）
    private func comboFor(userID: String) -> ComboAnomaly? {
        if let c = comboMap[userID] { return c }
        let upper = userID.uppercased()
        if let c = comboMap[upper] { return c }
        let letters = String(upper.prefix(while: { $0.isLetter }))
        guard !letters.isEmpty else { return nil }
        if let c = comboMap["\(letters)0"] { return c }
        return nil
    }

    /// v15.78 · 自选行 combo 徽章（命中才显示）
    @ViewBuilder
    private func comboWatchlistBadge(for id: String) -> some View {
        if let c = comboFor(userID: id) {
            HStack(spacing: 2) {
                Image(systemName: "sparkles").font(.system(size: 9 + chartFontSize.sizeDelta))
                Text("\(c.kindCount)/5").font(.system(size: 10 + chartFontSize.sizeDelta, design: .monospaced).bold())
            }
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(comboBadgeColor(c), in: RoundedRectangle(cornerRadius: 3))
            .tooltip(comboHelpText(c))
        } else {
            Text("—").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
    }

    private func comboBadgeColor(_ c: ComboAnomaly) -> Color {
        if c.kindCount >= 5 { return chartLoss }
        if c.kindCount == 4 { return .orange }
        return .yellow
    }

    private func comboHelpText(_ c: ComboAnomaly) -> String {
        let kindLabel = AnomalyKind.allCases
            .filter { c.kinds.contains($0) }
            .map(\.displayName)
            .joined(separator: " · ")
        return "✨ Combo \(c.kindCount)/5（\(kindLabel)）· severity \(Int(c.totalSeverity))"
    }

    /// v15.21 batch109 · 立即刷新报价（不影响 5s 周期 task · trader 重要数据/会议前后强刷）
    @MainActor
    private func refreshQuotesNow() {
        let allIDs = Array(Set(book.groups.flatMap { $0.instrumentIDs }))
        guard !allIDs.isEmpty else { return }
        Task { @MainActor in
            let sina = SinaMarketData()
            let fetched = await sina.fetchQuotesWithFallback(symbols: allIDs)
            var next = quotes
            for q in fetched { next[q.symbol] = q }
            quotes = next
        }
    }

    /// v17.103 · 价格小数位（PricePrecisionMode + 合约 priceTick · 每合约各自精度）
    private func priceDigits(for id: String) -> Int {
        let mode = ChartSettingsStore.loadPricePrecision()
        if let d = mode.digits { return d }
        return ChineseFuturesProducts.priceTickDigits(forInstrumentID: id) ?? 2
    }

    /// 最新价文本 · 真值 fallback Mock · v17.103 接 PricePrecisionMode
    private func priceText(for id: String) -> String {
        if let q = quotes[id] {
            return String(format: "%.\(priceDigits(for: id))f", NSDecimalNumber(decimal: q.lastPrice).doubleValue)
        }
        return MockQuote.price(for: id)
    }

    /// v15.21 batch133 · row 涨跌幅 hover 提示（绝对涨跌 + 振幅 + 昨结算 · v17.33 加 Bid/Ask/spread · v17.103 接 priceDigits）
    private func detailedChangeText(for id: String) -> String {
        guard let q = quotes[id] else { return "（无实时数据 · 仅 Mock 价格）" }
        let abs = NSDecimalNumber(decimal: q.change).doubleValue
        let amp = q.preSettlement != 0
            ? NSDecimalNumber(decimal: (q.high - q.low) / q.preSettlement).doubleValue * 100
            : 0
        let pre = NSDecimalNumber(decimal: q.preSettlement).doubleValue
        let d = priceDigits(for: id)
        let bidAskLine: String
        if q.bidPrice > 0, q.askPrice > 0, q.lastPrice > 0 {
            let bid = NSDecimalNumber(decimal: q.bidPrice).doubleValue
            let ask = NSDecimalNumber(decimal: q.askPrice).doubleValue
            let last = NSDecimalNumber(decimal: q.lastPrice).doubleValue
            let spreadPct = (ask - bid) / last * 100
            bidAskLine = String(format: " · 买 %.\(d)f / 卖 %.\(d)f · 价差 %.3f%%", bid, ask, spreadPct)
        } else {
            bidAskLine = ""
        }
        return String(format: "绝对涨跌：%+.\(d)f · 振幅：%.2f%% · 昨结算：%.\(d)f%@", abs, amp, pre, bidAskLine)
    }

    /// v15.19 batch48 · 右键一键创建单个预警预设（联动 AlertPreset + alertAddedFromChart 通知）
    @MainActor
    private func createAlertPreset(_ preset: AlertPreset, instrumentID: String) {
        // 用当前最新价（quotes 实时报价 fallback Mock 价的 Decimal 解析）
        let lastPrice = currentLastPrice(for: instrumentID)
        let alert = preset.makeAlert(instrumentID: instrumentID, lastPrice: lastPrice)
        NotificationCenter.default.post(name: .alertAddedFromChart, object: alert)
    }

    /// v15.19 batch48 · 一次创建 6 类全部预设
    @MainActor
    private func createAllAlertPresets(instrumentID: String) {
        let lastPrice = currentLastPrice(for: instrumentID)
        let alerts = AlertPreset.makeAlerts(AlertPreset.allCases, instrumentID: instrumentID, lastPrice: lastPrice)
        for a in alerts {
            NotificationCenter.default.post(name: .alertAddedFromChart, object: a)
        }
    }

    /// v15.20 batch68 · 涨幅/跌幅前 N 一键批量预警（聚合扫盘 + AlertPreset 联动）
    /// - 按涨跌幅排序（沿用 WatchlistSorter）取前 N · 给每个合约创建一条 preset 预警
    /// - 通过 NotificationCenter.alertAddedFromChart 投递到 AlertWindow（AlertWindow.append 自动 evaluator sync）
    /// - 没有有效涨跌幅数据的合约自动跳过（nil key 排末尾 · 取前 N 时已过滤）
    @MainActor
    private func batchAlertTopMovers(topN: Int, ascending: Bool, preset: AlertPreset) {
        let sortedIDs = WatchlistSorter.sort(
            ids: aggregatedInstrumentIDs,
            field: .changePct,
            ascending: ascending,
            keyForID: { id in parseChangePct(changePctText(for: id)) }
        )
        // 跳过 nil 涨跌幅（数据未拉到的）· 真实涨跌幅排序的前 N
        let valid = sortedIDs.filter { parseChangePct(changePctText(for: $0)) != nil }
        let target = Array(valid.prefix(topN))
        for id in target {
            createAlertPreset(preset, instrumentID: id)
        }
    }

    /// 取当前最新价（实时 quotes 优先 · fallback Mock 字符串解析 · 异常兜底 0）
    private func currentLastPrice(for id: String) -> Decimal {
        if let q = quotes[id] { return q.lastPrice }
        if let parsed = Decimal(string: MockQuote.price(for: id)) { return parsed }
        return 0
    }

    /// 涨跌幅文本 · 前缀 "+"/"-" 兼容现有涨跌色判断（hasPrefix("-") → green）
    private func changePctText(for id: String) -> String {
        if let q = quotes[id], q.preSettlement > 0 {
            let pct = NSDecimalNumber(decimal: q.changePercent).doubleValue
            return String(format: "%+.2f%%", pct)
        }
        return MockQuote.changePct(for: id)
    }

    /// 解析涨跌幅文本 → 百分点（"+1.23%" → 1.23）· "—" / 不可解析 → nil
    private func parseChangePct(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: "%", with: "")
        return Double(t)
    }

    /// 涨跌幅渐变染色（trader 一眼扫盘）· 中国期货习惯：涨红 / 跌绿
    /// |Δ| ≤ 0.5%：primary 不染 · ≤ 1%：浅 · ≤ 2%：标准 · > 2%：深
    static func priceColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .secondary }
        let abs = Swift.abs(p)
        if abs < 0.5 { return .primary }
        let isUp = p > 0
        // 颜色台阶（与中国期货软件一致 · 涨红跌绿）
        if abs >= 2 { return isUp ? Color(red: 0.85, green: 0.10, blue: 0.10) : Color(red: 0.05, green: 0.55, blue: 0.20) }
        if abs >= 1 { return isUp ? Color(red: 0.92, green: 0.30, blue: 0.30) : Color(red: 0.20, green: 0.65, blue: 0.30) }
        return isUp ? Color(red: 0.96, green: 0.55, blue: 0.45) : Color(red: 0.50, green: 0.75, blue: 0.45)
    }

    /// 持仓量文本 · ≥1M 用 M / ≥1K 用 K · 真值 fallback Mock
    private func openInterestText(for id: String) -> String {
        if let q = quotes[id] {
            let oi = q.openInterest
            if oi >= 1_000_000 { return String(format: "%.2fM", Double(oi) / 1_000_000) }
            if oi >= 1_000 { return String(format: "%.0fK", Double(oi) / 1_000) }
            return String(oi)
        }
        return MockQuote.openInterest(for: id)
    }

    /// v17.42 C1 · 成交量文本（≥1M 用 M / ≥1K 用 K · 无报价 → "—"）
    private func volumeText(for id: String) -> String {
        guard let q = quotes[id] else { return "—" }
        let v = q.volume
        if v >= 1_000_000 { return String(format: "%.2fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", Double(v) / 1_000) }
        return String(v)
    }

    /// v17.42 C1 · 买卖价差%（(ask-bid)/last · 缺值 / 无报价 → "—"）
    private func spreadText(for id: String) -> String {
        guard let q = quotes[id], q.bidPrice > 0, q.askPrice > 0, q.lastPrice > 0 else { return "—" }
        let bid = NSDecimalNumber(decimal: q.bidPrice).doubleValue
        let ask = NSDecimalNumber(decimal: q.askPrice).doubleValue
        let last = NSDecimalNumber(decimal: q.lastPrice).doubleValue
        return String(format: "%.3f%%", (ask - bid) / last * 100)
    }

    /// v17.42 C1 · 可选列 cells（持仓 / 成交量 / 价差%）· instrumentRow + aggregatedRow 共用
    @ViewBuilder
    private func extraColumnsCells(for id: String) -> some View {
        if visibleColumns.contains(.openInterest) {
            Spacer().frame(width: 16)
            Text(openInterestText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: WatchlistColumn.openInterest.width, alignment: .trailing)
        }
        if visibleColumns.contains(.volume) {
            Spacer().frame(width: 16)
            Text(volumeText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: WatchlistColumn.volume.width, alignment: .trailing)
                .tooltip("成交量（M=百万 · K=千）")
        }
        if visibleColumns.contains(.spread) {
            Spacer().frame(width: 16)
            Text(spreadText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: WatchlistColumn.spread.width, alignment: .trailing)
                .tooltip("买卖价差 % = (ask - bid) / last")
        }
    }

    /// v17.42 C1 · 可选列 sortable header（与 extraColumnsCells 列宽对位）
    @ViewBuilder
    private func extraColumnsHeader() -> some View {
        if visibleColumns.contains(.openInterest) {
            Spacer().frame(width: 16)
            sortableHeaderCell(L("持仓量"), field: .openInterest,
                              width: WatchlistColumn.openInterest.width, alignment: .trailing)
        }
        if visibleColumns.contains(.volume) {
            Spacer().frame(width: 16)
            sortableHeaderCell(L("成交量"), field: .volume,
                              width: WatchlistColumn.volume.width, alignment: .trailing)
        }
        if visibleColumns.contains(.spread) {
            Spacer().frame(width: 16)
            sortableHeaderCell(L("买卖价差%"), field: .spread,
                              width: WatchlistColumn.spread.width, alignment: .trailing)
        }
    }

    /// v17.42 C1 · 右键菜单"📋 显示列"submenu（toggle 持久化 · 跨窗口立即同步）
    @ViewBuilder
    private func columnVisibilityMenu() -> some View {
        Menu("📋 显示列") {
            ForEach(WatchlistColumn.allCases) { col in
                Button {
                    visibleColumns = WatchlistColumnPreferences.toggle(col)
                } label: {
                    HStack {
                        Image(systemName: visibleColumns.contains(col) ? "checkmark.square" : "square")
                        Text(col.displayName)
                    }
                }
            }
        }
    }
}

// MARK: - Transferable 拖拽载荷

private struct WatchlistGroupRef: Codable, Hashable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

private struct WatchlistInstrumentRef: Codable, Hashable, Transferable {
    let sourceGroupID: UUID
    let instrumentID: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// v17.129 · 备注编辑 sheet 目标 · Identifiable 包装 instrumentID 让 .sheet(item:) 兼容
private struct NoteEditTarget: Identifiable, Hashable {
    let id: String  // instrumentID 自身就是 id
}

// MARK: - Notification.Name · 跨窗口联动

extension Notification.Name {
    /// WP-43 commit 4 · WatchlistWindow 双击合约 → ChartScene 切换合约（object: instrumentID String）
    static let watchlistInstrumentSelected = Notification.Name("watchlistInstrumentSelected")
}

// MARK: - String 私有扩展

private extension String {
    /// 去前后空白后返回；若为空返回 nil
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Sheet · 分组名（add / rename 共用）

private struct GroupNameSheet: View {

    let title: String
    let initialName: String
    let actionLabel: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, initialName: String, actionLabel: String, onSubmit: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.actionLabel = actionLabel
        self.onSubmit = onSubmit
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).bold()

            Form {
                TextField("分组名", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(actionLabel) {
                    onSubmit(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 360, height: 220)
    }

    private var canSubmit: Bool {
        guard let trimmed = name.trimmedOrNil else { return false }
        return trimmed != initialName
    }
}

// MARK: - Sheet · 合约 ID 输入

private struct InstrumentIDSheet: View {

    let groupName: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instrumentID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加合约到「\(groupName)」").font(.title2).bold()

            Form {
                TextField("合约代码（如 RB0 / IF2509）", text: $instrumentID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Text("主力合约支持：RB0 / IF0 / AU0 / CU0\n（其他可输入 · commit 4 主图联动时不支持的合约会回退到主力）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") {
                    onSubmit(instrumentID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(instrumentID.trimmedOrNil == nil)
            }
        }
        .padding(20)
        .frame(width: 380, height: 280)
    }
}

// MARK: - Sheet · 合约备注编辑（v17.129 · trader 个人笔记 · 全局持久化 InstrumentNoteStore）

private struct NoteEditSheet: View {

    let instrumentID: String
    let initialNote: String
    let onSubmit: (String?) -> Void   // nil / 空字符串 → 删除

    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String

    init(instrumentID: String, initialNote: String, onSubmit: @escaping (String?) -> Void) {
        self.instrumentID = instrumentID
        self.initialNote = initialNote
        self.onSubmit = onSubmit
        self._noteText = State(initialValue: initialNote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📝 \(instrumentID) 备注").font(.title2).bold()
            Text("trader 个人笔记 · 跨日跨周保留 · 跨窗口同步 · 全 instrument 共享一条")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $noteText)
                .font(.system(.body, design: .default))
                .frame(width: 460, height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .background(Color.gray.opacity(0.05))

            HStack {
                Text("\(noteText.trimmingCharacters(in: .whitespacesAndNewlines).count) 字 · 留空将删除备注")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSubmit(noteText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 320)
    }
}

// MARK: - Sheet · 快速粘贴合约（v15.20 batch55 · QuickPasteParser 入口）

private struct QuickPasteSheet: View {

    let groups: [Watchlist]
    let defaultGroupID: UUID?
    /// (粘贴文本, 选中分组 ID 或 nil 代表新建, 新建分组名 nil 代表用默认 "粘贴导入")
    let onSubmit: (String, UUID?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var targetGroupID: UUID?
    @State private var createNewGroup: Bool = false
    @State private var newGroupName: String = ""

    init(
        groups: [Watchlist],
        defaultGroupID: UUID?,
        initialText: String = "",
        onSubmit: @escaping (String, UUID?, String?) -> Void
    ) {
        self.groups = groups
        self.defaultGroupID = defaultGroupID
        self.onSubmit = onSubmit
        self._text = State(initialValue: initialText)
        self._targetGroupID = State(initialValue: defaultGroupID)
        self._createNewGroup = State(initialValue: groups.isEmpty)
    }

    /// 实时解析预览（前 8 个 + 计数）· 输入空时空数组
    private var parsedPreview: [String] {
        QuickPasteParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速粘贴合约").font(.title2).bold()
            Text("支持任意分隔符：换行 / 空格 / 逗号（中英）/ 分号 / 顿号 / Tab · 行尾 # 注释剥离 · 数字自动过滤")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $text)
                .font(.system(size: 13 + chartFontSize.sizeDelta, design: .monospaced))
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4), lineWidth: 1))

            // 实时解析预览
            HStack(spacing: 6) {
                Text("解析：").foregroundColor(.secondary).font(.caption)
                if parsedPreview.isEmpty {
                    Text("（空 · 输入或粘贴合约代码）").foregroundColor(.secondary).font(.caption)
                } else {
                    Text("\(parsedPreview.count) 个 · ").font(.caption)
                    Text(parsedPreview.prefix(8).joined(separator: ", "))
                        .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if parsedPreview.count > 8 {
                        Text("…").foregroundColor(.secondary).font(.caption)
                    }
                }
            }

            Form {
                Toggle("新建分组（不勾则追加到现有分组）", isOn: $createNewGroup)
                    .disabled(groups.isEmpty)
                if createNewGroup {
                    TextField("新分组名（留空 → 粘贴导入）", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("目标分组", selection: $targetGroupID) {
                        ForEach(groups) { g in
                            Text(g.name).tag(Optional(g.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("确认添加 (\(parsedPreview.count) 个)") {
                    let groupID: UUID? = createNewGroup ? nil : targetGroupID
                    let groupName: String? = createNewGroup ? newGroupName : nil
                    onSubmit(text, groupID, groupName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedPreview.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}

// MARK: - Mock 数据（commit 1 静态 · commit 4 + M5 替换）

private enum MockWatchlistBook {
    /// v15.26 行情列表大补全 · 11 类目分组（黑色/有色/贵金属/农产品/油脂/化工/能化/软商品/股指/国债/新能源）
    /// 派生自 ChineseFuturesProducts.byCategory · 60+ 品种主连续合约 · 按用户视角分类
    /// 双击任意合约可直接切主图 · 全部 ∈ supportedContracts
    static func generate() -> WatchlistBook {
        var book = WatchlistBook()
        let now = Date()

        // 11 类目顺序：用户最常看的在前
        let categoryOrder: [ChineseFuturesProducts.Category] = [
            .黑色, .有色, .贵金属, .能化, .化工, .油脂, .农产品, .软商品, .股指, .国债, .新能源
        ]

        for category in categoryOrder {
            guard let entries = ChineseFuturesProducts.byCategory[category], !entries.isEmpty else { continue }
            let groupID = book.addGroup(name: category.rawValue, now: now).id
            // 每品种主连续合约（X0）· 视角更稳定 · 不会跨期切换
            for entry in entries {
                let id = entry.productID.uppercased() + "0"
                book.addInstrument(id, to: groupID, now: now)
            }
        }

        // 经典「主力月份」组 · 保留传统盯盘视角（贴近真实持仓 · 半年自动续期）
        let mainMonthIDs = ChineseFuturesProducts.allDominantMonthIDs
        if !mainMonthIDs.isEmpty {
            let mainGroupID = book.addGroup(name: "主力月份", now: now).id
            // 仅保留用户最熟悉的 8 个核心品种主力月（避免 60+ 一次铺满）
            let coreProducts = ["rb", "i", "j", "cu", "au", "ag", "m", "IF"]
            for productID in coreProducts {
                if let dominantID = DominantMonthCalculator.dominantContract(prefix: productID) {
                    book.addInstrument(dominantID, to: mainGroupID, now: now)
                }
            }
        }

        return book
    }
}

private enum MockQuote {
    /// 静态 Mock 行情 · commit 4 起替换为 NotificationCenter 推送的真实数据流
    /// 涨跌幅约定：正数前缀 "+" · 负数自带 "-" · 颜色由 hasPrefix("-") 判定
    /// v15.26 行情列表大补全 · 60+ 品种主连续 mock 报价（接 CTP 真行情后整段废弃）
    private static let table: [String: (price: String, changePct: String, openInt: String)] = [
        // 黑色
        "RB0": ("3245",   "+1.21%", "1.2M"),
        "HC0": ("3450",   "-0.32%", "850K"),
        "I0":  ("812.5",  "+1.78%", "640K"),
        "J0":  ("1925",   "+0.45%", "320K"),
        "JM0": ("1180",   "-0.78%", "280K"),
        "SF0": ("6420",   "+0.32%",  "85K"),
        "SM0": ("6180",   "-0.55%",  "92K"),
        // 有色
        "CU0": ("78650",  "+2.05%", "150K"),
        "AL0": ("19450",  "+0.85%", "240K"),
        "ZN0": ("23150",  "-0.65%", "180K"),
        "PB0": ("17320",  "+0.32%",  "65K"),
        "SN0": ("215800", "+1.45%",  "32K"),
        "NI0": ("125400", "-1.20%",  "78K"),
        "SS0": ("13280",  "-0.42%", "120K"),
        "BC0": ("69820",  "+1.85%",  "45K"),
        // 贵金属
        "AU0": ("612.5",  "+0.83%", "320K"),
        "AG0": ("7890",   "+1.45%", "560K"),
        // 能化
        "SC0": ("485.2",  "+1.92%", "180K"),
        "LU0": ("3520",   "+0.85%",  "65K"),
        "NR0": ("11250",  "-0.45%",  "85K"),
        "FU0": ("3145",   "+1.32%", "240K"),
        "BU0": ("3680",   "-0.28%",  "92K"),
        "RU0": ("13420",  "+0.65%", "180K"),
        "SP0": ("5840",   "-0.85%", "120K"),
        // 化工
        "L0":  ("8350",   "+0.45%", "180K"),
        "PP0": ("7820",   "-0.32%", "240K"),
        "V0":  ("5640",   "+0.85%", "320K"),
        "EG0": ("4520",   "-0.65%", "180K"),
        "EB0": ("8945",   "+1.20%",  "85K"),
        "PG0": ("4820",   "+0.45%",  "92K"),
        "TA0": ("5680",   "-0.85%", "240K"),
        "MA0": ("2485",   "+0.65%", "180K"),
        "FG0": ("1320",   "-1.15%", "320K"),
        "SA0": ("1620",   "+0.95%", "240K"),
        "UR0": ("1780",   "-0.45%", "180K"),
        "PX0": ("7220",   "+1.45%",  "65K"),
        "SH0": ("2280",   "+0.85%",  "45K"),
        "PR0": ("6450",   "-0.65%",  "32K"),
        // 油脂
        "M0":  ("3180",   "+0.65%", "560K"),
        "Y0":  ("8240",   "+1.05%", "320K"),
        "P0":  ("8920",   "+1.45%", "180K"),
        "OI0": ("9180",   "+0.85%", "120K"),
        "RM0": ("2820",   "+0.32%", "240K"),
        // 农产品
        "A0":  ("4280",   "-0.45%", "180K"),
        "B0":  ("3850",   "+0.32%",  "65K"),
        "C0":  ("2380",   "+0.85%", "320K"),
        "CS0": ("2780",   "-0.65%", "180K"),
        "JD0": ("3420",   "+1.20%", "120K"),
        // 软商品
        "SR0": ("6420",   "-0.85%", "240K"),
        "CF0": ("14580",  "+0.45%", "180K"),
        "AP0": ("8240",   "+1.65%", "120K"),
        "CJ0": ("12380",  "-0.85%",  "45K"),
        "PK0": ("8920",   "+0.65%",  "85K"),
        // 股指
        "IF0": ("3856.4", "-0.45%", "180K"),
        "IH0": ("2820.8", "-0.65%", "120K"),
        "IC0": ("5680.2", "+0.85%", "150K"),
        "IM0": ("6420.5", "+1.20%",  "92K"),
        // 国债
        "T0":  ("104.85", "+0.08%",  "85K"),
        "TF0": ("103.42", "+0.05%",  "65K"),
        "TS0": ("101.85", "+0.02%",  "45K"),
        "TL0": ("108.20", "+0.15%",  "32K"),
        // 新能源
        "SI0": ("12480",  "+0.85%",  "85K"),
        "LC0": ("82500",  "+1.45%",  "65K"),
    ]

    static func price(for id: String) -> String { table[id]?.price ?? "—" }
    static func changePct(for id: String) -> String { table[id]?.changePct ?? "—" }
    static func openInterest(for id: String) -> String { table[id]?.openInt ?? "—" }
}

#endif
