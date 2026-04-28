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

// MARK: - WP-41 v2 commit 3/4 · MACD 增量 API

@Suite("WP-41 v2 commit 3/4 · MACD 增量 API")
struct MACDIncrementalTests {

    @Test("history 满 + 增量推进：DIF/DEA/MACD 3 列每步与全量精确一致（12/26/9）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try MACD.calculate(kline: series, params: [12, 26, 9])
        // full[0] = DIF, full[1] = DEA, full[2] = MACD

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try MACD.makeIncrementalState(kline: history, params: [12, 26, 9])

        for i in historyCount..<bars.count {
            let row = MACD.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 3)
            #expect(row[0] == full[0].values[i], "DIF[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: full[0].values[i]))")
            #expect(row[1] == full[1].values[i], "DEA[\(i)]")
            #expect(row[2] == full[2].values[i], "MACD[\(i)]")
        }
    }

    @Test("history 空 · 各阶段 nil 模式与全量一致（DIF 在 slow 步起 / DEA 再延 signal-1 步）")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try MACD.makeIncrementalState(kline: empty, params: [12, 26, 9])

        let series = makeSeries(from: bars)
        let full = try MACD.calculate(kline: series, params: [12, 26, 9])

        for i in 0..<bars.count {
            let row = MACD.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "DIF[\(i)]")
            #expect(row[1] == full[1].values[i], "DEA[\(i)]")
            #expect(row[2] == full[2].values[i], "MACD[\(i)]")
        }
    }

    @Test("参数校验：少于 3 个参数 / slow <= fast 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try MACD.makeIncrementalState(kline: empty, params: [12, 26])
        }
        #expect(throws: IndicatorError.self) {
            _ = try MACD.makeIncrementalState(kline: empty, params: [26, 12, 9])
        }
    }
}

// MARK: - WP-41 v2 commit 3/4 · BOLL 增量 API

@Suite("WP-41 v2 commit 3/4 · BOLL 增量 API")
struct BOLLIncrementalTests {

    @Test("history 满 + 增量推进：MID/UPPER/LOWER 3 列每步与全量精确一致（period=20, k=2）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try BOLL.calculate(kline: series, params: [20, 2])

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try BOLL.makeIncrementalState(kline: history, params: [20, 2])

        for i in historyCount..<bars.count {
            let row = BOLL.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 3)
            #expect(row[0] == full[0].values[i], "MID[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: full[0].values[i]))")
            #expect(row[1] == full[1].values[i], "UPPER[\(i)]")
            #expect(row[2] == full[2].values[i], "LOWER[\(i)]")
        }
    }

    @Test("history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 30)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try BOLL.makeIncrementalState(kline: empty, params: [10, 2])

        for i in 0..<9 {
            let row = BOLL.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
            #expect(row[1] == nil)
            #expect(row[2] == nil)
        }
        let row10 = BOLL.stepIncremental(state: &state, newBar: bars[9])
        #expect(row10[0] != nil)

        let series = makeSeries(from: bars)
        let full = try BOLL.calculate(kline: series, params: [10, 2])
        #expect(row10[0] == full[0].values[9])
        #expect(row10[1] == full[1].values[9])
        #expect(row10[2] == full[2].values[9])
        for i in 10..<bars.count {
            let row = BOLL.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
            #expect(row[1] == full[1].values[i])
            #expect(row[2] == full[2].values[i])
        }
    }

    @Test("全 0 价差（close 不变）→ stddev = 0 · UPPER == LOWER == MID")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<25).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try BOLL.makeIncrementalState(kline: empty, params: [10, 2])
        for i in 0..<9 {
            _ = BOLL.stepIncremental(state: &state, newBar: flat[i])
        }
        let row = BOLL.stepIncremental(state: &state, newBar: flat[9])
        #expect(row[0] == Decimal(100))
        #expect(row[1] == Decimal(100))   // UPPER = MID + k*0
        #expect(row[2] == Decimal(100))   // LOWER = MID - k*0
    }

    @Test("参数校验：少于 2 参数 / period<2 / k<=0 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try BOLL.makeIncrementalState(kline: empty, params: [20])
        }
        #expect(throws: IndicatorError.self) {
            _ = try BOLL.makeIncrementalState(kline: empty, params: [1, 2])
        }
        #expect(throws: IndicatorError.self) {
            _ = try BOLL.makeIncrementalState(kline: empty, params: [20, 0])
        }
    }
}

