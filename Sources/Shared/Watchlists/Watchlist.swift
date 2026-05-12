// WP-43 · 自选管理 v1 数据模型层
// 多分组（无上限）+ 每组合约（无上限）+ 拖拽排序 + 同组去重
// 纯 value type 设计；不 import SwiftUI/AppKit/CloudKit，保持 Sources/Shared 跨端可移植
// 屏幕级 DnD 交互留给后续 UI WP
// WP-60 同步预埋（v15.24 batch003）：version / deletedAt 字段；旧 JSON decode 兼容（decodeIfPresent）

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
    /// WP-60 · 修改次数（新建=1 · 每次 mutate 字段 +1）· LWW 副决胜 · 旧 JSON 缺省 1
    public var version: Int
    /// WP-60 · 软删除时间戳（tombstone）· 非 nil 即已删
    public var deletedAt: Date?
    /// v17.36 C1 · 分组颜色索引（0~7 · nil = 默认 accent）· 向后兼容旧 JSON decodeIfPresent
    public var colorIndex: Int?
    /// v17.131 · 分组独立排序字段 raw（nil = 用全局默认 .manual）· 向后兼容旧 JSON
    public var sortFieldRaw: String?
    /// v17.131 · 分组独立排序升降序（nil = 用全局默认 false 降序）· 向后兼容旧 JSON
    public var sortAscending: Bool?
    /// v17.133 · 置顶合约 ID 列表（每组 ≤ 3 · 永远在排序结果前 · nil/空 = 无置顶）· 向后兼容旧 JSON
    public var pinnedInstrumentIDs: [String]?

    /// v17.133 · 每组最多置顶合约数（trader 主力/次主力/对冲腿 三档即够）
    public static let maxPinnedPerGroup: Int = 3

    public init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Int = 0,
        instrumentIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        version: Int = 1,
        deletedAt: Date? = nil,
        colorIndex: Int? = nil,
        sortFieldRaw: String? = nil,
        sortAscending: Bool? = nil,
        pinnedInstrumentIDs: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.instrumentIDs = instrumentIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.deletedAt = deletedAt
        self.colorIndex = colorIndex
        self.sortFieldRaw = sortFieldRaw
        self.sortAscending = sortAscending
        self.pinnedInstrumentIDs = pinnedInstrumentIDs
    }

    /// 空分组工厂
    public static func empty(name: String, sortIndex: Int = 0) -> Watchlist {
        Watchlist(name: name, sortIndex: sortIndex)
    }

    // MARK: - Codable（兼容旧 JSON · 缺 version/deletedAt 时回退）

    private enum CodingKeys: String, CodingKey {
        case id, name, sortIndex, instrumentIDs, createdAt, updatedAt, version, deletedAt
        case colorIndex
        case sortFieldRaw, sortAscending   // v17.131
        case pinnedInstrumentIDs           // v17.133
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.sortIndex = try c.decode(Int.self, forKey: .sortIndex)
        self.instrumentIDs = try c.decode([String].self, forKey: .instrumentIDs)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex)
        self.sortFieldRaw = try c.decodeIfPresent(String.self, forKey: .sortFieldRaw)
        self.sortAscending = try c.decodeIfPresent(Bool.self, forKey: .sortAscending)
        self.pinnedInstrumentIDs = try c.decodeIfPresent([String].self, forKey: .pinnedInstrumentIDs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(sortIndex, forKey: .sortIndex)
        try c.encode(instrumentIDs, forKey: .instrumentIDs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encodeIfPresent(colorIndex, forKey: .colorIndex)
        try c.encodeIfPresent(sortFieldRaw, forKey: .sortFieldRaw)
        try c.encodeIfPresent(sortAscending, forKey: .sortAscending)
        try c.encodeIfPresent(pinnedInstrumentIDs, forKey: .pinnedInstrumentIDs)
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
        guard groups[index].name != newName else { return true }
        groups[index].name = newName
        groups[index].updatedAt = now
        groups[index].version += 1
        return true
    }

    /// v17.36 C1 · 设置分组颜色索引（0~7 · nil 恢复默认 accent）
    /// - Returns: 是否成功（false 表示分组不存在）
    @discardableResult
    public mutating func setGroupColor(id: UUID, colorIndex: Int?, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        guard groups[index].colorIndex != colorIndex else { return true }
        groups[index].colorIndex = colorIndex
        groups[index].updatedAt = now
        groups[index].version += 1
        return true
    }

    /// v17.131 · 设置分组独立排序规则（每组独立 · 不同组可用不同字段/升降序）
    /// - Parameters:
    ///   - sortFieldRaw: WatchlistSortField rawValue · nil 恢复默认 .manual
    ///   - sortAscending: 升降序 · nil 视为 false（降序）
    /// - Returns: 是否成功（false 表示分组不存在）
    @discardableResult
    public mutating func setGroupSort(id: UUID, sortFieldRaw: String?, sortAscending: Bool?, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        let changed = groups[index].sortFieldRaw != sortFieldRaw || groups[index].sortAscending != sortAscending
        guard changed else { return true }
        groups[index].sortFieldRaw = sortFieldRaw
        groups[index].sortAscending = sortAscending
        groups[index].updatedAt = now
        groups[index].version += 1
        return true
    }

    /// v17.133 · 置顶合约到分组顶部（每组 ≤ Watchlist.maxPinnedPerGroup · 已置顶幂等 · 上限拒绝）
    /// - Returns: 是否实际新增置顶（false = 已置顶 / 上限满 / 分组或合约不存在）
    @discardableResult
    public mutating func pinInstrument(_ instrumentID: String, in groupID: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard groups[index].instrumentIDs.contains(instrumentID) else { return false }
        var pins = groups[index].pinnedInstrumentIDs ?? []
        guard !pins.contains(instrumentID) else { return false }
        guard pins.count < Watchlist.maxPinnedPerGroup else { return false }
        pins.append(instrumentID)
        groups[index].pinnedInstrumentIDs = pins
        groups[index].updatedAt = now
        groups[index].version += 1
        return true
    }

    /// v17.133 · 取消置顶 · 空数组写回 nil（紧凑存储）
    /// - Returns: 是否实际移除
    @discardableResult
    public mutating func unpinInstrument(_ instrumentID: String, in groupID: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        var pins = groups[index].pinnedInstrumentIDs ?? []
        guard let pos = pins.firstIndex(of: instrumentID) else { return false }
        pins.remove(at: pos)
        groups[index].pinnedInstrumentIDs = pins.isEmpty ? nil : pins
        groups[index].updatedAt = now
        groups[index].version += 1
        return true
    }

    /// v17.133 · 是否置顶
    public func isPinned(_ instrumentID: String, in groupID: UUID) -> Bool {
        group(id: groupID)?.pinnedInstrumentIDs?.contains(instrumentID) ?? false
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
        groups[index].version += 1
        return true
    }

    /// 从分组移除合约
    /// - Returns: 是否成功（false 表示分组或合约不存在）
    @discardableResult
    public mutating func removeInstrument(_ instrumentID: String, from groupID: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard let pos = groups[index].instrumentIDs.firstIndex(of: instrumentID) else { return false }
        groups[index].instrumentIDs.remove(at: pos)
        // v17.133 · 移除时同步清掉置顶引用（防 stale）
        if var pins = groups[index].pinnedInstrumentIDs, let p = pins.firstIndex(of: instrumentID) {
            pins.remove(at: p)
            groups[index].pinnedInstrumentIDs = pins.isEmpty ? nil : pins
        }
        groups[index].updatedAt = now
        groups[index].version += 1
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
        groups[groupIndex].version += 1
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
        // v17.133 · 跨组移动时清掉源组置顶引用（不携带到目标组 · trader 期望重新决策）
        if sourceIdx != targetIdx, var pins = groups[sourceIdx].pinnedInstrumentIDs,
           let p = pins.firstIndex(of: instrumentID) {
            pins.remove(at: p)
            groups[sourceIdx].pinnedInstrumentIDs = pins.isEmpty ? nil : pins
        }
        groups[sourceIdx].updatedAt = now
        groups[sourceIdx].version += 1

        if sourceIdx != targetIdx, !groups[targetIdx].instrumentIDs.contains(instrumentID) {
            let count = groups[targetIdx].instrumentIDs.count
            let insertAt = targetIndex.map { max(0, min($0, count)) } ?? count
            groups[targetIdx].instrumentIDs.insert(instrumentID, at: insertAt)
            groups[targetIdx].updatedAt = now
            groups[targetIdx].version += 1
        }
        return true
    }

    // MARK: - WP-60 同步 · 软删除

    /// 软删除分组（设 deletedAt + version+1）· 同步层用此而非物理 removeGroup
    /// - Returns: 是否成功
    @discardableResult
    public mutating func softDeleteGroup(id: UUID, now: Date = Date()) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return false }
        guard groups[index].deletedAt == nil else { return false }
        groups[index].deletedAt = now
        groups[index].updatedAt = now
        groups[index].version += 1
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

    /// v15.20 batch61 · 跨所有分组的合约去重列表（保持首次出现顺序）· 聚合视图扫盘用
    public var allInstrumentIDsDeduped: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for g in groups {
            for id in g.instrumentIDs where !seen.contains(id) {
                seen.insert(id)
                out.append(id)
            }
        }
        return out
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
