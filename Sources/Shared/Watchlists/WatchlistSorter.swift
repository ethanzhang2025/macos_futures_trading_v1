// v15.20 batch59 · 自选合约排序（trader 扫盘高频需求 · 涨幅榜/跌幅榜/活跃度）
//
// 设计要点：
// - 纯函数 [String] → [String] · key extractor 注入便于测试
// - .manual 保持原序（用户拖拽排序的结果不丢）
// - nil key 始终排末尾（数据未拉到的合约不打扰前序）
// - 同 key 时按 instrumentID 字典序作为稳定 tiebreaker
// - 升降序由 ascending 参数控制 · field=.manual 忽略

import Foundation

public enum WatchlistSortField: String, CaseIterable, Sendable, Codable {
    case manual          // 默认 · 保持 group.instrumentIDs 原序（用户拖拽排序结果）
    case instrumentID    // 合约代码字典序
    case lastPrice       // 最新价
    case changePct       // 涨跌幅 %
    case change          // v15.38 V2 · 涨跌（绝对值 · 不归一化 · 高价合约同涨幅 = 大变动）
    case openInterest    // 持仓量
    case volume          // v15.38 V2 · 成交量（活跃度 · trader 找活跃合约）
    case amplitude       // v15.38 V2 · 振幅 = (high - low) / preClose · 日内波动率
    case spread          // v17.33 C4 · Bid-Ask 价差% = (ask-bid)/last · trader 找窄/宽价差合约

    public var displayName: String {
        switch self {
        case .manual:        return "手动"
        case .instrumentID:  return "合约"
        case .lastPrice:     return "最新价"
        case .changePct:     return "涨跌幅"
        case .change:        return "涨跌"
        case .openInterest:  return "持仓量"
        case .volume:        return "成交量"
        case .amplitude:     return "振幅"
        case .spread:        return "买卖价差"
        }
    }
}

public enum WatchlistSorter {

    /// 按字段排序合约 ID 列表
    /// - ids: 输入合约代码（保序原数组 · sort 不 mutate）
    /// - field: 排序字段
    /// - ascending: 升序（true）或降序（false）· field=.manual 忽略
    /// - keyForID: 数值字段 closure（lastPrice/changePct/openInterest/volume/change/amplitude 用 · 不可比较返回 nil 排末尾）
    public static func sort(
        ids: [String],
        field: WatchlistSortField,
        ascending: Bool,
        keyForID: (String) -> Double?
    ) -> [String] {
        switch field {
        case .manual:
            return ids   // 不排
        case .instrumentID:
            return ids.sorted { ascending ? $0 < $1 : $0 > $1 }
        case .lastPrice, .changePct, .change, .openInterest, .volume, .amplitude, .spread:
            return ids.sorted { lhs, rhs in
                let lk = keyForID(lhs)
                let rk = keyForID(rhs)
                // nil 始终排末尾（无关 ascending）
                switch (lk, rk) {
                case (nil, nil):       return lhs < rhs   // 字典序 tiebreak
                case (nil, _):         return false       // lhs 排后
                case (_, nil):         return true        // rhs 排后 · lhs 在前
                case (let a?, let b?):
                    if a == b { return lhs < rhs }   // 同 key tiebreak
                    return ascending ? a < b : a > b
                }
            }
        }
    }
}
