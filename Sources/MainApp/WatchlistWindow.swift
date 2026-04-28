// MainApp · 自选合约面板（WP-43 UI · commit 1/4 · ⌘L 起步）
//
// 起步版职责：
// - 替换 Stubs.swift 占位 · 接 WatchlistBook 真数据模型
// - NavigationSplitView 双栏：左分组 · 右合约表
// - Mock 3 组 9 合约 · 暂不接真实行情/持久化
//
// 留给后续 commit：
// - commit 2/4：添加/删除分组与合约 + 重命名（顶部 + / 右键菜单 / sheet 表单）
// - commit 3/4：拖拽排序（macOS 13+ .draggable / .dropDestination · 同组重排 + 跨组移动）
// - commit 4/4：主图联动（双击合约 → openWindow(id: "chart") + NotificationCenter 切合约）
//
// 留待 M5：StoreManager 注入 SQLiteWatchlistBookStore · 替换 Mock 真持久化数据

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared

struct WatchlistWindow: View {

    @State private var book: WatchlistBook = MockWatchlistBook.generate()
    @State private var selectedGroupID: UUID?

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
    }

    // MARK: - 左栏 · 分组列表

    private var sidebar: some View {
        List(selection: $selectedGroupID) {
            Section("自选分组") {
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
                }
            }
        }
        .listStyle(.sidebar)
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
                Text("commit 1/4 · ⌘L 起步")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(16)

            Divider()

            if group.instrumentIDs.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "分组为空",
                    hint: "（待 commit 2 添加合约入口）"
                )
            } else {
                Table(group.instrumentIDs, id: \.self) {
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
            }

            Divider()

            HStack {
                Text("Mock 数据 · 待 M5 接真实行情 + commit 4 主图联动")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
