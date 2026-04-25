// WP-43 · 自选管理 v1 数据模型层
// 多分组（无上限）+ 每组合约（无上限）+ 拖拽排序 + 同组去重
// 纯 value type 设计；不 import SwiftUI/AppKit/CloudKit，保持 Sources/Shared 跨端可移植
// 屏幕级 DnD 交互留给后续 UI WP；CloudKit 同步留给 A12（M7-M9）

import Foundation

/// 自选分组 · 一个分组持有有序的 instrumentID 列表
public struct Watchlist: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// 同 Book 内分组的相对顺序（拖拽排序后由 Book 重写连续整数）
    public var sortIndex: Int
    /// 合约 ID 有序数组（顺序即排序，拖拽即数组 move）
    public var instrumentIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Int = 0,
        instrumentIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.instrumentIDs = instrumentIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 空分组工厂
    public static func empty(name: String, sortIndex: Int = 0) -> Watchlist {
        Watchlist(name: name, sortIndex: sortIndex)
    }
}

/// 自选簿 · 聚合根 · 持有所有分组 + 提供增删改查与拖拽排序
/// 整体可 Codable 序列化用于本地持久化（JSON / SQLite blob 上层自选）
public struct WatchlistBook: Sendable, Codable, Equatable {
    /// 内部存储：按 sortIndex 升序维护的分组列表（所有 mutating 方法负责保持有序与连续）
    public private(set) var groups: [Watchlist]

    public init(groups: [Watchlist] = []) {
        self.groups = groups.sorted { $0.sortIndex < $1.sortIndex }
        normalizeSortIndices()
    }

    // MARK: - 分组级 CRUD

    /// 新增分组（追加到末尾，sortIndex 自动分配）
    /// - Returns: 新建的 Watchlist（含分配后的 sortIndex 与 id）
    @discardableResult
    public mutating func addGroup(name: String, id: UUID = UUID(), now: Date = Date()) -> Watchlist {
        let newGroup = Watchlist(
            id: id,
            name: name,
            sortIndex: groups.count,
            instrumentIDs: [],
            createdAt: now,
            updatedAt: now
        )
        groups.append(newGroup)
        return newGroup
    }

    /// 重命名分组
    /// - Returns: 是否成功（false 表示分组不存在）
    @discardableResult
    public mutating func renameGroup(id: UUID, to newName: String, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups[index].name = newName
        groups[index].updatedAt = now
        return true
    }

    /// 删除分组
    /// - Returns: 是否成功（false 表示分组不存在）
    @discardableResult
    public mutating func removeGroup(id: UUID) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        groups.remove(at: index)
        normalizeSortIndices()
        return true
    }

    /// 拖拽分组：把 from 索引的分组移到 to 索引位置
    /// - Returns: 是否成功（false 表示索引越界或 from == to）
    @discardableResult
    public mutating func moveGroup(from: Int, to: Int) -> Bool {
        guard Self.moveElement(in: &groups, from: from, to: to) else { return false }
        normalizeSortIndices()
        return true
    }

    // MARK: - 合约级 CRUD

    /// 添加合约到分组（同组去重）
    /// - Returns: 是否新增（false 表示分组不存在或合约已存在）
    @discardableResult
    public mutating func addInstrument(_ instrumentID: String, to groupID: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard !groups[index].instrumentIDs.contains(instrumentID) else { return false }
        groups[index].instrumentIDs.append(instrumentID)
        groups[index].updatedAt = now
        return true
    }

    /// 从分组移除合约
    /// - Returns: 是否成功（false 表示分组或合约不存在）
    @discardableResult
    public mutating func removeInstrument(_ instrumentID: String, from groupID: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard let pos = groups[index].instrumentIDs.firstIndex(of: instrumentID) else { return false }
        groups[index].instrumentIDs.remove(at: pos)
        groups[index].updatedAt = now
        return true
    }

    /// 同组内拖拽合约（重排序）
    /// - Returns: 是否成功
    @discardableResult
    public mutating func moveInstrument(in groupID: UUID, from: Int, to: Int, now: Date = Date()) -> Bool {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              Self.moveElement(in: &groups[groupIndex].instrumentIDs, from: from, to: to)
        else { return false }
        groups[groupIndex].updatedAt = now
        return true
    }

    /// 跨分组移动合约（同组去重保证：目标组已有则仅从源组移除）
    /// - Returns: 是否成功
    @discardableResult
    public mutating func moveInstrument(
        _ instrumentID: String,
        from sourceGroupID: UUID,
        to targetGroupID: UUID,
        targetIndex: Int? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let sourceIdx = groups.firstIndex(where: { $0.id == sourceGroupID }),
              let targetIdx = groups.firstIndex(where: { $0.id == targetGroupID }),
              let posInSource = groups[sourceIdx].instrumentIDs.firstIndex(of: instrumentID)
        else { return false }

        groups[sourceIdx].instrumentIDs.remove(at: posInSource)
        groups[sourceIdx].updatedAt = now

        if sourceIdx != targetIdx, !groups[targetIdx].instrumentIDs.contains(instrumentID) {
            let count = groups[targetIdx].instrumentIDs.count
            let insertAt = targetIndex.map { max(0, min($0, count)) } ?? count
            groups[targetIdx].instrumentIDs.insert(instrumentID, at: insertAt)
            groups[targetIdx].updatedAt = now
        }
        return true
    }

    // MARK: - 查询

    /// 取分组（不存在返回 nil）
    public func group(id: UUID) -> Watchlist? {
        groups.first(where: { $0.id == id })
    }

    /// 合约是否在指定分组内
    public func contains(_ instrumentID: String, in groupID: UUID) -> Bool {
        group(id: groupID)?.instrumentIDs.contains(instrumentID) ?? false
    }

    /// 合约出现在哪些分组内（用于跨分组联动 UI）
    public func groups(containing instrumentID: String) -> [Watchlist] {
        groups.filter { $0.instrumentIDs.contains(instrumentID) }
    }

    // MARK: - 私有

    /// 强制 sortIndex 与数组顺序一致（连续整数 0..<N）
    private mutating func normalizeSortIndices() {
        for i in groups.indices {
            if groups[i].sortIndex != i {
                groups[i].sortIndex = i
            }
        }
    }

    /// 通用 move-by-index：把 from 处元素拔出再插到 to 处（语义同 SwiftUI onMove）
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
