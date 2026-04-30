// WP-55 · 工作区模板 v1 数据模型层
// 多窗口布局 + 多套模板（盘前/盘中/盘后/自定义）+ 快捷键映射数据 + CloudKit 字段映射预埋
// 纯 value type 设计；不 import SwiftUI/AppKit/CoreGraphics/CloudKit，保持 Sources/Shared 跨端可移植
// UI 切换动画/键盘绑定/CGRect 桥接 → 留给后续 UI WP；CloudKit 实际同步 → 留 A12（M7-M9）

import Foundation

// MARK: - 跨端 Rect

/// 跨端布局矩形（不依赖 CGRect/NSRect，Linux 也能用）
/// UI 层负责与 CGRect/NSRect 桥接（cgRect 计算属性留 UI WP 决定）
public struct LayoutFrame: Sendable, Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = LayoutFrame(x: 0, y: 0, width: 0, height: 0)
}

// MARK: - 快捷键数据表示

/// 快捷键的纯数据表示（不绑定具体平台键码常量）
/// keyCode: macOS Carbon kVK_xxx；modifiers: NSEvent.ModifierFlags rawValue
/// 数据模型层只承担"存什么"，"怎么解析/绑定"留 UI 层
public struct WorkspaceShortcut: Sendable, Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var modifierFlags: UInt32

    public init(keyCode: UInt16, modifierFlags: UInt32) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

// MARK: - 单个窗口布局

/// 单窗口的可序列化状态：合约 + 周期 + 指标 + 画线引用 + 几何 + 层级
/// 指标用 String ID（IndicatorCore 内部 ID），画线用 UUID 引用 WP-42 Drawing
public struct WindowLayout: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var instrumentID: String
    public var period: KLinePeriod
    public var indicatorIDs: [String]
    public var drawingIDs: [UUID]
    public var frame: LayoutFrame
    /// 同模板内多窗口的 z 顺序（越大越在上）
    public var zIndex: Int

    public init(
        id: UUID = UUID(),
        instrumentID: String,
        period: KLinePeriod,
        indicatorIDs: [String] = [],
        drawingIDs: [UUID] = [],
        frame: LayoutFrame = .zero,
        zIndex: Int = 0
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.period = period
        self.indicatorIDs = indicatorIDs
        self.drawingIDs = drawingIDs
        self.frame = frame
        self.zIndex = zIndex
    }
}

// MARK: - 工作区模板

/// 工作区模板 · 一组窗口布局 + 元数据
public struct WorkspaceTemplate: Sendable, Codable, Equatable, Identifiable, Hashable {

    /// 模板大类（盘前/盘中/盘后/自定义；与产品设计书对齐）
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case preMarket   // 盘前：自选刷新 / 隔夜分析
        case inMarket    // 盘中：主交易工作区
        case postMarket  // 盘后：复盘 + 日志
        case custom      // 自定义
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var windows: [WindowLayout]
    /// 一键切换快捷键（nil 表示未绑定；全局唯一性由 Book 层校验）
    public var shortcut: WorkspaceShortcut?
    /// Book 内同 kind 模板的相对顺序
    public var sortIndex: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .custom,
        windows: [WindowLayout] = [],
        shortcut: WorkspaceShortcut? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.windows = windows
        self.shortcut = shortcut
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 工作区簿（聚合根）

/// 工作区簿 · 持有所有模板 + 当前激活的模板 + 提供 CRUD/切换/复制
public struct WorkspaceBook: Sendable, Codable, Equatable {
    public private(set) var templates: [WorkspaceTemplate]
    public private(set) var activeTemplateID: UUID?

    public init(templates: [WorkspaceTemplate] = [], activeTemplateID: UUID? = nil) {
        self.templates = templates.sorted { $0.sortIndex < $1.sortIndex }
        self.activeTemplateID = activeTemplateID
        normalizeSortIndices()
        // 激活 ID 不存在则置空（基于已排序的 self.templates，显式声明依赖）
        if let id = activeTemplateID, !self.templates.contains(where: { $0.id == id }) {
            self.activeTemplateID = nil
        }
    }

    // MARK: - 模板 CRUD

    /// 新增模板（追加到末尾，sortIndex 自动分配；首个模板自动激活）
    @discardableResult
    public mutating func addTemplate(
        name: String,
        kind: WorkspaceTemplate.Kind = .custom,
        windows: [WindowLayout] = [],
        shortcut: WorkspaceShortcut? = nil,
        id: UUID = UUID(),
        now: Date = Date()
    ) -> WorkspaceTemplate {
        let template = WorkspaceTemplate(
            id: id,
            name: name,
            kind: kind,
            windows: windows,
            shortcut: shortcut,
            sortIndex: templates.count,
            createdAt: now,
            updatedAt: now
        )
        templates.append(template)
        if activeTemplateID == nil { activeTemplateID = template.id }
        return template
    }

