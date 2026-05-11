// MainApp · Shell · v17.0 PoC Step 1
// 用户工作台模型（Codable · 二级 Tab 单位）
// 一个 Workspace = 一个命名工作台快照（如"早盘"/"日内"/"夜盘"）
// 持久化到 @AppStorage shell.workspaces JSON

import Foundation

public struct Workspace: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String                // "早盘" / "日内" / "夜盘"
    public var primaryTab: PrimaryTab      // 隶属哪个一级模块
    public var paneLayout: PaneLayout      // 切分配置
    public var panes: [PaneConfig]         // 各 Pane 内容
    public var createdAt: Date
    public var lastUsedAt: Date

    public init(id: UUID = UUID(),
                name: String,
                primaryTab: PrimaryTab,
                paneLayout: PaneLayout,
                panes: [PaneConfig],
                createdAt: Date = Date(),
                lastUsedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.primaryTab = primaryTab
        self.paneLayout = paneLayout
        self.panes = panes
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 默认 3 个 workspace 模板（首次启动 / 空配置时加载）
    public static func defaults() -> [Workspace] {
        let now = Date()
        return [
            Workspace(
                name: "白天 看盘",
                primaryTab: .watching,
                paneLayout: .single,
                panes: [PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m")],
                createdAt: now, lastUsedAt: now
            ),
            Workspace(
                name: "夜盘 多周期",
                primaryTab: .watching,
                paneLayout: .twoHorizontal,
                panes: [
                    PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "5m", groupColor: .blue),
                    PaneConfig(kind: .chart, symbol: "rb2510", periodRaw: "1H", groupColor: .blue),
                ],
                createdAt: now, lastUsedAt: now
            ),
            Workspace(
                name: "复盘",
                primaryTab: .review,
                paneLayout: .twoHorizontal,
                panes: [
                    PaneConfig(kind: .review),
                    PaneConfig(kind: .journal),
                ],
                createdAt: now, lastUsedAt: now
            ),
        ]
    }
}
