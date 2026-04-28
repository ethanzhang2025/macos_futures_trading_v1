// MainApp · 自选合约面板（WP-43 UI · commit 2/4 · 添加/删除/重命名分组与合约）
//
// commit 1 已交付：NavigationSplitView 双栏 · WatchlistBook 真模型 · Mock 3 组 9 合约
// commit 2 本次新增：
// - 左 sidebar 顶部 "+" 添加分组（⌘⇧G）· 行右键菜单（重命名 / 删除）
// - 右 detail header "+" 添加合约（⌘⇧I）· Table 多选右键菜单（从分组移除）
// - GroupNameSheet（add / rename 共用）· InstrumentIDSheet
// - 删除分组前 confirmationDialog 提示（含级联清空合约的警示）
// - 切换分组时清空 Table 选中
//
// 留给后续 commit：
// - commit 3/4：拖拽排序（macOS 13+ .draggable / .dropDestination · 同组重排 + 跨组移动）
// - commit 4/4：主图联动（双击合约 → openWindow(id: "chart") + NotificationCenter 切合约）
//
// 留待 M5：StoreManager 注入 SQLiteWatchlistBookStore · 替换 Mock 真持久化数据

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared

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

// MARK: - 主窗口

struct WatchlistWindow: View {

    @State private var book: WatchlistBook = MockWatchlistBook.generate()
    @State private var selectedGroupID: UUID?
    @State private var sheetState: WatchlistSheetState?
    @State private var pendingDeleteGroup: Watchlist?
    @State private var selectedInstruments: Set<String> = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 480, idealHeight: 600)
        .onAppear {
            if selectedGroupID == nil {
                selectedGroupID = book.groups.first?.id
            }
        }
        .onChange(of: selectedGroupID) { _ in
            selectedInstruments.removeAll()
        }
        .sheet(item: $sheetState) { state in
            switch state {
            case .addGroup:
                GroupNameSheet(
                    title: "添加分组",
                    initialName: "",
                    actionLabel: "保存"
                ) { name in
                    addGroup(name: name)
                }
            case .renameGroup(let group):
                GroupNameSheet(
                    title: "重命名分组",
                    initialName: group.name,
                    actionLabel: "更新"
                ) { name in
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
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteGroup != nil },
            set: { if !$0 { pendingDeleteGroup = nil } }
        )
    }

    // MARK: - 左栏 · 分组列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("自选分组")
                    .font(.headline)
                Spacer()
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

            List(selection: $selectedGroupID) {
                ForEach(book.groups) { group in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text("\(group.instrumentIDs.count) 个合约")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(group.id as UUID?)
                    .contextMenu {
                        Button("重命名") {
                            sheetState = .renameGroup(group)
                        }
                        Divider()
                        Button("删除分组", role: .destructive) {
                            pendingDeleteGroup = group
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - 右栏 · 合约表

    @ViewBuilder
    private var detail: some View {
        if let groupID = selectedGroupID, let group = book.group(id: groupID) {
            instrumentList(for: group)
        } else {
            emptyState(
                icon: "list.bullet.rectangle",
                title: "未选择分组",
                hint: "在左侧选择一个自选分组以查看合约"
            )
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

            if group.instrumentIDs.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "分组为空",
                    hint: "点击右上「添加合约」开始"
                )
            } else {
                instrumentTable(for: group)
            }

            Divider()

            footerHint
        }
    }

    private func instrumentTable(for group: Watchlist) -> some View {
        Table(group.instrumentIDs, id: \.self, selection: $selectedInstruments) {
            TableColumn("合约") { id in
                Text(id)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .width(min: 90, ideal: 110)

            TableColumn("最新价") { id in
                Text(MockQuote.price(for: id))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 80, ideal: 100)

            TableColumn("涨跌幅") { id in
                let change = MockQuote.changePct(for: id)
                Text(change)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(change.hasPrefix("-") ? .green : .red)
            }
            .width(min: 80, ideal: 100)

            TableColumn("持仓量") { id in
                Text(MockQuote.openInterest(for: id))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let label = removeMenuLabel(for: ids) {
                Button(label, role: .destructive) {
                    removeInstruments(ids, from: group.id)
                }
            }
        }
    }

    private func removeMenuLabel(for ids: Set<String>) -> String? {
        guard let first = ids.first else { return nil }
        if ids.count == 1 {
            return "从分组移除「\(first)」"
        }
        return "从分组移除选中的 \(ids.count) 个合约"
    }

    private var footerHint: some View {
        HStack {
            Text("Mock 数据 · 待 M5 接真实行情 + commit 4 主图联动")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            if !selectedInstruments.isEmpty {
                Text("已选 \(selectedInstruments.count) 个 · 右键移除")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.title3)
                .foregroundColor(.secondary)
            Text(hint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Mutations

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
            Text(title)
                .font(.title2)
                .bold()

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
            Text("添加合约到「\(groupName)」")
                .font(.title2)
                .bold()

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

// MARK: - Mock 数据（commit 1 静态 · commit 4 + M5 替换）

private enum MockWatchlistBook {
    /// 3 组 9 合约 · 与 Stubs.swift 旧占位文案对齐
    /// 主力 RB0/IF0/AU0 三个 ∈ MarketDataPipeline.supportedContracts，commit 4 主图联动可直接生效
    static func generate() -> WatchlistBook {
        var book = WatchlistBook()
        let now = Date()
        let groups: [(name: String, ids: [String])] = [
            ("主力合约", ["RB0", "IF0", "AU0"]),
            ("黑色系",   ["RB0", "HC0", "I0"]),
            ("贵金属",   ["AU0", "AG0", "CU0"])
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
