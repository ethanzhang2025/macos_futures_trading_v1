// WP-42 v13.16 · 画线模板（保存常用 → 一键插入）· v15.19 batch39 加 category 分类
//
// 模板存全局（不按 instrumentID/period 隔离）· 跨合约复用
// 模板内嵌 Drawing 完整快照（含锚点 + 样式 + 文字 + offset 等）
// 应用模板时由调用方负责锚点重定位（barIndex/price 从原始上下文不一定适合新合约）

import Foundation

/// 画线模板分类（trader 多模板时按用途归类 · UI 按分类分组）
public enum DrawingTemplateCategory: String, Sendable, Codable, CaseIterable {
    case trend       // 趋势线 / 通道
    case keyLevel    // 关键位（前高 / 前低 / 整数关口）
    case channel     // 平行通道 / 黄金分割
    case annotation  // 文字注解 / 标签
    case custom      // 自定义（默认）

    public var displayName: String {
        switch self {
        case .trend:      return "趋势"
        case .keyLevel:   return "关键位"
        case .channel:    return "通道"
        case .annotation: return "注解"
        case .custom:     return "自定义"
        }
    }
}

/// 画线模板（保存常用画线为可复用模板）
public struct DrawingTemplate: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    /// 用户自定义名称（如"前高阻力位"/"通道交叉"）
    public var name: String
    /// 模板内嵌画线（含 type / 锚点 / 样式 / 文字 / fontSize / strokeColorHex 等）
    public var drawing: Drawing
    /// 创建时间（UI 排序用 · 最新在前）
    public var createdAt: Date
    /// v15.19 batch39 · 用户指定的分类（默认 .custom · 旧 JSON 缺字段 fallback custom）
    public var category: DrawingTemplateCategory

    public init(
        id: UUID = UUID(),
        name: String,
        drawing: Drawing,
        createdAt: Date = Date(),
        category: DrawingTemplateCategory = .custom
    ) {
        self.id = id
        self.name = name
        self.drawing = drawing
        self.createdAt = createdAt
        self.category = category
    }

    // MARK: - Codable · category 旧 JSON fallback custom

    private enum CodingKeys: String, CodingKey {
        case id, name, drawing, createdAt, category
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.drawing = try c.decode(Drawing.self, forKey: .drawing)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.category = try c.decodeIfPresent(DrawingTemplateCategory.self, forKey: .category) ?? .custom
    }
}
