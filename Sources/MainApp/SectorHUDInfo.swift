// 板块归属 HUD 信息（v15.56 · 主图 HUD `.sectorInfo` 字段计算）
//
// trader 用法：在主图角落看到当前合约所属板块的横向对比
//   - 板块平均涨跌 + 多空偏向 → 当前 K 线的"板块共识"是什么
//   - 龙头 / 弱势 → 是否本合约就是板块龙头 / 弱势
//
// 数据源：SectorPresets · v2 接 CTP 后整段切换 · 此层 API 不变
//
// 合约 ID 匹配规则（兼容多种格式）：
//   - 精确：byID 命中（"RB0" / "AU0"）
//   - 前缀拼 "0"：字母前缀 + "0"（"rb2509" → "RB" → "RB0" 命中）
//   - 不命中返 nil（HUD 不显示）

#if canImport(SwiftUI) && os(macOS)

import Foundation
import Shared

struct SectorHUDInfo: Equatable {
    let sector: Sector
    let avgChangePct: Double
    let bullBias: Double                // [-1, +1] · gainers - losers / total
    let myInstrument: SectorInstrument? // 当前合约（命中时）
    let strongest: SectorInstrument?
    let weakest: SectorInstrument?

    /// 当前合约是否为板块龙头
    var isLeader: Bool {
        guard let me = myInstrument, let s = strongest else { return false }
        return me.id == s.id
    }

    /// 当前合约是否为板块弱势
    var isLagger: Bool {
        guard let me = myInstrument, let w = weakest else { return false }
        return me.id == w.id
    }

    /// 主标题：板块 + 均值 + 多空偏向
    /// 例："板块 黑色系 · 均 +0.45% · 偏多 36%"
    var headline: String {
        let bias = Int((bullBias * 100).rounded())
        let biasLabel = bias > 5 ? "偏多" : (bias < -5 ? "偏空" : "中性")
        let biasNum = abs(bias) >= 5 ? " \(abs(bias))%" : ""
        return String(format: "板块 %@ · 均 %+.2f%% · %@%@",
                      sector.displayName, avgChangePct, biasLabel, biasNum)
    }

    /// 龙头行（nil = 板块仅 1 品种 / 无强势）
    var leaderText: String? {
        guard let s = strongest else { return nil }
        if isLeader {
            return String(format: "龙头：本合约（领涨 %+.2f%%）", s.changePct)
        }
        return String(format: "龙头：%@ %+.2f%%", s.name, s.changePct)
    }

    /// 弱势行
    var laggerText: String? {
        guard let w = weakest else { return nil }
        // 龙头 / 弱势是同一个时（板块仅 1 品种）不重复显示
        if let s = strongest, s.id == w.id { return nil }
        if isLagger {
            return String(format: "弱势：本合约（领跌 %+.2f%%）", w.changePct)
        }
        return String(format: "弱势：%@ %+.2f%%", w.name, w.changePct)
    }

    /// 入口：由合约 ID 推断板块 + 计算统计
    static func compute(instrumentID: String) -> SectorHUDInfo? {
        guard let me = matchInstrument(instrumentID) else { return nil }
        let peers = SectorPresets.instruments(in: me.sector)
        guard !peers.isEmpty else { return nil }
        let stat = SectorStatisticsCalculator.compute(peers, sector: me.sector)
        return SectorHUDInfo(
            sector: me.sector,
            avgChangePct: stat.avgChangePct,
            bullBias: stat.bullBias,
            myInstrument: me,
            strongest: stat.strongest,
            weakest: stat.weakest
        )
    }

    /// 容错匹配：精确 → 字母前缀 + "0" → all 前缀 fallback
    static func matchInstrument(_ id: String) -> SectorInstrument? {
        if let hit = SectorPresets.byID[id] { return hit }
        let upper = id.uppercased()
        if let hit = SectorPresets.byID[upper] { return hit }
        // 字母前缀（"rb2509" → "RB"）· 拼 "0" 查主连续
        let letters = String(upper.prefix(while: { $0.isLetter }))
        guard !letters.isEmpty else { return nil }
        if let hit = SectorPresets.byID["\(letters)0"] { return hit }
        // 兜底：byID key 取字母前缀（"AU0" → "AU"）· 与本合约前缀相等
        return SectorPresets.all.first(where: { preset in
            String(preset.id.prefix(while: { $0.isLetter })) == letters
        })
    }
}

#endif
