// WP-41 v2 commit 1/4 · MA 增量计算 API 测试
//
// 验证 IncrementalIndicator 协议的算法等价性：
// - 增量逐根 step 的输出与 calculate() 全量结果对应位置末值精确一致
// - warm-up 期（history + step 累计 < period）正确返回 nil
// - 边界 case：history 空 / period=1 / period=count

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("WP-41 v2 commit 1/4 · MA 增量 API")
struct MAIncrementalTests {

    @Test("history 满 + 增量推进 50 根：每步与全量 calculate 末值精确一致（period=20）")
    func incrementalMatchesFull_HistoryFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try MA.calculate(kline: series, params: [20])
        let fullValues = full[0].values
        #expect(fullValues.count == 100)

        // history 用前 50 根（≥ period 20 · ring 已满）
        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try MA.makeIncrementalState(kline: history, params: [20])

        for i in historyCount..<bars.count {
            let row = MA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 1)
            #expect(row[0] == fullValues[i],
                    "incremental[\(i)] = \(String(describing: row[0])) ≠ full[\(i)] = \(String(describing: fullValues[i]))")
        }
    }

    @Test("history 不足 period · warm-up 期 step 返回 nil 直到 count == period")
    func incrementalWarmup_EmptyHistory() throws {
        let bars = makeBars(count: 30)
        let emptyHistory = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try MA.makeIncrementalState(kline: emptyHistory, params: [10])

        // 前 9 根（i=0..8）：warm-up · 应 nil
        for i in 0..<9 {
            let row = MA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil, "warm-up at i=\(i) should be nil")
        }
        // 第 10 根（i=9）：恰好 count == period · 应有值
        let row10 = MA.stepIncremental(state: &state, newBar: bars[9])
        #expect(row10[0] != nil)

        // 与全量对比 i=9 起
        let series = makeSeries(from: bars)
        let full = try MA.calculate(kline: series, params: [10])
        let fullValues = full[0].values
        #expect(row10[0] == fullValues[9])
        for i in 10..<bars.count {
            let row = MA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i])
        }
    }

    @Test("history 部分填充（< period）+ step 跨过 period 边界")
    func incrementalPartialHistory() throws {
        let bars = makeBars(count: 30)
        let historyCount = 6   // < period 10
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try MA.makeIncrementalState(kline: history, params: [10])

        // step bars[6..9] · 第 4 步（i=9）达到 period · 才有值
        for i in historyCount..<9 {
            let row = MA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil, "warm-up at i=\(i)")
        }
        let row9 = MA.stepIncremental(state: &state, newBar: bars[9])
        #expect(row9[0] != nil)

        let series = makeSeries(from: bars)
        let full = try MA.calculate(kline: series, params: [10])
        #expect(row9[0] == full[0].values[9])
        for i in 10..<bars.count {
            let row = MA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("period=1 边界：每步等于 newBar.close（round8 后）")
    func incrementalPeriod1() throws {
        let bars = makeBars(count: 5)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try MA.makeIncrementalState(kline: empty, params: [1])

        for bar in bars {
            let row = MA.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == Kernels.round8(bar.close))
        }
    }

    @Test("period 超过 history+steps 总数：始终 warm-up nil")
    func incrementalNeverWarmedUp() throws {
        let bars = makeBars(count: 5)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try MA.makeIncrementalState(kline: empty, params: [100])

        for bar in bars {
            let row = MA.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == nil)
        }
    }

    @Test("period 参数缺失抛 IndicatorError.invalidParameter")
    func incrementalMissingParam() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try MA.makeIncrementalState(kline: empty, params: [])
        }
    }

    // MARK: - Helpers

    private func makeBars(count: Int) -> [KLine] {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        return (0..<count).map { i in
            // 简单上行 + 周期 7 噪声 · 让 MA 各值有差异
            let noise = i % 7 - 3
            let close = Decimal(100 + i + noise)
            return KLine(
                instrumentID: "TEST",
                period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: close - 1,
                high: close + 2,
                low: close - 2,
                close: close,
                volume: 100 + i,
                openInterest: 0,
                turnover: 0
            )
        }
    }

    private func makeSeries(from bars: [KLine]) -> KLineSeries {
        KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
    }
}
