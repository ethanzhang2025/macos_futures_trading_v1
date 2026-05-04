// v15.20 batch69 · AlertWindow 列表排序（trader 大量预警时高效定位）
//
// 设计要点：
// - 与 WatchlistSorter 同形（纯函数 [Alert] → [Alert]）
// - .manual 保持 alerts 原序（创建顺序 · 默认）
// - status 排序按业务意义：active > triggered > paused > cancelled
// - lastTriggeredAt nil 排末尾（无关 ascending · 与 Watchlist nil 习惯一致）

import Foundation

public enum AlertSortField: String, CaseIterable, Sendable, Codable {
    case manual          // 默认 · 保持 alerts 原序（创建顺序）
    case name            // 名称字典序
    case instrumentID    // 合约代码字典序
    case status          // 业务状态序：active(0) / triggered(1) / paused(2) / cancelled(3)
    case createdAt       // 创建时间
    case lastTriggeredAt // 最近触发时间（nil 排末尾）

    public var displayName: String {
        switch self {
        case .manual:           return "默认"
        case .name:             return "名称"
        case .instrumentID:     return "合约"
        case .status:           return "状态"
        case .createdAt:        return "创建时间"
        case .lastTriggeredAt:  return "最近触发"
        }
    }
}

public enum AlertSorter {

    /// 业务状态序号（小=优先 · 与 trader 视角一致：active 顶 / cancelled 底）
    public static func statusRank(_ s: AlertStatus) -> Int {
        switch s {
        case .active:    return 0
        case .triggered: return 1
        case .paused:    return 2
        case .cancelled: return 3
        }
    }

    public static func sort(_ alerts: [Alert], field: AlertSortField, ascending: Bool) -> [Alert] {
        switch field {
        case .manual:
            return alerts
        case .name:
            return alerts.sorted { ascending ? $0.name < $1.name : $0.name > $1.name }
        case .instrumentID:
            return alerts.sorted { lhs, rhs in
                if lhs.instrumentID == rhs.instrumentID { return lhs.name < rhs.name }
                return ascending ? lhs.instrumentID < rhs.instrumentID : lhs.instrumentID > rhs.instrumentID
            }
        case .status:
            return alerts.sorted { lhs, rhs in
                let lr = statusRank(lhs.status)
                let rr = statusRank(rhs.status)
                if lr == rr { return lhs.name < rhs.name }
                return ascending ? lr < rr : lr > rr
            }
        case .createdAt:
            return alerts.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        case .lastTriggeredAt:
            return alerts.sorted { lhs, rhs in
                switch (lhs.lastTriggeredAt, rhs.lastTriggeredAt) {
                case (nil, nil):       return lhs.name < rhs.name
                case (nil, _):         return false
                case (_, nil):         return true
                case (let l?, let r?):
                    if l == r { return lhs.name < rhs.name }
                    return ascending ? l < r : l > r
                }
            }
        }
    }
}