    /// 重命名模板
    @discardableResult
    public mutating func renameTemplate(id: UUID, to newName: String, now: Date = Date()) -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        templates[index].name = newName
        templates[index].updatedAt = now
        return true
    }

    /// 删除模板（若删的是激活的，自动切到第一个剩下的；空集则置 nil）
    @discardableResult
    public mutating func removeTemplate(id: UUID) -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return false }
        templates.remove(at: index)
        normalizeSortIndices()
        if activeTemplateID == id {
            activeTemplateID = templates.first?.id
        }
        return true
    }

    /// 复制模板（深拷贝 windows · 全部生成新 UUID · 不复制快捷键避免冲突）
    @discardableResult
    public mutating func duplicateTemplate(id: UUID, newName: String? = nil, now: Date = Date()) -> WorkspaceTemplate? {
        guard let original = templates.first(where: { $0.id == id }) else { return nil }
        // 深拷贝 windows：仅换 id，其余字段不变（避免日后字段新增时漏拷的隐患）
        let clonedWindows = original.windows.map { window -> WindowLayout in
            var copy = window
            copy.id = UUID()
            return copy
        }
        let copy = WorkspaceTemplate(
            id: UUID(),
            name: newName ?? "\(original.name) 副本",
            kind: original.kind,
            windows: clonedWindows,
            shortcut: nil,
            sortIndex: templates.count,
            createdAt: now,
            updatedAt: now
        )
        templates.append(copy)
        return copy
    }

    /// 拖拽模板：把 from 索引的模板移到 to 位置
    @discardableResult
    public mutating func moveTemplate(from: Int, to: Int) -> Bool {
        guard Self.moveElement(in: &templates, from: from, to: to) else { return false }
        normalizeSortIndices()
        return true
    }

    // MARK: - 切换激活

    /// 切换激活模板
    @discardableResult
    public mutating func setActive(id: UUID?) -> Bool {
        if let id = id {
            guard templates.contains(where: { $0.id == id }) else { return false }
            activeTemplateID = id
        } else {
            activeTemplateID = nil
        }
        return true
    }

    /// 当前激活模板（nil 表示未激活或被删除）
    public var activeTemplate: WorkspaceTemplate? {
        guard let id = activeTemplateID else { return nil }
        return templates.first(where: { $0.id == id })
    }

    // MARK: - 模板更新

    /// 整模板覆盖更新（保留 id/sortIndex/createdAt，刷新 updatedAt）
    /// 用于"另存为模板"或快捷键覆盖当前布局
    @discardableResult
    public mutating func updateTemplate(_ template: WorkspaceTemplate, now: Date = Date()) -> Bool {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return false }
        var merged = template
        merged.sortIndex = templates[index].sortIndex
        merged.createdAt = templates[index].createdAt
        merged.updatedAt = now
        templates[index] = merged
        return true
    }

    /// 设置/清除快捷键（强制全局唯一：若另一模板已用同 shortcut，先清掉它）
    @discardableResult
    public mutating func setShortcut(_ shortcut: WorkspaceShortcut?, for templateID: UUID, now: Date = Date()) -> Bool {
        guard let targetIdx = templates.firstIndex(where: { $0.id == templateID }) else { return false }
        if let shortcut = shortcut {
            for i in templates.indices where i != targetIdx && templates[i].shortcut == shortcut {
                templates[i].shortcut = nil
                templates[i].updatedAt = now
            }
        }
        templates[targetIdx].shortcut = shortcut
        templates[targetIdx].updatedAt = now
        return true
    }

    // MARK: - 查询

    public func template(id: UUID) -> WorkspaceTemplate? {
        templates.first(where: { $0.id == id })
    }

    /// 按类型筛选模板
    public func templates(of kind: WorkspaceTemplate.Kind) -> [WorkspaceTemplate] {
        templates.filter { $0.kind == kind }
    }

    /// 按快捷键查找（命中 shortcut 的第一个模板）
    public func template(forShortcut shortcut: WorkspaceShortcut) -> WorkspaceTemplate? {
        templates.first(where: { $0.shortcut == shortcut })
    }

    // MARK: - 私有

    /// 强制 sortIndex 与数组顺序一致（连续整数 0..<N）
    private mutating func normalizeSortIndices() {
        for i in templates.indices {
            if templates[i].sortIndex != i {
                templates[i].sortIndex = i
            }
        }
    }

    /// 通用 move-by-index（语义同 SwiftUI onMove）
    /// - Returns: false 表示 from == to 或索引越界（数组未被修改）
    private static func moveElement<T>(in array: inout [T], from: Int, to: Int) -> Bool {
        guard from != to,
              array.indices.contains(from),
              to >= 0, to <= array.count
        else { return false }
        let element = array.remove(at: from)
        let insertIndex = to > from ? to - 1 : to
        array.insert(element, at: insertIndex)
        return true
    }
}
