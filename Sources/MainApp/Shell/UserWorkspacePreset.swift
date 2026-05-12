// MainApp · Shell · v17.81 · 用户自定义 Workspace 预设
// trader 把当前 Workspace 一键存为可复用模板 · UserDefaults 持久化
// 与内置 WorkspacePreset enum（5 个）并列 · ⌘K + PickerSheet 双入口

import Foundation

public struct UserWorkspacePreset: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var primaryTab: PrimaryTab
    public var paneLayout: PaneLayout
    public var panes: [PaneConfig]
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String,
                emoji: String = "🎯",
                primaryTab: PrimaryTab,
                paneLayout: PaneLayout,
                panes: [PaneConfig],
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.primaryTab = primaryTab
        self.paneLayout = paneLayout
        self.panes = panes
        self.createdAt = createdAt
    }

    public init(from workspace: Workspace, name: String, emoji: String) {
        self.init(
            name: name,
            emoji: emoji,
            primaryTab: workspace.primaryTab,
            paneLayout: workspace.paneLayout,
            panes: workspace.panes.map { p in
                var np = p
                np.id = UUID()
                return np
            }
        )
    }

    public func toWorkspace() -> Workspace {
        let now = Date()
        return Workspace(
            name: "\(emoji) \(name)",
            primaryTab: primaryTab,
            paneLayout: paneLayout,
            panes: panes.map { p in
                var np = p
                np.id = UUID()
                return np
            },
            createdAt: now,
            lastUsedAt: now
        )
    }

    public var subtitle: String {
        "\(paneLayout.displayName) · \(panes.count) Pane"
    }
}
