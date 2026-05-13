// v17.160 · 副图指标收藏夹（trader 高频指标自定义快捷开关）
//
// 痛点：v17.158 副图 picker 28 项分 6 大类后 · trader 仍要每天点 2 层菜单（先 picker 再分类）
// 收藏夹解决：常用 4-8 个指标钉在 picker 顶部 ⭐ section · 0 层点开即可勾选
//
// 数据流：
// - 全局 UserDefaults key indicatorFavorites.v1 · 跨合约/周期共享（trader 偏好"我永远先看 MACD/KDJ/RSI"）
// - 右键 picker 行 → "⭐ 加入收藏 / 移出收藏" · 与 [[v17.158]] 分组 picker 同 sheet
// - 收藏顺序保留（用户加入顺序 = 顶部展示顺序）· 没有数量上限（trader 自己决定 picker 高度）
//
// rawValue 字符串引用：与 [[v17.154 IndicatorPreset]] 同模式跨 module 解耦（Shared 不引 MainApp 的 SubIndicatorKind）

import Foundation

/// 副图指标收藏夹（用户钉在 picker 顶部的高频指标）
public struct IndicatorFavorites: Sendable, Codable, Equatable {
    /// 收藏的 SubIndicatorKind rawValue 有序列表（加入顺序 = 展示顺序）
    public var rawValues: [String]

    public init(rawValues: [String] = []) {
        self.rawValues = rawValues
    }

    public static let `default` = IndicatorFavorites()

    /// 是否在收藏中
    public func contains(_ rawValue: String) -> Bool {
        rawValues.contains(rawValue)
    }

    /// 切换：在则移除 · 不在则追加末尾
    public mutating func toggle(_ rawValue: String) {
        if let idx = rawValues.firstIndex(of: rawValue) {
            rawValues.remove(at: idx)
        } else {
            rawValues.append(rawValue)
        }
    }

    /// 清空（reset 全部偏好用）
    public mutating func clear() {
        rawValues.removeAll()
    }

    /// 按 rawValue 直接加入（已存在不重复）
    public mutating func add(_ rawValue: String) {
        guard !rawValues.contains(rawValue) else { return }
        rawValues.append(rawValue)
    }

    /// 按 rawValue 移除
    public mutating func remove(_ rawValue: String) {
        rawValues.removeAll { $0 == rawValue }
    }
}

// MARK: - UserDefaults 加载 / 保存（与 IndicatorPreset 等同模式 · 失败返回 nil · 调用方 fallback default）

public enum IndicatorFavoritesStore {
    public static let key = "indicatorFavorites.v1"

    /// 失败 / 不存在返回 nil · 调用方决定 fallback default（空集 = 不显示 ⭐ section）
    public static func load(defaults: UserDefaults = .standard) -> IndicatorFavorites? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IndicatorFavorites.self, from: data)
    }

    /// 写入 UserDefaults · 失败静默
    public static func save(_ favs: IndicatorFavorites, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(favs) else { return }
        defaults.set(data, forKey: key)
    }
}
