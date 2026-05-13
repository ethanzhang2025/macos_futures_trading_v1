// v17.156 · OverlayIncrementalStates 单测
//
// 验证 9 overlay 增量化的两层正确性：
// 1. 每个单 overlay 启用时 · prime(history) + step×K 的累积输出 == MainChartOverlayCompute.compute(history+K 根).values
// 2. 多 overlay 同启用时 · 列顺序与 MainChartOverlayCompute 完全一致（KC 重排 / Pivot 5 列 / Ichimoku 4 列 / SuperTrend 1 列）
//
// Linux 兼容（无 SwiftUI 依赖 · MainApp 模块 import 通过即可）· 单测在 Linux 端跑通保护切机风险

import Testing
import Foundation
import Shared
import IndicatorCore
@testable import MainApp

@Suite("v17.156 · OverlayIncrementalStates 增量等价 + 列顺序")
struct OverlayIncrementalStatesTests {

    // MARK: - 9 个 overlay 单独启用 · prime + step 累积输出 == 全量 calculate

    @Test("VWAP 单 overlay · 50 history + 50 step · 每根值与 calculate 全量一致")
    func vwapIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.vwap, historyCount: 50, stepCount: 50)
    }

    @Test("Pivot 单 overlay · 5 列（drop R3/S3）· prime+step 与 compute 全量一致")
    func pivotIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.pivot, historyCount: 50, stepCount: 50)
    }

    @Test("SuperTrend 单 overlay · 1 列（drop DIR）· period=10 mult=3 · 增量等价")
    func superTrendIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.superTrend, historyCount: 80, stepCount: 30)
    }

    @Test("Ichimoku 单 overlay · 4 列（drop CHIKOU）· 9/26/52 · 增量等价（含 senkou 延迟 26 根）")
    func ichimokuIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.ichimoku, historyCount: 120, stepCount: 30)
    }

    @Test("SAR 单 overlay · 1 列 · step=0.02 max=0.2 · 增量等价")
    func sarIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.sar, historyCount: 50, stepCount: 50)
    }

    @Test("PriceChannel 单 overlay · 2 列 · period=20 · 增量等价")
    func priceChannelIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.priceChannel, historyCount: 50, stepCount: 50)
    }

    @Test("Envelopes 单 overlay · 3 列 mid/upper/lower · period=20 percent=2.5 · 增量等价")
    func envelopesIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.envelopes, historyCount: 50, stepCount: 50)
    }

    @Test("Donchian 单 overlay · 3 列 upper/mid/lower · period=20 · 增量等价")
    func donchianIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.donchian, historyCount: 50, stepCount: 50)
    }

    @Test("Keltner 单 overlay · 3 列 upper/mid/lower（KC step 返回 mid/upper/lower 已重排）· 增量等价")
    func keltnerIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.keltner, historyCount: 80, stepCount: 30)
    }

    // v17.159 · 3 改进型均线 parity

    @Test("HMA 单 overlay · 1 列 · period=16 · 增量等价")
    func hmaIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.hma, historyCount: 50, stepCount: 30)
    }

    @Test("DEMA 单 overlay · 1 列 · period=20 · 增量等价（双 EMA 复合）")
    func demaIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.dema, historyCount: 50, stepCount: 30)
    }

    @Test("TEMA 单 overlay · 1 列 · period=20 · 增量等价（三 EMA 复合）")
    func temaIncrementalEquivalence() throws {
        try assertSingleOverlayParity(.tema, historyCount: 50, stepCount: 30)
    }

    // MARK: - 列顺序：多 overlay 启用 · OverlayIncrementalStates.step 输出 == compute(bars).flatMap(\.values.last)

    @Test("12 overlay 全开 · step 输出列顺序与 MainChartOverlayCompute 完全一致（26 列）")
    func allEnabledColumnOrder() throws {
        let bars = makeBars(count: 200)
        let history = bars.prefix(150)
        let last50 = Array(bars[150...])

        var book = MainChartOverlayBook()
        for kind in MainChartOverlayKind.allCases {
            book.setEnabled(kind, true)
        }

        let kline = makeSeries(from: Array(history))
        var states = OverlayIncrementalStates(history: kline, book: book)

        // 累积每根 step 输出
        var historyArr = Array(history)
        for newBar in last50 {
            let stepOut = states.step(newBar: newBar)
            historyArr.append(newBar)
            // 同步对照：MainChartOverlayCompute 全量 compute 取末值列
            let computeOut = MainChartOverlayCompute.compute(bars: historyArr, book: book)
            let lastValues: [Decimal?] = computeOut.map { $0.values.last ?? nil }
            #expect(stepOut.count == lastValues.count,
                    "列数不匹配 step=\(stepOut.count) compute=\(lastValues.count)")
            for (i, (a, b)) in zip(stepOut, lastValues).enumerated() {
                #expect(a == b,
                        "列[\(i)] step=\(String(describing: a)) ≠ compute=\(String(describing: b)) · series[\(i)].name=\(computeOut[i].name)")
            }
        }
    }

    @Test("混合启用（vwap + ichimoku + keltner）· 列顺序 1+4+3=8 列 · 与 compute 一致")
    func mixedOverlayColumnOrder() throws {
        var book = MainChartOverlayBook()
        book.setEnabled(.vwap, true)
        book.setEnabled(.ichimoku, true)
        book.setEnabled(.keltner, true)

        let bars = makeBars(count: 200)
        let history = Array(bars.prefix(150))
        let last50 = Array(bars[150...])

        let kline = makeSeries(from: history)
        var states = OverlayIncrementalStates(history: kline, book: book)

        var historyArr = history
        for newBar in last50 {
            let stepOut = states.step(newBar: newBar)
            historyArr.append(newBar)
            let computeOut = MainChartOverlayCompute.compute(bars: historyArr, book: book)
            #expect(stepOut.count == computeOut.count, "8 列总数")
            for (i, series) in computeOut.enumerated() {
                #expect(stepOut[i] == series.values.last ?? nil,
                        "列[\(i)] name=\(series.name) step=\(String(describing: stepOut[i])) ≠ compute last=\(String(describing: series.values.last ?? nil))")
            }
        }
    }

    @Test("全空 book · step 返回空数组")
    func noOverlayEnabled() throws {
        let bars = makeBars(count: 30)
        let kline = makeSeries(from: bars)
        var states = OverlayIncrementalStates(history: kline, book: MainChartOverlayBook())
        let out = states.step(newBar: makeBar(at: 30))
        #expect(out.isEmpty)
    }

    // MARK: - helper

    /// 单 overlay parity assertion · 在 (historyCount + stepCount) 范围内每根 step 输出与 compute 全量末值一致
    private func assertSingleOverlayParity(
        _ kind: MainChartOverlayKind,
        historyCount: Int,
        stepCount: Int
    ) throws {
        var book = MainChartOverlayBook()
        book.setEnabled(kind, true)

        let bars = makeBars(count: historyCount + stepCount)
        let history = Array(bars.prefix(historyCount))
        let kline = makeSeries(from: history)
        var states = OverlayIncrementalStates(history: kline, book: book)

        var historyArr = history
        for i in 0..<stepCount {
            let newBar = bars[historyCount + i]
            let stepOut = states.step(newBar: newBar)
            historyArr.append(newBar)
            let computeOut = MainChartOverlayCompute.compute(bars: historyArr, book: book)
            let computeLast: [Decimal?] = computeOut.map { $0.values.last ?? nil }
            #expect(stepOut.count == computeLast.count, "\(kind) 列数")
            for (col, (a, b)) in zip(stepOut, computeLast).enumerated() {
                #expect(a == b,
                        "\(kind) step[\(i)] col[\(col)] = \(String(describing: a)) ≠ compute last = \(String(describing: b))")
            }
        }
    }
}

// MARK: - 共享 helper（与 IndicatorCoreTests/IncrementalIndicatorTests 同 pattern）

fileprivate func makeBars(count: Int) -> [KLine] {
    (0..<count).map { i in makeBar(at: i) }
}

fileprivate func makeBar(at i: Int) -> KLine {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
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
