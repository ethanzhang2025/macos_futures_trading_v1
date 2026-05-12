// v17.129 · 自选合约备注（trader 个人笔记 · 跨日跨周保留）
//
// trader 场景：
// - 复盘时记 "RB0 等回 3540 入场"
// - 关键支撑/阻力："AU0 525 是周线 BOLL 下轨"
// - 策略备注："IF0 跨期做多 12-3 价差扩大"
//
// 设计：
// - 全局存储（不挂在 Watchlist group · 同合约在多组共享同一 note）
// - UserDefaults 持久化（轻量 · 跨窗口 didChangeNotification 联动）
// - 不参与 CloudKit 同步（v1 仅本机 · 留 v2）
// - 与 InstrumentFlag 同模式（pattern 一致 · 维护简单）

import Foundation

/// 全局合约备注 store · UserDefaults stringDict (instrumentID → noteText) 持久化
/// 跨窗口同步走 UserDefaults.didChangeNotification（与 InstrumentFlag / ChartTheme 同模式）
public struct InstrumentNoteStore {

    public static let defaultsKey = "watchlist.v1.instrumentNotes"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 读 instrumentID 的备注 · 缺失返回 nil
    public func note(for instrumentID: String) -> String? {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] else { return nil }
        return dict[instrumentID]
    }

    /// 设置备注 · 空字符串 / nil 会从存储移除（保持 dict 紧凑）
    public func setNote(_ note: String?, for instrumentID: String) {
        var dict = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            dict[instrumentID] = t
        } else {
            dict.removeValue(forKey: instrumentID)
        }
        defaults.set(dict, forKey: Self.defaultsKey)
    }

    /// 是否有备注（hover 标识用 · 比 note(for:) 省一次字符串解码）
    public func hasNote(for instrumentID: String) -> Bool {
        guard let dict = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] else { return false }
        return dict[instrumentID]?.isEmpty == false
    }

    /// 全部备注快照（测试 / 全量 export 用）
    public func allNotes() -> [String: String] {
        (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
    }

    /// 清空全部备注
    public func clearAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
