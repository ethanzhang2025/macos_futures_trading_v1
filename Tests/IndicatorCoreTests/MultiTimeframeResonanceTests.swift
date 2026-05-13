// v17.170 · MultiTimeframeResonance 单测
//
// 覆盖：
// - 聚合 minute1 → minute5（OHLCV/openTime）· 同周期 · target<base · 空 bars
// - detectSignals · EMA / MACD 金叉死叉精确检出 · 数据不足
// - detect() 完整流水线 · 信号映射回 base bar index · 空 base
// - defaultTargets 表
// - enabledKinds 过滤
// - ResonanceSignalKind metadata 全集

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.170 · MultiTimeframeResonance 多周期共振")
struct MultiTimeframeResonanceTests {

    // MARK: - 聚合

    @Test("aggregate minute1 → minute5 · 10 bars → 2 buckets · OHLCV 正确")
    func aggregateMinute1ToMinute5() {
        // 第 1 桶 i=0..4 价格 100/101/102/103/104 · 第 2 桶 i=5..9 价格 105/106/107/108/109
        let bars = makeBars(period: .minute1, closes: [100, 101, 102, 103, 104, 105, 106, 107, 108, 109])
        let agg = MultiTimeframeResonance.aggregate(bars: bars, targetPeriod: .minute5)
        #expect(agg.count == 2)
        #expect(agg[0].period == .minute5)
        #expect(agg[0].open == Decimal(100))
        #expect(agg[0].close == Decimal(104))
        #expect(agg[0].high == Decimal(string: "104.1")!)
        #expect(agg[0].low == Decimal(string: "99.9")!)
        #expect(agg[0].volume == 500)
        #expect(agg[1].open == Decimal(105))
        #expect(agg[1].close == Decimal(109))
    }

    @Test("aggregate · 同周期（minute1 → minute1）· 返回空")
    func aggregateSamePeriodReturnsEmpty() {
        let bars = makeBars(period: .minute1, closes: [100, 101, 102, 103, 104])
        let agg = MultiTimeframeResonance.aggregate(bars: bars, targetPeriod: .minute1)
        #expect(agg.isEmpty)
    }

    @Test("aggregate · target 小于 base（hour1 → minute1）· 返回空")
    func aggregateTargetSmallerReturnsEmpty() {
        let bars = makeBars(period: .hour1, closes: [100, 101, 102])
        let agg = MultiTimeframeResonance.aggregate(bars: bars, targetPeriod: .minute1)
        #expect(agg.isEmpty)
    }

    @Test("aggregate · 空 bars · 返回空")
    func aggregateEmptyReturnsEmpty() {
        let agg = MultiTimeframeResonance.aggregate(bars: [], targetPeriod: .minute5)
        #expect(agg.isEmpty)
    }

    // MARK: - detectSignals

    @Test("detectSignals · EMA fast=3 slow=5 · 升后降序列 · 检出 emaDeathCross")
    func detectSignalsEMADeathCross() throws {
        // 升 10 根（100..109）+ 降 10 根（108..90 步长 -2）· fast 比 slow 反应快 · 必有 EMA 死叉
        var closes: [Double] = (0..<10).map { 100 + Double($0) }
        closes += stride(from: 108.0, through: 90.0, by: -2.0)
        let bars = makeBars(period: .minute5, closes: closes)
        let params = MultiTimeframeResonanceParams(emaFast: 3, emaSlow: 5)
        let signals = try MultiTimeframeResonance.detectSignals(on: bars, params: params)
        let death = signals.filter { $0.kind == .emaDeathCross }
        #expect(death.count >= 1, "升后降必出 EMA 死叉")
    }

    @Test("detectSignals · EMA · 降后升序列 · 检出 emaGoldCross")
    func detectSignalsEMAGoldCross() throws {
        var closes: [Double] = (0..<10).map { 110 - Double($0) }
        closes += stride(from: 102.0, through: 120.0, by: 2.0)
        let bars = makeBars(period: .minute5, closes: closes)
        let params = MultiTimeframeResonanceParams(emaFast: 3, emaSlow: 5)
        let signals = try MultiTimeframeResonance.detectSignals(on: bars, params: params)
        let gold = signals.filter { $0.kind == .emaGoldCross }
        #expect(gold.count >= 1, "降后升必出 EMA 金叉")
    }

    @Test("detectSignals · MACD fast=2 slow=4 signal=2 · 加速升后降 · 检出 macdDeathCross")
    func detectSignalsMACDDeathCross() throws {
        // 用二次方加速上升 → DIF 不会持平于 DEA 形成等值平台（线性匀速升降会让 DIF≡DEA）
        var closes: [Double] = (0..<15).map { 100 + Double($0 * $0) * 0.2 }    // 100..139.2 加速升
        closes += stride(from: 130.0, through: 70.0, by: -6.0)                  // 130..70 11 根降
        let bars = makeBars(period: .minute5, closes: closes)
        let params = MultiTimeframeResonanceParams(
            macdFast: 2, macdSlow: 4, macdSignal: 2,
            emaFast: 5, emaSlow: 20,
            enabledKinds: [.macdGoldCross, .macdDeathCross]
        )
        let signals = try MultiTimeframeResonance.detectSignals(on: bars, params: params)
        let death = signals.filter { $0.kind == .macdDeathCross }
        #expect(death.count >= 1, "升后降必出 MACD 死叉")
    }

