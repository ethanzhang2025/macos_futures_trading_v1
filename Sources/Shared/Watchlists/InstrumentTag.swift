// v17.132 · 自选合约多标签（trader 分类标记 · per-instrument 多 tag）
//
// trader 场景：
// - 「主力」「次主力」「套利腿」「对冲腿」分类
// - 「日内」「波段」「长线」周期标签
// - 「黑色」「化工」「农产品」板块标签
// - 标签筛选：仅看含 "套利腿" 标签的合约
//
// 设计：
// - 全局存储（与 InstrumentFlagStore / InstrumentNoteStore 同模式）
// - 一个合约可多标签（vs flag 单选 / note 单文本）
// - 标签自动 trim · 去重 · 空标签移除
// - 单合约标签数上限（防滥用 UI 破坏）
// - 单标签长度上限（防超长字符串）
// - 跨窗口 didChangeNotification 联动

import Foundation

/// 全局合约多标签 store · UserDefaults `[String: [String]]`（instrumentID → tag 数组）
public struct InstrumentTagStore {

    public static let defaultsKey = "watchlist.v1.instrumentTags"

    /// 单合约标签数上限（trader 不会贴太多 · 防 UI 行高失控）
    public static let maxTagsPerInstrument: Int = 10

    /// 单标签字符数上限（防超长破坏列表布局）
    public static let maxTagLength: Int = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读 instrumentID 的标签列表 · 缺失返回空数组
    public func tags(for instrumentID: String) -> [String] {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]] else { return [] }
        return dict[instrumentID] ?? []
    }

    /// 设置标签列表 · 空数组从存储移除（保持 dict 紧凑） · 自动 trim/去重/上限截断
    public func setTags(_ tags: [String], for instrumentID: String) {
        var dict = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]]) ?? [:]
        let cleaned = sanitize(tags)
        if cleaned.isEmpty {
            dict.removeValue(forKey: instrumentID)
        } else {
            dict[instrumentID] = cleaned
        }
        defaults.set(dict, forKey: Self.defaultsKey)
    }

    /// 加一个标签（已存在则跳过 · 超上限不加）· 返回是否实际新增
    @discardableResult
    public func addTag(_ tag: String, to instrumentID: String) -> Bool {
        let trimmed = trimAndClip(tag)
        guard !trimmed.isEmpty else { return false }
        var current = tags(for: instrumentID)
        guard !current.contains(trimmed) else { return false }
        guard current.count < Self.maxTagsPerInstrument else { return false }
        current.append(trimmed)
        setTags(current, for: instrumentID)
        return true
    }

    /// 移除一个标签 · 返回是否实际移除
    @discardableResult
    public func removeTag(_ tag: String, from instrumentID: String) -> Bool {
        let trimmed = trimAndClip(tag)
        var current = tags(for: instrumentID)
        guard let idx = current.firstIndex(of: trimmed) else { return false }
        current.remove(at: idx)
        setTags(current, for: instrumentID)
        return true
    }

    /// 是否含某标签（精确匹配 · trim 后比较）
    public func hasTag(_ tag: String, for instrumentID: String) -> Bool {
        let trimmed = trimAndClip(tag)
        return tags(for: instrumentID).contains(trimmed)
    }

    /// 是否有任何标签（hover 标识用）
    public func hasTags(for instrumentID: String) -> Bool {
        !tags(for: instrumentID).isEmpty
    }

    /// 全 instrument → 标签快照
    public func allInstrumentTags() -> [String: [String]] {
        (defaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]]) ?? [:]
    }

    /// 全局所有不重复标签（按字符串排序 · 用于筛选下拉 / 自动补全）
    public func allTagsAcrossInstruments() -> [String] {
        let dict = allInstrumentTags()
        var seen = Set<String>()
        for tags in dict.values {
            for t in tags { seen.insert(t) }
        }
        return seen.sorted()
    }

    /// 清空全部标签
    public func clearAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - v17.152 · 全工程批量管理（rename / merge / delete · trader 标签整理）

    /// 全局重命名标签 · 所有 instrument 上的 oldTag 都改成 newTag
    /// merge 语义：若 instrument 同时有 oldTag 和 newTag · rename 后去重（保留 newTag · 删 oldTag）
    /// - Returns: 受影响的 instrument 数量（0 = 未匹配 · oldTag 不存在或 newTag 非法）
    @discardableResult
    public func renameTagGlobally(oldTag: String, newTag: String) -> Int {
        let oldTrim = trimAndClip(oldTag)
        let newTrim = trimAndClip(newTag)
        guard !oldTrim.isEmpty, !newTrim.isEmpty, oldTrim != newTrim else { return 0 }
        var dict = allInstrumentTags()
        var affected = 0
        for (id, tags) in dict {
            guard let idx = tags.firstIndex(of: oldTrim) else { continue }
            var copy = tags
            copy.remove(at: idx)
            // merge：newTrim 已存在则去重 · 否则插入到原位（保留语义顺序）
            if !copy.contains(newTrim) {
                copy.insert(newTrim, at: idx)
            }
            dict[id] = copy
            affected += 1
        }
        guard affected > 0 else { return 0 }
        defaults.set(dict, forKey: Self.defaultsKey)
        return affected
    }

    /// 全局删除标签 · 所有 instrument 上的此标签都移除
    /// - Returns: 受影响的 instrument 数量
    @discardableResult
    public func deleteTagGlobally(_ tag: String) -> Int {
        let trim = trimAndClip(tag)
        guard !trim.isEmpty else { return 0 }
        var dict = allInstrumentTags()
        var affected = 0
        for (id, tags) in dict {
            guard tags.contains(trim) else { continue }
            let filtered = tags.filter { $0 != trim }
            if filtered.isEmpty {
                dict.removeValue(forKey: id)   // 清空 → 移除 entry 紧凑
            } else {
                dict[id] = filtered
            }
            affected += 1
        }
        guard affected > 0 else { return 0 }
        defaults.set(dict, forKey: Self.defaultsKey)
        return affected
    }

    /// 该标签影响的 instrument 数（rename / delete 前预览用 · "影响 N 个合约"提示）
    public func instrumentCountFor(tag: String) -> Int {
        let trim = trimAndClip(tag)
        guard !trim.isEmpty else { return 0 }
        return allInstrumentTags().values.reduce(0) { $0 + ($1.contains(trim) ? 1 : 0) }
    }

    // MARK: - helpers

    private func trimAndClip(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Self.maxTagLength else { return trimmed }
        return String(trimmed.prefix(Self.maxTagLength))
    }

    /// 数组级 sanitize：trim + 截断 + 去空 + 去重（保持首次顺序）+ 总数截断
    private func sanitize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let t = trimAndClip(raw)
            guard !t.isEmpty else { continue }
            guard !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
            if out.count >= Self.maxTagsPerInstrument { break }
        }
        return out
    }
}
