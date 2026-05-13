// v17.181 · PatternDetector 历史回测统计（trader 量化每种形态的有效性）
//
// trader 视角：
//   "头肩顶到底准不准？我自己数据里命中 12 次后市怎么走？"
//   → 给每种 PatternKind 算：命中次数 + N 根后均价变化 + 与 direction 一致的胜率
//
// 算法：
// 1. PatternDetector.detect 跑全图 · 拿到 [DetectedPattern]
// 2. 对每个 pattern · 取 endIndex 后 lookForward 根 bars 的 close[endIndex + lookForward] vs close[endIndex] 变化%
// 3. 按 PatternKind 分组汇总：count / avgChangePct / winRate（变化%与 direction 一致 = 胜）
//
// 中性 direction（rectangle · direction=0）特殊处理：
//   - 胜率 = abs(changePct) >= 突破阈值的比例（不论方向 · 因为矩形终归会破位）
//   - direction*changePct 不适用

import Foundation
import Shared

/// 单一 PatternKind 的回测统计
public struct PatternPerformanceStats: Sendable, Equatable {
    public let kind: PatternKind
    public let occurrenceCount: Int
    /// N 根后 close 相对 endIndex close 的平均变化百分比（保留正负 · 含方向意义）
    public let averagePriceChangePct: Double
    /// 胜率（与 direction 一致 / 总命中数）· direction=0 时 abs(change%) ≥ breakoutThresholdPct 视为胜
    public let winRatePct: Double
    /// 该 kind 所有命中的 N 根后 changePct 列表（trader 可看分布 · 不只是均值）
    public let individualChangesPct: [Double]
}

public enum PatternPerformanceAnalyzer {

    /// 跑全图统计 · trader 在 PatternsListSheet 或 dashboard 调
    /// - Parameters:
    ///   - bars: 全部 K 线
    ///   - lookForwardBars: pattern endIndex 后多少根判定（默认 20 · 对应 trader "1 个月" 短线）
    ///   - breakoutThresholdPct: rectangle 等中性形态突破阈值（默认 1.5%）
    ///   - detectorParams: 转发给 PatternDetector
    /// - Returns: 按 PatternKind.allCases 顺序 · 即使 occurrenceCount = 0 也包含一项（占位 · UI 显示 0/—%/—%）
    public static func analyze(
        bars: [KLine],
        lookForwardBars: Int = 20,
        breakoutThresholdPct: Double = 1.5,
        detectorParams: PatternDetectorParams = .default
    ) throws -> [PatternPerformanceStats] {
        let kline = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        let detected = (try? PatternDetector.detect(kline: kline, params: detectorParams)) ?? []

        // 按 kind 聚合 · 计算每个 pattern 的"N 根后变化%"
        var bucket: [PatternKind: [Double]] = [:]
        for pattern in detected {
            let endIdx = pattern.endIndex
            let futureIdx = endIdx + lookForwardBars
            guard futureIdx < bars.count, endIdx >= 0, endIdx < bars.count else { continue }
            let baseClose = NSDecimalNumber(decimal: bars[endIdx].close).doubleValue
            guard baseClose > 0 else { continue }
            let futureClose = NSDecimalNumber(decimal: bars[futureIdx].close).doubleValue
            let changePct = (futureClose - baseClose) / baseClose * 100
            bucket[pattern.kind, default: []].append(changePct)
        }

        // 组装结果 · 即使没命中也输出占位（UI 显示完整列表）
        return PatternKind.allCases.map { kind in
            let changes = bucket[kind] ?? []
            let count = changes.count
            let avg: Double = count > 0 ? changes.reduce(0, +) / Double(count) : 0
            let win: Double
            if count == 0 {
                win = 0
            } else if kind.direction == 0 {
                let breakouts = changes.filter { abs($0) >= breakoutThresholdPct }.count
                win = Double(breakouts) / Double(count) * 100
            } else {
                let dir = Double(kind.direction)
                let wins = changes.filter { $0 * dir > 0 }.count
                win = Double(wins) / Double(count) * 100
            }
            return PatternPerformanceStats(
                kind: kind,
                occurrenceCount: count,
                averagePriceChangePct: avg,
                winRatePct: win,
                individualChangesPct: changes
            )
        }
    }
}