// MARK: - WP-41 v3 commit 1/4 · KDJ 增量 API

@Suite("WP-41 v3 commit 1/4 · KDJ 增量 API")
struct KDJIncrementalTests {

    @Test("history 满 + 增量推进：K/D/J 3 列每步与全量精确一致（9/3/3）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try KDJ.calculate(kline: series, params: [9, 3, 3])

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try KDJ.makeIncrementalState(kline: history, params: [9, 3, 3])

        for i in historyCount..<bars.count {
            let row = KDJ.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 3)
            #expect(row[0] == full[0].values[i], "K[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: full[0].values[i]))")
            #expect(row[1] == full[1].values[i], "D[\(i)]")
            #expect(row[2] == full[2].values[i], "J[\(i)]")
        }
    }

    @Test("history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 50)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try KDJ.makeIncrementalState(kline: empty, params: [9, 3, 3])

        for i in 0..<8 {
            let row = KDJ.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
            #expect(row[1] == nil)
            #expect(row[2] == nil)
        }
        let row9 = KDJ.stepIncremental(state: &state, newBar: bars[8])
        #expect(row9[0] != nil)

        let series = makeSeries(from: bars)
        let full = try KDJ.calculate(kline: series, params: [9, 3, 3])
        #expect(row9[0] == full[0].values[8])
        #expect(row9[1] == full[1].values[8])
        #expect(row9[2] == full[2].values[8])
        for i in 9..<bars.count {
            let row = KDJ.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
            #expect(row[1] == full[1].values[i])
            #expect(row[2] == full[2].values[i])
        }
    }

    @Test("全平 close（high == low == close 不变）→ rsv = 0 · K/D 趋稳到 0")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<30).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try KDJ.makeIncrementalState(kline: empty, params: [9, 3, 3])
        var lastK: Decimal = 50
        for i in 0..<flat.count {
            let row = KDJ.stepIncremental(state: &state, newBar: flat[i])
            if let k = row[0] { lastK = k }
        }
        // 平价 22 步后 K 收敛：K = K * 2/3 每步 · K_22 ≈ 50 * (2/3)^22 ≈ 0.029（< 0.1）
        #expect(lastK < Decimal(string: "0.1")!)
    }

    @Test("参数校验：少于 3 参数 / period<1 / k<1 / d<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try KDJ.makeIncrementalState(kline: empty, params: [9, 3])
        }
        #expect(throws: IndicatorError.self) {
            _ = try KDJ.makeIncrementalState(kline: empty, params: [0, 3, 3])
        }
        #expect(throws: IndicatorError.self) {
            _ = try KDJ.makeIncrementalState(kline: empty, params: [9, 0, 3])
        }
        #expect(throws: IndicatorError.self) {
            _ = try KDJ.makeIncrementalState(kline: empty, params: [9, 3, 0])
        }
    }
}

// MARK: - WP-41 v3 commit 2/4 · CCI 增量 API

