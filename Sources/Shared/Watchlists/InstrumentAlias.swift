// v17.134 · 自选合约别名（trader 自定义可读名）
//
// trader 场景：
// - "m2509" → "豆粕 0509"（中文品种名 + 月份）
// - "RB0" → "螺纹主力"（主力替代展示）
// - "IFmain" → "沪深 300 主力"
//
// 设计：
// - 全局存储（与 InstrumentFlag/Note/Tag 同模式）
// - 单别名 ≤ 20 字（防超长破坏列表布局）
// - displayName(for:) 工具：有 alias 返回 "alias (id)" · 无返回 id
// - 跨窗口 didChangeNotification 联动

import Foundation

/// 全局合约别名 store · UserDefaults `[String: String]`（instrumentID → alias）
public struct InstrumentAliasStore {

    public static let defaultsKey = "watchlist.v1.instrumentAliases"

    /// 别名字符上限（防超长破坏 row 布局）
    public static let maxAliasLength: Int = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读 instrumentID 的别名 · 缺失返回 nil
    public func alias(for instrumentID: String) -> String? {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] else { return nil }
        return dict[instrumentID]
    }

    /// 设置别名 · 空字符串 / 全空白 / nil 移除（保持 dict 紧凑） · 自动 trim/截断
    public func setAlias(_ alias: String?, for instrumentID: String) {
        var dict = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
        let cleaned = sanitize(alias)
        if let c = cleaned {
            dict[instrumentID] = c
        } else {
            dict.removeValue(forKey: instrumentID)
        }
        defaults.set(dict, forKey: Self.defaultsKey)
    }

    /// 是否有别名（hover 标识 / 显示决策用）
    public func hasAlias(for instrumentID: String) -> Bool {
        alias(for: instrumentID)?.isEmpty == false
    }

    /// 显示用名 · 有别名返回 "alias (id)" · 无返回 id
    /// trader 阅读偏好：中文别名为主 · ID 为辅
    public func displayName(for instrumentID: String) -> String {
        if let a = alias(for: instrumentID), !a.isEmpty {
            return "\(a) (\(instrumentID))"
        }
        return instrumentID
    }

    /// 全部别名快照
    public func allAliases() -> [String: String] {
        (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
    }

    /// 清空全部别名
    public func clearAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - helpers

    private func sanitize(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > Self.maxAliasLength {
            return String(trimmed.prefix(Self.maxAliasLength))
        }
        return trimmed
    }
}
