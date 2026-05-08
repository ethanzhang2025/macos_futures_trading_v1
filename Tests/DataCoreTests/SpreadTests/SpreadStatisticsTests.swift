// SpreadStatistics 单测（v15.27 · WP-套利分析 V1）

import Foundation
import Testing
@testable import DataCore

@Suite("SpreadStatistics · mean/std/Z-score/分位数")
struct SpreadStatisticsTests {

    private func makeValues(_ values: [Decimal]) -> [SpreadValue] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return values.enumerated().map { (i, v) in
            SpreadValue(
                openTime: base.addingTimeInterval(TimeInterval(i * 60)),
                value: v, leg1Close: 0, leg2Close: 0
            )
        }
    }

    @Test("空 → empty")
    func emptyInput() {
        let s = SpreadStatisticsCalculator.compute([])
        #expect(s.count == 0)
        #expect(s.current == 0)
        #expect(s.mean == 0)
    }

    @Test("单点 · stdDev=0 zScore=0")
    func singlePoint() {
        let s = SpreadStatisticsCalculator.compute(makeValues([100]))
        #expect(s.count == 1)
        #expect(s.current == 100)
        #expect(s.mean == 100)
        #expect(s.stdDev == 0)
        #expect(s.zScore == 0)
    }

    @Test("常量序列 · mean=值 · stdDev=0")
    func constantSeries() {
        let s = SpreadStatisticsCalculator.compute(makeValues([200, 200, 200, 200]))
        #expect(s.mean == 200)
        #expect(s.stdDev == 0)
        #expect(s.zScore == 0)
        #expect(s.min == 200)
        #expect(s.max == 200)
    }

    @Test("等差序列 [10..100 步10] · mean=55")
    func arithmeticSeries() {
        let values: [Decimal] = stride(from: 10, through: 100, by: 10).map { Decimal($0) }
        let s = SpreadStatisticsCalculator.compute(makeValues(values))
        #expect(s.count == 10)
        #expect(s.mean == 55)
        #expect(s.min == 10)
        #expect(s.max == 100)
        #expect(s.range == 90)
        #expect(s.current == 100)   // 末位
        #expect(s.percentile == 1.0) // 当前=最大值
    }

    @Test("Z-score 正向 · current >> mean")
    func zScoreHigh() {
        let s = SpreadStatisticsCalculator.compute(makeValues([10, 11, 9, 10, 11, 50]))
        // current=50 远超均值
        #expect(s.zScore > 1)
    }

    @Test("Z-score 负向 · current << mean")
    func zScoreLow() {
        let s = SpreadStatisticsCalculator.compute(makeValues([90, 88, 92, 91, 89, 30]))
        // current=30 远低均值
        #expect(s.zScore < -1)
    }

    @Test("分位数 · current=最低 → 0~低 · current=最高 → 1.0")
    func percentileExtremes() {
        let lo = SpreadStatisticsCalculator.compute(makeValues([5, 10, 20, 30, 40]))
        // current=40 最高 → percentile=1.0
        #expect(lo.percentile == 1.0)

        let hi = SpreadStatisticsCalculator.compute(makeValues([40, 30, 20, 10, 5]))
        // current=5 最低 → percentile=0.2（仅自己 ≤ 5）
        #expect(hi.percentile == 0.2)
    }

    @Test("±2σ 通道 · upper>mean>lower")
    func bandsOrder() {
        let s = SpreadStatisticsCalculator.compute(makeValues([10, 20, 30, 40, 50, 60]))
        #expect(s.upperBand2σ > s.mean)
        #expect(s.mean > s.lowerBand2σ)
    }
}
