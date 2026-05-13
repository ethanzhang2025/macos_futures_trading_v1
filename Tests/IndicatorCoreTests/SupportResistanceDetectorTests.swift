// v17.166 · SupportResistanceDetector 单测

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.166 · SupportResistanceDetector 支撑阻力自动识别")
struct SupportResistanceDetectorTests {

    @Test("价格在 100 和 105 之间反复弹跳 · 应聚出 2 个 level（100 附近 + 105 附近）· touchCount >= 2 各")
    func detectsTwoMainLevels() throws {
        // 反复 100 / 105 / 100 / 105 · 每次 5% 摆动
        let prices: [Double] = [100, 105, 100, 105, 100, 105, 100, 105, 100, 105]
        let bars = makeBarsFromCloses(prices)
        let kline = makeSeries(bars: bars)
        let levels = try SupportResistanceDetector.detect(kline: kline, params: .default)
        #expect(levels.count == 2, "应聚出 2 个 level · 实际 \(levels.map(\.price))")
        // 价格升序
        #expect(levels[0].price < levels[1].price)
        // 都有多次触碰
        #expect(levels[0].touchCount >= 2)
        #expect(levels[1].touchCount >= 2)
    }

    @Test("当前价位于 level 之间 · isResistance 标记正确")
    func resistanceVsSupportLabeling() throws {
        // 反弹序列 · 末尾 close 在中间
        let prices: [Double] = [100, 110, 100, 110, 100, 110, 105]
        let bars = makeBarsFromCloses(prices)
        let kline = makeSeries(bars: bars)
        let levels = try SupportResistanceDetector.detect(kline: kline, params: .default)
        guard levels.count == 2 else {
            Issue.record("应有 2 个 level · 实际 \(levels.count)")
            return
        }
        // 当前 close ≈ 105 · level 1 (100 附近) = 支撑 · level 2 (110 附近) = 阻力
        #expect(levels[0].isResistance == false, "100 附近应为支撑")
        #expect(levels[1].isResistance == true, "110 附近应为阻力")
    }

    @Test("空 KLine · 返回空")
    func emptyKLine() throws {
        let empty = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        let levels = try SupportResistanceDetector.detect(kline: empty, params: .default)
        #expect(levels.isEmpty)
    }

    @Test("单调上涨无反转 · 无聚类成员 ≥ 2 · 返回空")
    func monotonicTrendNoLevels() throws {
        let prices = (0..<50).map { 100.0 + Double($0) }
        let bars = makeBarsFromCloses(prices)
        let levels = try SupportResistanceDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(levels.isEmpty)
    }

    @Test("强度归一化 · 最高 touchCount 的 strength = 1.0")
    func strengthNormalization() throws {
        // 主要在 100 反复 3 次 · 次要在 110 反复 2 次
        let prices: [Double] = [100, 110, 100, 110, 100, 110, 100]
        let bars = makeBarsFromCloses(prices)
        let levels = try SupportResistanceDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let maxStrength = levels.map(\.strength).max() ?? 0
        #expect(maxStrength == 1.0, "最高 strength 应归一化为 1.0")
    }

    @Test("maxLevels 限制输出数量")
    func maxLevelsLimit() throws {
        // 构造多个不同价位的反弹 · 验证 maxLevels=3 时输出 ≤ 3
        let prices: [Double] = [
            100, 110, 100, 110,   // 100/110 各 2 次
            120, 130, 120, 130,   // 120/130 各 2 次
            140, 150, 140, 150,   // 140/150 各 2 次
            160, 170, 160, 170    // 160/170 各 2 次
        ]
        let bars = makeBarsFromCloses(prices)
        var params = SupportResistanceParams.default
        params.maxLevels = 3
        let levels = try SupportResistanceDetector.detect(kline: makeSeries(bars: bars), params: params)
        #expect(levels.count <= 3, "输出限于 3 · 实际 \(levels.count)")
    }
}

// MARK: - helper

fileprivate func makeBarsFromCloses(_ closes: [Double]) -> [KLine] {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    return closes.enumerated().map { i, c in
        KLine(
            instrumentID: "TEST",
            period: .minute1,
            openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
            open: Decimal(c),
            high: Decimal(c + 0.1),
            low: Decimal(c - 0.1),
            close: Decimal(c),
            volume: 100,
            openInterest: 0,
            turnover: 0
        )
    }
}

fileprivate func makeSeries(bars: [KLine]) -> KLineSeries {
    KLineSeries(
        opens: bars.map(\.open),
        highs: bars.map(\.high),
        lows: bars.map(\.low),
        closes: bars.map(\.close),
        volumes: bars.map(\.volume),
        openInterests: bars.map { _ in 0 }
    )
}
