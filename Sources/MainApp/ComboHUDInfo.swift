// 组合异常 HUD 信息（v15.73 · 主图 HUD `.comboAnomaly` 字段计算）
//
// trader 用法：在主图角落直接看到当前合约是否处于"组合异常"状态
//   - 命中 ≥3 类异常 = 真信号（多类共振而非单类噪声）
//   - 不命中 → 隐藏行（HUD 不冗余）
//
// 数据源：SectorPresets 全市场快照 → AnomalyDetector.scan → ComboAnomalyAggregator
// 性能：60 品种全扫 + 聚合 < 1ms（纯函数 · 无 IO）· 主图每帧调用 OK
//
// 合约 ID 匹配：复用 SectorHUDInfo.matchInstrument（"rb2509" → "RB0"）

#if canImport(SwiftUI) && os(macOS)

import Foundation
import Shared

struct ComboHUDInfo: Equatable {
    let instrumentID: String
    let instrumentName: String
    let kindCount: Int                  // 命中类型数（3-5）
    let totalSeverity: Double           // combo 严重度（数量加权）
    let avgSeverity: Double
    let kinds: [AnomalyKind]            // 按 AnomalyKind.allCases 顺序排列（与 UI tag 一致）

    /// 主标题：异常 N/5 · 类型缩写 · combo 严重度
    /// 例："异常 4/5 · 价·持·资·背 · combo 72"
    var headline: String {
        let abbr = kinds.map(kindAbbreviation).joined(separator: "·")
        return String(format: "异常 %d/5 · %@ · combo %d", kindCount, abbr, Int(totalSeverity))
    }

    /// 颜色提示：5 类满命中红 · 4 类橙 · 3 类黄
    var severityLevel: SeverityLevel {
        if kindCount >= 5 { return .high }
        if kindCount == 4 { return .mid }
        return .low
    }

    enum SeverityLevel {
        case high, mid, low
    }

    /// 单字缩写（HUD 紧凑显示）
    private func kindAbbreviation(_ kind: AnomalyKind) -> String {
        switch kind {
        case .priceSpike:        return "价"
        case .oiSpike:           return "持"
        case .fundSurge:         return "资"
        case .priceOIDivergence: return "背"
        case .sectorOutlier:     return "离"
        }
    }

    /// 入口：由合约 ID 推断 + 全市场扫描 + 聚合 · 不命中返 nil
    /// - Parameter minKinds: 最少命中类型数（默认 3 · 与 ⌘⌥A combo 视图默认值一致）
    static func compute(instrumentID: String, minKinds: Int = 3) -> ComboHUDInfo? {
        guard let me = SectorHUDInfo.matchInstrument(instrumentID) else { return nil }
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        let combos = ComboAnomalyAggregator.aggregate(events: result.events, minKinds: minKinds)
        guard let combo = combos.first(where: { $0.instrumentID == me.id }) else { return nil }
        let orderedKinds = AnomalyKind.allCases.filter { combo.kinds.contains($0) }
        return ComboHUDInfo(
            instrumentID: combo.instrumentID,
            instrumentName: combo.instrumentName,
            kindCount: combo.kindCount,
            totalSeverity: combo.totalSeverity,
            avgSeverity: combo.avgSeverity,
            kinds: orderedKinds
        )
    }
}

#endif
