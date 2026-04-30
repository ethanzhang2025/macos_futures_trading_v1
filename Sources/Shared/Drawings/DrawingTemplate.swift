// WP-42 v13.16 · 画线模板（保存常用 → 一键插入）
//
// 模板存全局（不按 instrumentID/period 隔离）· 跨合约复用
// 模板内嵌 Drawing 完整快照（含锚点 + 样式 + 文字 + offset 等）
// 应用模板时由调用方负责锚点重定位（barIndex/price 从原始上下文不一定适合新合约）

import Foundation

/// 画线模板（保存常用画线为可复用模板）
public struct DrawingTemplate: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    /// 用户自定义名称（如"前高阻力位"/"通道交叉"）
    public var name: String
    /// 模板内嵌画线（含 type / 锚点 / 样式 / 文字 / fontSize / strokeColorHex 等）
    public var drawing: Drawing
    /// 创建时间（UI 排序用 · 最新在前）
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        drawing: Drawing,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.drawing = drawing
        self.createdAt = createdAt
    }
}
