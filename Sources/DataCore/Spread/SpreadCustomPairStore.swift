// 用户自定义价差对持久化（v15.75 · ⌘⌥W 价差对自定义 v1）
//
// 存储：UserDefaults JSON · 同 HUDFieldsBook 模式（v1 简化 · 不引 SQLite store）
// CRUD：load / save / append / remove · 防重 by id
//
// 设计要点：
// - SpreadPair 已 Codable · 直接 JSON 落盘
// - 自定义对的 id 由 UI 生成（custom-yyyyMMddHHmmss-leg1-leg2 · 兜底防撞）
// - load 失败（损坏 JSON）→ 返回 [] · 不抛错（trader 不感知）
// - append 同 id 跳过（防重）· UI 需校验 id 唯一
//
// 与 SpreadPresets.all 的关系：
// - load() 返回的 custom pairs 由 caller 手动 merge 到 SpreadPresets.all
// - 不污染 SpreadPresets（保持 preset 不变）

import Foundation

public enum SpreadCustomPairStore {
    public static let key = "spreadCustomPairs.v1"

    /// 加载所有自定义对 · 失败/不存在返回 []
    public static func load(defaults: UserDefaults = .standard) -> [SpreadPair] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SpreadPair].self, from: data)) ?? []
    }

    /// 全量覆盖写入
    @discardableResult
    public static func save(_ pairs: [SpreadPair], defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(pairs) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// 追加单条 · 同 id 已存在则跳过（防重）· 返回是否实际追加成功
    @discardableResult
    public static func append(_ pair: SpreadPair, defaults: UserDefaults = .standard) -> Bool {
        var current = load(defaults: defaults)
        guard !current.contains(where: { $0.id == pair.id }) else { return false }
        current.append(pair)
        return save(current, defaults: defaults)
    }

    /// 按 id 移除 · 不存在静默 · 返回是否实际移除
    @discardableResult
    public static func remove(id: String, defaults: UserDefaults = .standard) -> Bool {
        var current = load(defaults: defaults)
        let before = current.count
        current.removeAll { $0.id == id }
        guard current.count != before else { return false }
        return save(current, defaults: defaults)
    }

    /// 清空（trader 调试 / 还原用）
    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