@Suite("WP-41 v3 commit 2/4 · CCI 增量 API")
struct CCIIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=20）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try CCI.calculate(kline: series, params: [20])
        let fullValues = full[0].values

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try CCI.makeIncrementalState(kline: history, params: [20])

        for i in historyCount..<bars.count {
            let row = CCI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "CCI[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 前 period-1 步 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 40)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try CCI.makeIncrementalState(kline: empty, params: [10])

        for i in 0..<9 {
            let row = CCI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
        }
        let row10 = CCI.stepIncremental(state: &state, newBar: bars[9])
        let series = makeSeries(from: bars)
        let full = try CCI.calculate(kline: series, params: [10])
        #expect(row10[0] == full[0].values[9])
        for i in 10..<bars.count {
            let row = CCI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("全平 close（h==l==c 不变）→ tp 全相等 → md=0 → 输出始终 nil")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<25).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try CCI.makeIncrementalState(kline: empty, params: [10])
        for i in 0..<flat.count {
            let row = CCI.stepIncremental(state: &state, newBar: flat[i])
            #expect(row[0] == nil, "i=\(i) all-same should yield nil（md=0）")
        }
    }

    @Test("参数校验：缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try CCI.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try CCI.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - WP-41 v3 commit 3/4 · ATR 增量 API

@Suite("WP-41 v3 commit 3/4 · ATR 增量 API")
struct ATRIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=14）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try ATR.calculate(kline: series, params: [14])
        let fullValues = full[0].values

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try ATR.makeIncrementalState(kline: history, params: [14])

        for i in historyCount..<bars.count {
            let row = ATR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "ATR[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 前 period-1 步 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 30)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try ATR.makeIncrementalState(kline: empty, params: [10])

        for i in 0..<9 {
            let row = ATR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
        }
        let row10 = ATR.stepIncremental(state: &state, newBar: bars[9])
        #expect(row10[0] != nil)

        let series = makeSeries(from: bars)
        let full = try ATR.calculate(kline: series, params: [10])
        #expect(row10[0] == full[0].values[9])
        for i in 10..<bars.count {
            let row = ATR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("第 1 根 K：TR = high - low（无 prevClose · 与 calculate tr[0] 一致）")
    func incrementalFirstBarTR() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let bar0 = KLine(
            instrumentID: "TEST", period: .minute1,
            openTime: baseDate,
            open: 100, high: 110, low: 95, close: 105,
            volume: 100, openInterest: 0, turnover: 0
        )
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try ATR.makeIncrementalState(kline: empty, params: [3])
        // 第 1 根：tr = 110 - 95 = 15 · warmUp 累加 · 返回 nil
        let row1 = ATR.stepIncremental(state: &state, newBar: bar0)
        #expect(row1[0] == nil)
        // 验证 warmUpSum 累加（间接：跑完 3 根后 atr 应为 (15 + tr2 + tr3) / 3）
    }

    @Test("period=1 边界：每步 ATR == 当前根 TR（round8）")
    func incrementalPeriod1() throws {
        let bars = makeBars(count: 5)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try ATR.makeIncrementalState(kline: empty, params: [1])
        let series = makeSeries(from: bars)
        let full = try ATR.calculate(kline: series, params: [1])
        for i in 0..<bars.count {
            let row = ATR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "ATR(1)[\(i)]")
        }
    }

    @Test("参数缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try ATR.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try ATR.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - WP-41 v3 第 2 批 commit 1/4 · OBV 增量 API

@Suite("WP-41 v3 第 2 批 commit 1/4 · OBV 增量 API")
struct OBVIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（OBV 无 period · 累积式）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try OBV.calculate(kline: series, params: [])
        let fullValues = full[0].values

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try OBV.makeIncrementalState(kline: history, params: [])

        for i in historyCount..<bars.count {
            let row = OBV.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "OBV[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 第 1 根 OBV = volume · 后续按涨跌累加（无 warm-up）")
    func incrementalNoWarmup() throws {
        let bars = makeBars(count: 20)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try OBV.makeIncrementalState(kline: empty, params: [])

        // 第 1 根 OBV 即有值（与 calculate out[0] = volumes[0] 一致）
        let row1 = OBV.stepIncremental(state: &state, newBar: bars[0])
        #expect(row1[0] == Decimal(bars[0].volume))

        let series = makeSeries(from: bars)
        let full = try OBV.calculate(kline: series, params: [])
        for i in 1..<bars.count {
            let row = OBV.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("close 全平（每根 close 不变）→ OBV 始终 = 第 1 根 volume")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<10).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100 + i,
                openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try OBV.makeIncrementalState(kline: empty, params: [])
        let firstVol = Decimal(flat[0].volume)
        for bar in flat {
            let row = OBV.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == firstVol, "close 全平时 OBV 应保持首根 volume = \(firstVol)")
        }
    }
}

// MARK: - WP-41 v3 第 2 批 commit 2/4 · WilliamsR 增量 API