    @Test("detectSignals · 数据不足（bars 少于 slow+1）· 返回空")
    func detectSignalsInsufficientData() throws {
        let bars = makeBars(period: .minute5, closes: [100, 101, 102])  // 仅 3 根
        // 默认 emaSlow=20 → 需要 ≥21 根
        let signals = try MultiTimeframeResonance.detectSignals(on: bars, params: .default)
        #expect(signals.isEmpty)
    }

    // MARK: - detect() 完整流水线

    @Test("detect() · minute1 base + minute5 target · 信号映射回 base bar index")
    func detectEndToEnd() throws {
        // 60 根 minute1 · 升 30 + 降 30 · 聚合后 12 根 minute5 · 必有 EMA 死叉
        var closes: [Double] = (0..<30).map { 100 + Double($0) * 0.5 }       // 100..114.5
        closes += stride(from: 113.5, through: 84.0, by: -1.0)               // 30 根降
        let bars = makeBars(period: .minute1, closes: closes)
        let params = MultiTimeframeResonanceParams(emaFast: 3, emaSlow: 5)
        let signals = try MultiTimeframeResonance.detect(baseBars: bars, targetPeriods: [.minute5], params: params)
        let death = signals.filter { $0.kind == .emaDeathCross }
        #expect(death.count >= 1)
        if let s = death.first {
            #expect(s.sourcePeriod == .minute5)
            // baseBarIndex 必须在 [0, bars.count-1] 区间
            #expect(s.baseBarIndex >= 0 && s.baseBarIndex < bars.count)
            // 验证映射：信号 close time = target_bar.openTime + 300 · base bar openTime ≤ closeTime
            let closeTime = s.sourceOpenTime.timeIntervalSince1970 + 300
            #expect(bars[s.baseBarIndex].openTime.timeIntervalSince1970 <= closeTime)
        }
    }

    @Test("detect() · 空 base bars · 返回空")
    func detectEmptyBaseBars() throws {
        let signals = try MultiTimeframeResonance.detect(baseBars: [], targetPeriods: [.minute5], params: .default)
        #expect(signals.isEmpty)
    }

    @Test("detect() · enabledKinds 过滤 · 关闭 ema 后只剩 macd 信号")
    func detectEnabledKindsFilter() throws {
        var closes: [Double] = (0..<30).map { 100 + Double($0) * 0.5 }
        closes += stride(from: 113.5, through: 84.0, by: -1.0)
        let bars = makeBars(period: .minute1, closes: closes)
        let params = MultiTimeframeResonanceParams(
            macdFast: 2, macdSlow: 4, macdSignal: 2,
            emaFast: 3, emaSlow: 5,
            enabledKinds: [.macdGoldCross, .macdDeathCross]   // 关 EMA
        )
        let signals = try MultiTimeframeResonance.detect(baseBars: bars, targetPeriods: [.minute5], params: params)
        #expect(signals.allSatisfy { $0.kind == .macdGoldCross || $0.kind == .macdDeathCross })
    }

    // MARK: - defaultTargets 表

    @Test("defaultTargets · daily → [weekly, monthly]")
    func defaultTargetsDaily() {
        #expect(MultiTimeframeResonance.defaultTargets(for: .daily) == [.weekly, .monthly])
    }

    @Test("defaultTargets · minute15 → [hour1, hour4]")
    func defaultTargetsMinute15() {
        #expect(MultiTimeframeResonance.defaultTargets(for: .minute15) == [.hour1, .hour4])
    }

    @Test("defaultTargets · annual → 空（已是最长）")
    func defaultTargetsAnnual() {
        #expect(MultiTimeframeResonance.defaultTargets(for: .annual).isEmpty)
    }

    // MARK: - ResonanceSignalKind metadata

    @Test("ResonanceSignalKind · direction / shortCode 全集校验")
    func signalKindMetadata() {
        #expect(ResonanceSignalKind.macdGoldCross.direction == 1)
        #expect(ResonanceSignalKind.macdDeathCross.direction == -1)
        #expect(ResonanceSignalKind.emaGoldCross.direction == 1)
        #expect(ResonanceSignalKind.emaDeathCross.direction == -1)
        #expect(ResonanceSignalKind.macdGoldCross.shortCode == "M↑")
        #expect(ResonanceSignalKind.emaDeathCross.shortCode == "E↓")
        #expect(ResonanceSignalKind.allCases.count == 4)
    }
}

// MARK: - test helpers

fileprivate func makeBars(period: KLinePeriod, closes: [Double]) -> [KLine] {
    // 用 epoch 0 起点 · 整除任何 period.seconds · 避免 bucket 跨界乱
    let baseTS: TimeInterval = 0
    let step = TimeInterval(period.seconds)
    return closes.enumerated().map { i, c in
        KLine(
            instrumentID: "TEST",
            period: period,
            openTime: Date(timeIntervalSince1970: baseTS + Double(i) * step),
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
