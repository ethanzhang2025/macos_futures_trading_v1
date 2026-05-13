// v17.163 · PatternDetector 单测
//
// 验证：
// - 4 种形态精确识别（手工构造典型 pivot 序列）
// - 阈值边界（肩对称 / 头突出 / 颈线 / 双顶容忍 / 中间回撤）
// - 重叠去重（同 endIndex 保留 confidence 最高）
// - 空序列 / 不足 pivot / 噪声不误报

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.163 · PatternDetector 形态识别")
struct PatternDetectorTests {

    // MARK: - 头肩顶（peak-trough-peak-trough-peak · 头高于肩 · 肩对称）

    @Test("头肩顶 · 典型 pivot 价格 100/90/115/89/101 · 检出 confidence > 0.5")
    func detectHeadAndShouldersTop() throws {
        // 设计 K 线：左肩 100 · 谷 90 · 头 115 · 谷 89 · 右肩 101
        // ZigZag percent=3 应该正好捕获这 5 个 pivot（5/100 ≈ 5% 摆动 · > 3% 阈值）
        let prices: [Double] = [100, 100, 90, 90, 90, 115, 115, 89, 89, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let kline = makeSeries(bars: bars)
        let detected = try PatternDetector.detect(kline: kline, params: .default)
        let hsTop = detected.filter { $0.kind == .headAndShouldersTop }
        #expect(hsTop.count >= 1, "应至少检出 1 个头肩顶 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = hsTop.first {
            #expect(p.pivotPrices.count == 5)
            #expect(p.confidence > 0.5)
        }
    }

    @Test("头肩顶 · 肩极不对称（左肩 100 / 右肩 130）· 不应识别（shoulderDiff > 10%）")
    func headAndShouldersTopRejectsAsymmetricShoulders() throws {
        let prices: [Double] = [100, 90, 115, 89, 130, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .headAndShouldersTop }.isEmpty)
    }

    @Test("头肩顶 · 头不突出（头 102 vs 肩 100）· 不应识别（prominence < 3%）")
    func headAndShouldersTopRejectsWeakHead() throws {
        let prices: [Double] = [100, 90, 102, 89, 100, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .headAndShouldersTop }.isEmpty)
    }

    // MARK: - 头肩底（mirror）

    @Test("头肩底 · 典型 pivot 100/110/85/111/99 · 检出")
    func detectHeadAndShouldersBottom() throws {
        let prices: [Double] = [100, 100, 110, 110, 85, 85, 111, 111, 99, 99, 105]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let hsBot = detected.filter { $0.kind == .headAndShouldersBottom }
        #expect(hsBot.count >= 1, "应至少检出 1 个头肩底")
        if let p = hsBot.first {
            #expect(p.kind.direction == 1, "看多反转")
        }
    }

    // MARK: - 双顶

    @Test("双顶 · 典型 pivot 100/90/101 · 检出 · 双底 mirror")
    func detectDoubleTop() throws {
        let prices: [Double] = [100, 100, 90, 90, 90, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let dTop = detected.filter { $0.kind == .doubleTop }
        #expect(dTop.count >= 1)
        if let p = dTop.first {
            #expect(p.pivotPrices.count == 3)
            #expect(p.kind.direction == -1)
        }
    }

    @Test("双顶 · 两顶差距过大（100 vs 110）· 不应识别（topDiff > 3%）")
    func doubleTopRejectsLargeGap() throws {
        let prices: [Double] = [100, 90, 110, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .doubleTop }.isEmpty)
    }

    @Test("双顶 · 中间回撤太浅（100 vs 99 vs 100）· 不应识别（retracement < 2%）")
    func doubleTopRejectsShallowRetracement() throws {
        let prices: [Double] = [100, 99, 100, 95]
        let bars = makeBarsFromCloses(prices)
        // ZigZag 3% 阈值下 · 99 → 100 仅 1% 不算 pivot · 故 pivot 不足直接不出形态
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .doubleTop }.isEmpty)
    }

    @Test("双底 · 典型 pivot 100/110/101 · 检出")
    func detectDoubleBottom() throws {
        let prices: [Double] = [100, 100, 110, 110, 101, 101, 110]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let dBot = detected.filter { $0.kind == .doubleBottom }
        #expect(dBot.count >= 1)
        if let p = dBot.first {
            #expect(p.kind.direction == 1)
        }
    }

    // MARK: - 边界

    @Test("空 KLine · 返回空列表")
    func emptyKLine() throws {
        let kline = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        let detected = try PatternDetector.detect(kline: kline, params: .default)
        #expect(detected.isEmpty)
    }

    @Test("单调上涨 · 无 pivot · 不出形态")
    func monotonicUptrend() throws {
        let prices = (0..<50).map { 100.0 + Double($0) }
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.isEmpty)
    }

    // MARK: - 重叠去重

    @Test("同 endIndex 多命中 · 仅保留最高 confidence（dedupByEndIndex）")
    func dedupByEndIndex() throws {
        // 设计：5 pivot 同时满足 HS top + 内部 3 pivot 双顶
        // 100 / 90 / 115 / 89 / 101 ← HS top
        //          ↓ 内部 3 个：90 / 115 / 89 → 不算 doubleTop（90/89 是 trough · 115 是 peak）
        //          正确双顶覆盖：100/90/101 仍是另一个窗口（3 pivot 在 i=0..2 + 0..3? 取决于 pivot 索引）
        // ZigZag 给出的 pivot 数量取决于 percent · 这里只验证 dedup 不重复输出 endIndex
        let prices: [Double] = [100, 100, 90, 90, 90, 115, 115, 89, 89, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let ends = detected.map(\.endIndex)
        #expect(Set(ends).count == ends.count, "dedup 后 endIndex 不重复 · 实际 \(ends)")
    }

    // MARK: - 排序

    @Test("结果按 startIndex 升序")
    func sortedByStartIndex() throws {
        // 构造两段独立的双顶：第一段在 0..15 · 第二段在 30..45
        let segment1: [Double] = [100, 100, 90, 90, 101, 101, 95, 95]
        let connector: [Double] = Array(repeating: 95.0, count: 20)
        let segment2: [Double] = [80, 80, 90, 90, 80, 80, 85]
        let prices = segment1 + connector + segment2
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let starts = detected.map(\.startIndex)
        #expect(starts == starts.sorted(), "starts 应升序 · 实际 \(starts)")
    }
}

// MARK: - 共享 helper

fileprivate func makeBarsFromCloses(_ closes: [Double]) -> [KLine] {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    return closes.enumerated().map { i, c in
        // OHLC 都取 close ± 微小噪声 · 让 ZigZag 仅基于 close 判断
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