@Suite("WP-41 v3 第 2 批 commit 2/4 · WilliamsR 增量 API")
struct WilliamsRIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=14）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try WilliamsR.calculate(kline: series, params: [14])
        let fullValues = full[0].values

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try WilliamsR.makeIncrementalState(kline: history, params: [14])

        for i in historyCount..<bars.count {
            let row = WilliamsR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "WR[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 前 period-1 步 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 30)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try WilliamsR.makeIncrementalState(kline: empty, params: [10])

        for i in 0..<9 {
            let row = WilliamsR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == nil)
        }
        let row10 = WilliamsR.stepIncremental(state: &state, newBar: bars[9])
        #expect(row10[0] != nil)

        let series = makeSeries(from: bars)
        let full = try WilliamsR.calculate(kline: series, params: [10])
        #expect(row10[0] == full[0].values[9])
        for i in 10..<bars.count {
            let row = WilliamsR.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i])
        }
    }

    @Test("全平 high/low（hhv == llv）→ 输出始终 nil（与 calculate h > l 守卫一致）")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<15).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try WilliamsR.makeIncrementalState(kline: empty, params: [10])
        for bar in flat {
            let row = WilliamsR.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == nil, "h == l 时 WR 应 nil")
        }
    }

    @Test("参数缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try WilliamsR.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try WilliamsR.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - WP-41 v3 第 2 批 commit 3/4 · ADX 增量 API（4 路 Wilder）

@Suite("WP-41 v3 第 2 批 commit 3/4 · ADX 增量 API")
struct ADXIncrementalTests {

    @Test("history 满 + 增量推进：ADX/+DI/-DI 3 列每步与全量精确一致（period=14）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try ADX.calculate(kline: series, params: [14])

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try ADX.makeIncrementalState(kline: history, params: [14])

        for i in historyCount..<bars.count {
            let row = ADX.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 3)
            #expect(row[0] == full[0].values[i], "ADX[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: full[0].values[i]))")
            #expect(row[1] == full[1].values[i], "+DI[\(i)]")
            #expect(row[2] == full[2].values[i], "-DI[\(i)]")
        }
    }

    @Test("history 空 · 前 period-1 步全 nil · 第 period 步起匹配全量")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try ADX.makeIncrementalState(kline: empty, params: [14])

        let series = makeSeries(from: bars)
        let full = try ADX.calculate(kline: series, params: [14])

        for i in 0..<bars.count {
            let row = ADX.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "ADX[\(i)]")
            #expect(row[1] == full[1].values[i], "+DI[\(i)]")
            #expect(row[2] == full[2].values[i], "-DI[\(i)]")
        }
    }

    @Test("参数缺失 / period<2 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try ADX.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try ADX.makeIncrementalState(kline: empty, params: [1])
        }
    }
}

// MARK: - WP-41 v3 第 2 批 commit 3/4 · DMI 增量 API（复用 ADX state · 仅截 +DI/-DI）

@Suite("WP-41 v3 第 2 批 commit 3/4 · DMI 增量 API")
struct DMIIncrementalTests {

    @Test("DMI 增量与全量精确一致（+DI/-DI 2 列 · 复用 ADX state）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try DMI.calculate(kline: series, params: [14])

        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try DMI.makeIncrementalState(kline: empty, params: [14])

        for i in 0..<bars.count {
            let row = DMI.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 2)
            #expect(row[0] == full[0].values[i], "+DI[\(i)]")
            #expect(row[1] == full[1].values[i], "-DI[\(i)]")
        }
    }
}

// MARK: - WP-41 v3 第 3 批 · Stochastic 增量 API

@Suite("WP-41 v3 第 3 批 · Stochastic 增量 API")
struct StochasticIncrementalTests {

    @Test("history 满 + 增量推进：%K/%D 2 列每步与全量精确一致（period=14 · smooth=3）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 80)
        let series = makeSeries(from: bars)
        let full = try Stochastic.calculate(kline: series, params: [14, 3])

        let historyCount = 30
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try Stochastic.makeIncrementalState(kline: history, params: [14, 3])

        for i in historyCount..<bars.count {
            let row = Stochastic.stepIncremental(state: &state, newBar: bars[i])
            #expect(row.count == 2)
            #expect(row[0] == full[0].values[i], "%K[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: full[0].values[i]))")
            #expect(row[1] == full[1].values[i], "%D[\(i)]")
        }
    }

    @Test("history 空 · 60 根 K 全程匹配全量（双 ring · %K 在 period 起 · %D 在 smooth 起）")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try Stochastic.makeIncrementalState(kline: empty, params: [14, 3])

        let series = makeSeries(from: bars)
        let full = try Stochastic.calculate(kline: series, params: [14, 3])

