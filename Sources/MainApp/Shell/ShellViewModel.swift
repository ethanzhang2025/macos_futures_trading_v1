// MainApp · Shell · v17.0 PoC Step 1
// Shell 主 ViewModel · @MainActor ObservableObject
// 持有所有 Shell 级状态（primaryTab / workspaces / layout / groupBindings）
// 持久化到 @AppStorage JSON

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import Foundation

@MainActor
public final class ShellViewModel: ObservableObject {

    // MARK: - 一级模块

    @Published public var primaryTab: PrimaryTab = .watching {
        didSet { persistPrimaryTab() }
    }

    // MARK: - 二级 Tab（Workspace）

    @Published public var workspaces: [Workspace] = []
    @Published public var activeWorkspaceID: UUID? = nil {
        didSet { persistActiveWorkspaceID() }
    }

    public var activeWorkspace: Workspace? {
        guard let id = activeWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    // MARK: - 布局状态

    @Published public var layout: ShellLayout = ShellLayout() {
        didSet { persistLayout() }
    }

    // MARK: - 彩色 group 联动（v17.1 实装 · Step 1 占位）

    @Published public var groupBindings: [GroupColor: SymbolBinding] = [:]

    // MARK: - 初始化

    public init() {
        loadFromStorage()
    }

    // MARK: - Workspace 操作

    public func newWorkspace(name: String? = nil) {
        let count = workspaces.filter { $0.primaryTab == primaryTab }.count
        let defaultName = name ?? "\(primaryTab.displayName) \(count + 1)"
        let ws = Workspace(
            name: defaultName,
            primaryTab: primaryTab,
            paneLayout: .single,
            panes: [PaneConfig(kind: primaryTab.defaultPaneKind)]
        )
        workspaces.append(ws)
        activeWorkspaceID = ws.id
        persistWorkspaces()
    }

    public func closeWorkspace(_ id: UUID) {
        guard workspaces.count > 1 else { return }  // 至少保留 1 个
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id {
            activeWorkspaceID = workspaces.first?.id
        }
        persistWorkspaces()
    }

    public func renameWorkspace(_ id: UUID, to newName: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].name = newName
        persistWorkspaces()
    }

    /// 切到指定 workspace（更新 lastUsedAt）
    public func activate(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].lastUsedAt = Date()
        activeWorkspaceID = id
        primaryTab = workspaces[idx].primaryTab
        persistWorkspaces()
    }

    /// 修改当前 active workspace 的 PaneLayout · 自动调整 panes 数组
    public func setPaneLayout(_ layout: PaneLayout) {
        guard let id = activeWorkspaceID,
              let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].paneLayout = layout
        let target = layout.paneCount
        if target > 0 {
            let current = workspaces[idx].panes.count
            if target > current {
                // 补默认 Pane
                let defaultKind = workspaces[idx].primaryTab.defaultPaneKind
                for _ in 0..<(target - current) {
                    workspaces[idx].panes.append(PaneConfig(kind: defaultKind))
                }
            } else if target < current {
                workspaces[idx].panes = Array(workspaces[idx].panes.prefix(target))
            }
        }
        persistWorkspaces()
    }

    // MARK: - 持久化

    private static let kWorkspaces = "shell.v1.workspaces"
    private static let kActiveID = "shell.v1.activeWorkspaceID"
    private static let kPrimaryTab = "shell.v1.primaryTab"
    private static let kLayout = "shell.v1.layout"

    private func loadFromStorage() {
        let ud = UserDefaults.standard
        // workspaces
        if let data = ud.data(forKey: Self.kWorkspaces),
           let arr = try? JSONDecoder().decode([Workspace].self, from: data),
           !arr.isEmpty {
            workspaces = arr
        } else {
            workspaces = Workspace.defaults()
        }
        // active workspace
        if let s = ud.string(forKey: Self.kActiveID),
           let id = UUID(uuidString: s),
           workspaces.contains(where: { $0.id == id }) {
            activeWorkspaceID = id
        } else {
            activeWorkspaceID = workspaces.first?.id
        }
        // primary tab
        if let raw = ud.string(forKey: Self.kPrimaryTab),
           let tab = PrimaryTab(rawValue: raw) {
            primaryTab = tab
        } else if let ws = activeWorkspace {
            primaryTab = ws.primaryTab
        }
        // layout
        if let data = ud.data(forKey: Self.kLayout),
           let l = try? JSONDecoder().decode(ShellLayout.self, from: data) {
            layout = l
        }
    }

    private func persistWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: Self.kWorkspaces)
        }
    }

    private func persistActiveWorkspaceID() {
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: Self.kActiveID)
    }

    private func persistPrimaryTab() {
        UserDefaults.standard.set(primaryTab.rawValue, forKey: Self.kPrimaryTab)
    }

    private func persistLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: Self.kLayout)
        }
    }
}

#endif
