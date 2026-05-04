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

    /// v12.17 文华自选导入预览（NSOpenPanel 选 .txt 解析后 · 用户确认前的 holding 状态）
    @State private var importPreview: ImportPreview?

    /// v15.20 batch55 · 自由粘贴合约 sheet 显隐（文本框 + 分组选择 + 实时解析预览）
    @State private var showQuickPasteSheet: Bool = false
    /// v15.21 batch91 · CSV 导入 sheet 预填文本（importWatchlistFromFile 把 .csv 内容塞进去 · 复用 QuickPasteSheet）
    @State private var quickPasteInitialText: String = ""
    /// v15.21 batch101 · 聚合视图合约搜索（lowercased contains · 不区分大小写 · 空字符串跳过过滤）
    @State private var aggregatedSearchText: String = ""
    @FocusState private var isAggregatedSearchFocused: Bool

    /// v15.20 batch59 · 排序字段（v15.20 batch60 · @AppStorage 持久化 · 重启保留）
    /// 默认 .manual 保持用户拖拽顺序 · 反序失败 fallback .manual
    @AppStorage("viewState.v1.watchlist.sortFieldRaw") private var sortFieldRaw: String = WatchlistSortField.manual.rawValue
    @AppStorage("viewState.v1.watchlist.sortAscending") private var sortAscending: Bool = false

    /// v15.20 batch61/76 · 跨分组聚合视图（trader 涨幅榜扫盘 · 不用切分组找涨幅大的）
    /// v15.20 batch76 · @AppStorage 持久化（重启保留 · trader 习惯使用聚合扫盘）
    @AppStorage("viewState.v1.watchlist.showAllAggregated") private var showAllAggregated: Bool = false

    /// 解析 sortField · raw 不合法 fallback .manual（写入用 setSortField）
    private var sortField: WatchlistSortField {
        WatchlistSortField(rawValue: sortFieldRaw) ?? .manual
    }
    private func setSortField(_ field: WatchlistSortField) {
        sortFieldRaw = field.rawValue
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.storeManager) private var storeManager

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 480, idealHeight: 600)
        .animation(.easeInOut(duration: 0.22), value: book)
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
        }
        .onDisappear {
            quoteFetchTask?.cancel()
            quoteFetchTask = nil
        }
        .onChange(of: book) { newValue in
            // M5 自动持久化：每次 book 变化异步 save · isLoaded 守卫避免初始 Mock 误写覆盖真数据
            guard isLoaded, let store = storeManager?.watchlistBook else { return }
            Task { try? await store.save(newValue) }
        }
        .onChange(of: selectedGroupID) { _ in
            selectedInstruments.removeAll()
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

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("自选分组").font(.headline)
                Spacer()
                Button {
                    importWatchlistFromFile()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("导入自选合约（.txt 文华格式 · .csv 自由表格）")
                Button {
                    showQuickPasteSheet = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("快速粘贴合约（⌘⇧V · 任意分隔符）")
                .keyboardShortcut("v", modifiers: [.command, .shift])
                Button {
                    sheetState = .addGroup
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加分组（⌘⇧G）")
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
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
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
        return HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(.accentColor)
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
        let q = aggregatedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredIDs = q.isEmpty ? allIDs : allIDs.filter { $0.lowercased().contains(q) }
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
                        .help("清空搜索（Esc）")
                    }
                }
                Button("") { isAggregatedSearchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
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
                .help("按涨跌幅排序后取前 N · 一键创建涨/跌停预警 · 默认 paused 防触发风暴")
                Button("退出聚合视图") { showAllAggregated = false }
                    .buttonStyle(.borderless)
                    .help("回到分组视图")
            }
            .padding(16)

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
            Spacer().frame(width: 16)
            Text(openInterestText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
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
            // v15.21 batch97 · 复制合约代码 / 最新价（与单组 row 一致）
            Button("复制合约代码 \(id)") { Pasteboard.copy(id) }
            Button("复制最新价 \(priceText(for: id))") { Pasteboard.copy(priceText(for: id)) }
            Divider()
            Menu("📋 创建预警模板") {
                ForEach(AlertPreset.allCases) { preset in
                    Button(preset.displayName) {
                        createAlertPreset(preset, instrumentID: id)
                    }
                }
            }
        }
    }

    private func instrumentList(for group: Watchlist) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("· \(group.instrumentIDs.count) 合约")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    sheetState = .addInstrument(groupID: group.id, groupName: group.name)
                } label: {
                    Label("添加合约", systemImage: "plus")
                }
                .help("添加合约到「\(group.name)」（⌘⇧I）")
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            .padding(16)

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
            sortableHeaderCell("合约", field: .instrumentID, width: 100, alignment: .leading)
            sortableHeaderCell("最新价", field: .lastPrice, width: 90, alignment: .trailing)
            Spacer().frame(width: 16)
            sortableHeaderCell("涨跌幅", field: .changePct, width: 80, alignment: .trailing)
            Spacer().frame(width: 16)
            sortableHeaderCell("持仓量", field: .openInterest, width: 80, alignment: .trailing)
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
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
            .help("点击按\(title)排序 · 再点切升降序 · 拖拽行自动切回手动")
    }

    /// v15.20 batch59 · 按 sortField + sortAscending 排序合约 ID（quotes 不可达 fallback nil 排末尾）
    private func sortedInstrumentIDs(for group: Watchlist) -> [String] {
        WatchlistSorter.sort(
            ids: group.instrumentIDs,
            field: sortField,
            ascending: sortAscending,
            keyForID: keyForInstrument
        )
    }

    /// v15.20 batch59 · 数值字段 closure（同 sort field 提取规则）
    private func keyForInstrument(_ id: String) -> Double? {
        switch sortField {
        case .lastPrice:
            return quotes[id].map { NSDecimalNumber(decimal: $0.lastPrice).doubleValue }
        case .changePct:
            return parseChangePct(changePctText(for: id))
        case .openInterest:
            return quotes[id].map { Double($0.openInterest) }
        case .manual, .instrumentID:
            return nil   // sorter 不调 keyForID
        }
    }

    private func instrumentRow(id: String, index: Int, groupID: UUID) -> some View {
        let change = changePctText(for: id)
        let pctValue = parseChangePct(change)
        return HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 24)
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
            Spacer().frame(width: 16)
            Text(openInterestText(for: id))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Spacer()
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openInstrumentInChart(id)
        }
        .contextMenu {
            // v15.19 batch48 · 右键一键创建预警模板（联动 AlertPreset · 复用 alertAddedFromChart）
            Button("打开主图") { openInstrumentInChart(id) }
            // v15.21 batch97 · 复制合约代码 / 最新价（trader 报单 / 截单 高频粘贴）
            Button("复制合约代码 \(id)") {
                Pasteboard.copy(id)
            }
            Button("复制最新价 \(priceText(for: id))") {
                Pasteboard.copy(priceText(for: id))
            }
            Divider()
            Menu("📋 创建预警模板") {
                ForEach(AlertPreset.allCases) { preset in
                    Button(preset.displayName) {
                        createAlertPreset(preset, instrumentID: id)
                    }
                    .help(preset.helpText)
                }
                Divider()
                Button("全部 6 类一次创建") {
                    createAllAlertPresets(instrumentID: id)
                }
            }
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
        book.addInstrument(trimmed, to: groupID)
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
    private func importWatchlistFromFile() {
        let panel = NSOpenPanel()
        panel.title = "导入自选合约（.txt 文华格式 · .csv 自由表格）"
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

    /// 最新价文本 · 真值 fallback Mock
    private func priceText(for id: String) -> String {
        if let q = quotes[id] {
            return String(format: "%.2f", NSDecimalNumber(decimal: q.lastPrice).doubleValue)
        }
        return MockQuote.price(for: id)
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
                .font(.system(size: 13, design: .monospaced))
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
                        .font(.system(size: 11, design: .monospaced))
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
    /// 2 组共 8 合约 · 全部 ∈ MarketDataPipeline.supportedContracts · 双击任意合约可直接切主图
    /// 主力月份组：贴近用户真实持仓盯盘（rb2609 螺纹 / i2609 铁矿 / au2606 黄金 / IF2605 股指）
    /// 主连续组：跨多年合约连续 K 线分析（RB0/IF0/AU0/CU0）
    static func generate() -> WatchlistBook {
        var book = WatchlistBook()
        let now = Date()
        let groups: [(name: String, ids: [String])] = [
            ("主力月份", ["rb2609", "i2609", "au2606", "IF2605"]),
            ("主连续",   ["RB0", "IF0", "AU0", "CU0"])
        ]
        for (name, ids) in groups {
            let groupID = book.addGroup(name: name, now: now).id
            for id in ids {
                book.addInstrument(id, to: groupID, now: now)
            }
        }
        return book
    }
}

private enum MockQuote {
    /// 静态 Mock 行情 · commit 4 起替换为 NotificationCenter 推送的真实数据流
    /// 涨跌幅约定：正数前缀 "+" · 负数自带 "-" · 颜色由 hasPrefix("-") 判定
    private static let table: [String: (price: String, changePct: String, openInt: String)] = [
        "RB0": ("3245",   "+1.21%", "1.2M"),
        "IF0": ("3856.4", "-0.45%", "180K"),
        "AU0": ("612.5",  "+0.83%", "320K"),
        "CU0": ("78650",  "+2.05%", "150K"),
        "HC0": ("3450",   "-0.32%", "850K"),
        "I0":  ("812.5",  "+1.78%", "640K"),
        "AG0": ("7890",   "+1.45%", "560K")
    ]

    static func price(for id: String) -> String { table[id]?.price ?? "—" }
    static func changePct(for id: String) -> String { table[id]?.changePct ?? "—" }
    static func openInterest(for id: String) -> String { table[id]?.openInt ?? "—" }
}

#endif