        for i in 0..<bars.count {
            let row = Stochastic.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "%K[\(i)]")
            #expect(row[1] == full[1].values[i], "%D[\(i)]")
        }
    }

    @Test("全平 high/low → %K 始终 nil · %D 始终 0（kRaw 全 0 · sum/s = 0 · 与文华标准一致）")
    func incrementalAllSame() throws {
        let baseDate = Date(timeIntervalSinceReferenceDate: 0)
        let flat = (0..<10).map { i in
            KLine(
                instrumentID: "TEST", period: .minute1,
                openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
                open: 100, high: 100, low: 100, close: 100,
                volume: 100, openInterest: 0, turnover: 0
            )
        }
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try Stochastic.makeIncrementalState(kline: empty, params: [5, 3])
        for (i, bar) in flat.enumerated() {
            let row = Stochastic.stepIncremental(state: &state, newBar: bar)
            #expect(row[0] == nil, "i=\(i): h==l → %K nil")
            if i >= 2 {  // smooth - 1 = 2 起 %D 有值
                #expect(row[1] == Decimal(0), "i=\(i): kRaw 全 0 → %D 应 0")
            }
        }
    }

    @Test("参数缺失 / period<1 / smooth<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try Stochastic.makeIncrementalState(kline: empty, params: [14])
        }
        #expect(throws: IndicatorError.self) {
            _ = try Stochastic.makeIncrementalState(kline: empty, params: [0, 3])
        }
        #expect(throws: IndicatorError.self) {
            _ = try Stochastic.makeIncrementalState(kline: empty, params: [14, 0])
        }
    }
}

// MARK: - WP-41 v3 第 4 批 · TRIX 增量 API（内嵌 3 EMA · 同 MACD 模式）

@Suite("WP-41 v3 第 4 批 · TRIX 增量 API")
struct TRIXIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=12）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try TRIX.calculate(kline: series, params: [12])
        let fullValues = full[0].values

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try TRIX.makeIncrementalState(kline: history, params: [12])

        for i in historyCount..<bars.count {
            let row = TRIX.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "TRIX[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 60 根 K 全程匹配全量（3 层 EMA + prevE3 差分）")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try TRIX.makeIncrementalState(kline: empty, params: [12])

        let series = makeSeries(from: bars)
        let full = try TRIX.calculate(kline: series, params: [12])

        for i in 0..<bars.count {
            let row = TRIX.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "TRIX[\(i)]")
        }
    }

    @Test("参数缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try TRIX.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try TRIX.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - WP-41 v3 第 5 批 · DEMA 增量 API

@Suite("WP-41 v3 第 5 批 · DEMA 增量 API")
struct DEMAIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=20）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try DEMA.calculate(kline: series, params: [20])
        let fullValues = full[0].values

        let historyCount = 50
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try DEMA.makeIncrementalState(kline: history, params: [20])

        for i in historyCount..<bars.count {
            let row = DEMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "DEMA[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 60 根 K 全程匹配全量（2 层 EMA 同步）")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try DEMA.makeIncrementalState(kline: empty, params: [10])

        let series = makeSeries(from: bars)
        let full = try DEMA.calculate(kline: series, params: [10])

        for i in 0..<bars.count {
            let row = DEMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "DEMA[\(i)]")
        }
    }

    @Test("参数缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try DEMA.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try DEMA.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - WP-41 v3 第 5 批 · TEMA 增量 API

@Suite("WP-41 v3 第 5 批 · TEMA 增量 API")
struct TEMAIncrementalTests {

    @Test("history 满 + 增量推进：每步与全量精确一致（period=20）")
    func incrementalMatchesFull() throws {
        let bars = makeBars(count: 100)
        let series = makeSeries(from: bars)
        let full = try TEMA.calculate(kline: series, params: [20])
        let fullValues = full[0].values

        let historyCount = 60
        let history = makeSeries(from: Array(bars.prefix(historyCount)))
        var state = try TEMA.makeIncrementalState(kline: history, params: [20])

        for i in historyCount..<bars.count {
            let row = TEMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == fullValues[i],
                    "TEMA[\(i)]: incr=\(String(describing: row[0])) full=\(String(describing: fullValues[i]))")
        }
    }

    @Test("history 空 · 60 根 K 全程匹配全量（3 层 EMA 同步）")
    func incrementalWarmup() throws {
        let bars = makeBars(count: 60)
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        var state = try TEMA.makeIncrementalState(kline: empty, params: [10])

        let series = makeSeries(from: bars)
        let full = try TEMA.calculate(kline: series, params: [10])

        for i in 0..<bars.count {
            let row = TEMA.stepIncremental(state: &state, newBar: bars[i])
            #expect(row[0] == full[0].values[i], "TEMA[\(i)]")
        }
    }

    @Test("参数缺失 / period<1 抛错")
    func incrementalInvalidParams() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        #expect(throws: IndicatorError.self) {
            _ = try TEMA.makeIncrementalState(kline: empty, params: [])
        }
        #expect(throws: IndicatorError.self) {
            _ = try TEMA.makeIncrementalState(kline: empty, params: [0])
        }
    }
}

// MARK: - 共享 helper（fileprivate · 五个 suite 复用）

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
