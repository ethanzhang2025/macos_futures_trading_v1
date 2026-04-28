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

}

// MARK: - WP-41 v2 commit 2/4 · EMA 增量 API

@Suite("WP-41 v2 commit 2/4 · EMA 增量 API")
struct EMAIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量 calculate 末值精确一致（period=12）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try EMA.calculate(kline: series, params: [12])
        let fullValues = full[0].values

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try EMA.makeIncrementalState(kline: history, params: [12])

        for i in historyCount..<bars.count {
            let row = EMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "EMA incremental[\(i)] = \(String(describing: row[0])) ≠ full[\(i)] = \(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 前 period-1 步返回 nil · 第 period 步起有值并匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 30)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try EMA.makeIncrementalState(kline: empty, params: [10])

        for i in 0..<9 {
            let row = EMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
        }
        let row10 = EMA.stepIncremental(state: &state, newBar: bars[9])
        #expect(row10[0] != nil)

        let series = makeSeries(from: bars)
        let full = try EMA.calculate(kline: series, params: [10])
        #expect(row10[0] == full[0].values[9])
        for i in 10..<bars.count {
            let row = EMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("period=1 边界：每步等于 close round8")
    func incrementalPeriod1() throws {
        let bars = makeBars(count: 5)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try EMA.makeIncrementalState(kline: empty, params: [1])
        for bar in bars {
            let row = EMA.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == Kernels.round8(bar.close))
        }
    }

    @Test("params 缺失抛 IndicatorError")
    func incrementalMissingParam() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try EMA.makeIncrementalState(kline: empty, params: [])
        }
    }
}

// MARK: - WP-41 v2 commit 2/4 · RSI 增量 API

@Suite("WP-41 v2 commit 2/4 · RSI 增量 API")
struct RSIIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量 calculate 末值精确一致（period=14）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try RSI.calculate(kline: series, params: [14])
        let fullValues = full[0].values

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try RSI.makeIncrementalState(kline: history, params: [14])

        for i in historyCount..<bars.count {
            let row = RSI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "RSI incremental[\(i)] = \(String(describing: row[0])) ≠ full[\(i)] = \(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 前 period-1 步返回 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 40)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try RSI.makeIncrementalState(kline: empty, params: [14])

        for i in 0..<13 {
            let row = RSI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
        }
        let row14 = RSI.stepIncremental(state: &state, newBar: bars[13])
        #expect(row14[0] != nil)

        let series = makeSeries(from: bars)
        let full = try RSI.calculate(kline: series, params: [14])
        #expect(row14[0] == full[0].values[13])
        for i in 14..<bars.count {
            let row = RSI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("全 0 价差（close 不变）→ avgU + avgD == 0 → RSI = 50")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<20).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try RSI.makeIncrementalState(kline: empty, params: [14])
        for i in 0..<13 {
            _ = RSI.stepIncremental(state: &state, newBar: flat[i])
        }
        let row14 = RSI.stepIncremental(state: &state, newBar: flat[13])
        #expect(row14[0] == Decimal(50))
    }

    @Test("period<2 抛错 / params 缺失抛错")
    func incrementalInvalidParam() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try RSI.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try RSI.makeIncrementalState(kline: empty, params: [1])
        }
    }
}

// MARK: - 共享 helper（fileprivate · 三个 suite 复用）

fileprivate func makeBars(count: Int) -> [KLine] {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    return (0..<count).map { i in
        // 简单上行 + 周期 7 噪声 · 让指标各值有差异
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

fileprivate func makeSeries(from bars: [KLine]) -> KLineSeries {
    KLineSeries(
        opens: bars.map(\.open),
        highs: bars.map(\.high),
        lows: bars.map(\.low),
        closes: bars.map(\.close),
        volumes: bars.map(\.volume),
        openInterests: bars.map { _ in 0 }
    )
}
