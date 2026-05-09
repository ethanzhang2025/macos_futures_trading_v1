// 组合异常聚合器（v15.70 · ⌘⌥A 组合异常发现）
//
// 输入：[AnomalyEvent]（AnomalyDetector.scan 的 events）
// 输出：[ComboAnomaly]（按 instrumentID 聚合 · ≥ minKinds 类命中保留）
//
// 排序：totalSeverity desc → kindCount desc → instrumentID asc（稳定排序）

import Foundation

public enum ComboAnomalyAggregator {

    /// 聚合 combo 异常
    /// - Parameters:
    ///   - events: 全市场异常事件（不要求已按品种分组）
    ///   - minKinds: 触发 combo 的最小类型数（默认 3）
    ///   - now: 检测时间戳
    public static func aggregate(
        events: [AnomalyEvent],
        minKinds: Int = 3,
        now: Date = Date()
    ) -> [ComboAnomaly] {
        guard minKinds >= 1 else { return [] }
        let grouped = Dictionary(grouping: events, by: \.instrumentID)
        var combos: [ComboAnomaly] = []
        combos.reserveCapacity(grouped.count)
        for (_, list) in grouped {
            let kinds = Set(list.map(\.kind))
            guard kinds.count >= minKinds, let first = list.first else { continue }
            combos.append(ComboAnomaly(
                instrumentID: first.instrumentID,
                instrumentName: first.instrumentName,
                sector: first.sector,
                events: list.sorted { $0.severity > $1.severity },
                detectedAt: now
            ))
        }
        combos.sort { lhs, rhs in
            if lhs.totalSeverity != rhs.totalSeverity { return lhs.totalSeverity > rhs.totalSeverity }
            if lhs.kindCount != rhs.kindCount { return lhs.kindCount > rhs.kindCount }
            return lhs.instrumentID < rhs.instrumentID
        }
        return combos
    }

    /// 便利方法：直接基于 AnomalyDetector 全市场扫描结果聚合
    public static func aggregate(
        from result: AnomalyDetectionResult,
        minKinds: Int = 3,
        now: Date = Date()
    ) -> [ComboAnomaly] {
        aggregate(events: result.events, minKinds: minKinds, now: now)
    }
}
