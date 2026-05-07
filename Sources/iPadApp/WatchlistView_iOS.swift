// WatchlistView_iOS · iPad 自选列表（WP-61 batch003）
//
// 设计：
//   - sidebar List 显示 WatchlistBook 的全部 group · Section 分组
//   - 每个 group 内的合约用 NavigationLink-like row · 选中态绑定 selection: instrumentID
//   - long-press 删除合约（contextMenu）· swipe 也可
//   - 加分组 / 加合约 通过 toolbar + button（batch005 集成）
//
// 数据源：
//   - @ObservedObject WatchlistViewModel 持有 WatchlistBook
//   - load: 异步从 store 拉
//   - save: 改动时持久化（WatchlistBookStore）
//   - sync 由 batch006 SyncCoordinator 触发
//
// 占位策略：
//   - 首次启动 store 为空 → 用 demoSeed() 注入 3 分组 demo 数据 · 让 UI 立刻可看
//   - 真实持久化由 Mac 端创建数据 → CloudKit 同步过来（batch006）

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import Shared

@MainActor
final class WatchlistViewModel: ObservableObject {
    @Published var book: WatchlistBook = .init()
    private let store: any WatchlistBookStore

    init(store: any WatchlistBookStore = InMemoryWatchlistBookStore(initial: WatchlistViewModel.demoSeed())) {
        self.store = store
    }

    func load() async {
        do {
            if let loaded = try await store.load() {
                self.book = loaded
            } else {
                self.book = WatchlistViewModel.demoSeed()
                try? await store.save(self.book)
            }
        } catch {
            self.book = WatchlistViewModel.demoSeed()
        }
    }

    func addInstrument(_ id: String, to groupID: UUID) async {
        _ = book.addInstrument(id, to: groupID)
        try? await store.save(book)
    }

    func removeInstrument(_ id: String, from groupID: UUID) async {
        _ = book.removeInstrument(id, from: groupID)
        try? await store.save(book)
    }

    func renameGroup(_ id: UUID, to newName: String) async {
        _ = book.renameGroup(id: id, to: newName)
        try? await store.save(book)
    }

    static func demoSeed() -> WatchlistBook {
        var b = WatchlistBook()
        let g1 = b.addGroup(name: "黑色板块")
        _ = b.addInstrument("rb0", to: g1.id)
        _ = b.addInstrument("hc0", to: g1.id)
        _ = b.addInstrument("i0", to: g1.id)
        let g2 = b.addGroup(name: "贵金属")
        _ = b.addInstrument("au0", to: g2.id)
        _ = b.addInstrument("ag0", to: g2.id)
        let g3 = b.addGroup(name: "有色")
        _ = b.addInstrument("cu0", to: g3.id)
        _ = b.addInstrument("al0", to: g3.id)
        _ = b.addInstrument("zn0", to: g3.id)
        return b
    }
}

struct WatchlistView_iOS: View {

    @StateObject private var viewModel = WatchlistViewModel()
    @Binding var selection: String?
    @State private var renamingGroupID: UUID? = nil
    @State private var newGroupName: String = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(viewModel.book.groups.filter { $0.deletedAt == nil }) { group in
                Section {
                    ForEach(group.instrumentIDs, id: \.self) { instrumentID in
                        WatchlistRow(instrumentID: instrumentID)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeInstrument(instrumentID, from: group.id) }
                                } label: {
                                    Label("从分组移除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeInstrument(instrumentID, from: group.id) }
                                } label: {
                                    Label("移除", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("\(group.name)（\(group.instrumentIDs.count)）")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            renamingGroupID = group.id
                            newGroupName = group.name
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .task { await viewModel.load() }
        .sheet(isPresented: Binding(
            get: { renamingGroupID != nil },
            set: { if !$0 { renamingGroupID = nil } }
        )) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                TextField("分组名称", text: $newGroupName)
            }
            .navigationTitle("重命名分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { renamingGroupID = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let id = renamingGroupID, !newGroupName.isEmpty {
                            Task {
                                await viewModel.renameGroup(id, to: newGroupName)
                                renamingGroupID = nil
                            }
                        }
                    }
                    .disabled(newGroupName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct WatchlistRow: View {
    let instrumentID: String

    var body: some View {
        HStack {
            Text(instrumentID.uppercased())
                .font(.body)
                .monospaced()
            Spacer()
            // batch008 替换为实时报价
            Text("--.--")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#endif
