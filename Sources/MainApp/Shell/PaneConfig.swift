// MainApp · Shell · v17.0 PoC Step 1
// 单个 Pane 配置（Codable · Workspace 的子结构）
// 持久化到 @AppStorage JSON · 启动时还原
// 注意：period 用 String 存（KLinePeriod.rawValue · 解耦 Shell 与 Shared 类型）

import Foundation

public struct PaneConfig: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: PaneKind
    public var symbol: String?      // 绑定合约（nil = Pane 默认 / 自选首个）
    public var periodRaw: String?   // KLinePeriod.rawValue 字符串
    public var groupColor: GroupColor?  // 彩色 group · nil = 不联动
    public var extraJSON: Data?     // view-specific 配置（指标参数 / 自选 ID 等）

    public init(id: UUID = UUID(),
                kind: PaneKind,
                symbol: String? = nil,
                periodRaw: String? = nil,
                groupColor: GroupColor? = nil,
                extraJSON: Data? = nil) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.periodRaw = periodRaw
        self.groupColor = groupColor
        self.extraJSON = extraJSON
    }
}
