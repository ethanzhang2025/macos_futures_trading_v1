// v17.181 · PatternPerformanceStats 单测

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.181 · PatternPerformanceAnalyzer 形态历史回测")
struct PatternPerformanceStatsTests {

    @Test("analyze · 空 bars · 所有 kind 占位 count=0")
    func emptyBars() throws {
        let stats = try PatternPerformanceAnalyzer.analyze(bars: [])
        // v17.188 后 PatternKind allCases 共 13 · 全部 count=0
        #expect(stats.count == PatternKind.allCases.count)
        #expect(stats.allSatisfy { $0.occurrenceCount == 0 })
        #expect(stats.allSatisfy { $0.individualChangesPct.isEmpty })
    }

    @Test("analyze · 含双顶形态 · 后市下跌 · 看空 direction 一致 → 胜率 100%")
    func detectsDoubleTopWithWinRate() throws {
        // 双顶 prices: 100/90/101 · endIndex 大约在 5-7
        // 之后构造连续下跌让 lookForward=5 时 close 明显跌
        let pricesUp: [Double] = [100, 100, 90, 90, 101, 101]
        let pricesDown: [Double] = [98, 95, 92, 90, 88, 85]
        let bars = makeBars(closes: pricesUp + pricesDown)
        let stats = try PatternPerformanceAnalyzer.analyze(bars: bars, lookForwardBars: 5)
        let dt = stats.first { $0.kind == .doubleTop }!
        #expect(dt.occurrenceCount >= 1, "应至少检出 1 个 doubleTop · 命中 \(dt.occurrenceCount)")
        if dt.occurrenceCount > 0 {
            #expect(dt.averagePriceChangePct < 0, "后续平均跌 · 实际 \(dt.averagePriceChangePct)")
            #expect(dt.winRatePct == 100.0, "看空形态后续真跌 · 胜率应 100% · 实际 \(dt.winRatePct)")
        }
    }

    @Test("analyze · 未来 bars 不足 · pattern 不计入统计")
    func skipsPatternsWithoutFutureBars() throws {
        // 双顶在末尾 · 后续没有足够 bars
        let prices: [Double] = [100, 100, 90, 90, 101, 101, 95]
        let bars = makeBars(closes: prices)
        let stats = try PatternPerformanceAnalyzer.analyze(bars: bars, lookForwardBars: 20)
        let dt = stats.first { $0.kind == .doubleTop }!
        #expect(dt.occurrenceCount == 0, "未来 20 根不够 · 不计入")
    }

    @Test("analyze · direction 0（矩形）· 用 breakoutThreshold 计胜率")
    func rectangleWinRateUsesBreakoutThreshold() throws {
        // 矩形 prices · 触发后大涨 5%（突破方向无所谓 · 只看 abs ≥ threshold）
        let rectPrices: [Double] = [120, 120, 100, 100, 121, 121, 101, 101]
        let breakoutPrices: [Double] = [105, 108, 112, 115, 118]   // 后市突破
        let bars = makeBars(closes: rectPrices + breakoutPrices)
        let stats = try PatternPerformanceAnalyzer.analyze(bars: bars, lookForwardBars: 4, breakoutThresholdPct: 1.5)
        let rect = stats.first { $0.kind == .rectangle }!
        if rect.occurrenceCount > 0 {
            #expect(rect.winRatePct == 100, "abs(change%) ≥ 1.5% 算胜 · 实际 \(rect.winRatePct)")
        }
    }

    @Test("analyze · individualChangesPct 与 averagePriceChangePct 一致")
    func averageEqualsMeanOfIndividuals() throws {
        let pricesUp: [Double] = [100, 100, 90, 90, 101, 101]
        let pricesDown: [Double] = [98, 95, 92, 90, 88, 85]
        let bars = makeBars(closes: pricesUp + pricesDown)
        let stats = try PatternPerformanceAnalyzer.analyze(bars: bars, lookForwardBars: 5)
        for s in stats where s.occurrenceCount > 0 {
            let expected = s.individualChangesPct.reduce(0, +) / Double(s.individualChangesPct.count)
            #expect(abs(s.averagePriceChangePct - expected) < 0.0001, "avg 须 = mean(individual) · kind=\(s.kind)")
        }
    }
}

fileprivate func makeBars(closes: [Double]) -> [KLine] {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    return closes.enumerated().map { i, c in
        KLine(
            instrumentID: "TEST", period: .minute1,
            openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
            open: Decimal(c), high: Decimal(c + 0.1), low: Decimal(c - 0.1), close: Decimal(c),
            volume: 100, openInterest: 0, turnover: 0
        )
    }
}
