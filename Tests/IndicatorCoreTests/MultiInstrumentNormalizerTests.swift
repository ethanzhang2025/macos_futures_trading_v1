// v17.189 · MultiInstrumentNormalizer 单测

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.189 · MultiInstrumentNormalizer 多合约归一化")
struct MultiInstrumentNormalizerTests {

    // MARK: - firstBaseline

    @Test("firstBaseline · secondary 涨 10% · 映射到 primary[0] * 1.1（起点对齐 + 同涨幅）")
    func firstBaselineMatchesPercentChange() {
        let primary:   [Decimal] = [100, 110, 120]
        let secondary: [Decimal] = [50, 55, 60]   // +10%, +20%
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: primary, secondary: secondary, mode: .firstBaseline
        )
        #expect(out.count == 3)
        #expect(out[0] == 100)
        #expect(out[1] == 110)     // 50→55 = +10% · 100 × 1.1
        #expect(out[2] == 120)     // 50→60 = +20% · 100 × 1.2
    }

    @Test("firstBaseline · secondary 跌 · 映射保持负百分比")
    func firstBaselineHandlesDecline() {
        let primary:   [Decimal] = [200]
        let secondary: [Decimal] = [100, 90]   // -10%
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: primary, secondary: secondary, mode: .firstBaseline
        )
        #expect(out.count == 2)
        #expect(out[0] == 200)
        #expect(out[1] == 180)   // 100→90 -10% · 200 × 0.9
    }

    @Test("firstBaseline · secondary base 0 · 全 primary base fallback（避免除零）")
    func firstBaselineZeroBaseFallback() {
        let primary:   [Decimal] = [100]
        let secondary: [Decimal] = [0, 10]
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: primary, secondary: secondary, mode: .firstBaseline
        )
        #expect(out == [100, 100])
    }

    // MARK: - minMax

    @Test("minMax · secondary [100,200] 缩放到 primary [10,30]")
    func minMaxScalesToRange() {
        let primary:   [Decimal] = [10, 20, 30]
        let secondary: [Decimal] = [100, 150, 200]
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: primary, secondary: secondary, mode: .minMax
        )
        #expect(out.count == 3)
        #expect(out[0] == 10)    // smin 100 → pmin 10
        #expect(out[1] == 20)    // 中点 150 → 20
        #expect(out[2] == 30)    // smax 200 → pmax 30
    }

    @Test("minMax · primary 区间退化（pmax==pmin）· 全 primaryBase fallback")
    func minMaxDegenerateRangeFallback() {
        let primary:   [Decimal] = [50, 50, 50]
        let secondary: [Decimal] = [10, 20, 30]
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: primary, secondary: secondary, mode: .minMax
        )
        #expect(out == [50, 50, 50])
    }

    // MARK: - 空 / 边界

    @Test("空 primary · 返回空")
    func emptyPrimary() {
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: [], secondary: [100, 110], mode: .firstBaseline
        )
        #expect(out.isEmpty)
    }

    @Test("空 secondary · 返回空")
    func emptySecondary() {
        let out = MultiInstrumentNormalizer.normalizeToPrimaryScale(
            primary: [100, 110], secondary: [], mode: .firstBaseline
        )
        #expect(out.isEmpty)
    }

    // MARK: - 时间对齐

    @Test("alignByOpenTime · 完全对齐 · secondary 不变")
    func alignSameTimes() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let primary = (0..<3).map { i in
            makeBar(time: base.addingTimeInterval(TimeInterval(i * 60)), close: Decimal(100 + i))
        }
        let secondary = (0..<3).map { i in
            makeBar(time: base.addingTimeInterval(TimeInterval(i * 60)), close: Decimal(200 + i))
        }
        let (p, s) = MultiInstrumentNormalizer.alignByOpenTime(primary: primary, secondary: secondary)
        #expect(p.count == 3)
        #expect(s.count == 3)
        #expect(s.map(\.close) == [200, 201, 202])
    }

    @Test("alignByOpenTime · secondary 缺中间 bar · 用上一根 hold-last")
    func alignHoldLastOnMissing() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let primary = (0..<4).map { i in
            makeBar(time: base.addingTimeInterval(TimeInterval(i * 60)), close: Decimal(100 + i))
        }
        // secondary 只有 idx 0 和 2 时间点 · idx 1/3 应 hold-last
        let secondary = [
            makeBar(time: base, close: 200),
            makeBar(time: base.addingTimeInterval(120), close: 220)
        ]
        let (_, s) = MultiInstrumentNormalizer.alignByOpenTime(primary: primary, secondary: secondary)
        #expect(s.count == 4)
        #expect(s.map(\.close) == [200, 200, 220, 220])
    }

    @Test("alignByOpenTime · primary 早于 secondary 起点 · 用 secondary[0]")
    func alignBeforeSecondaryStart() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let primary = [
            makeBar(time: base, close: 100),
            makeBar(time: base.addingTimeInterval(60), close: 101)
        ]
        let secondary = [
            makeBar(time: base.addingTimeInterval(120), close: 200)
        ]
        let (_, s) = MultiInstrumentNormalizer.alignByOpenTime(primary: primary, secondary: secondary)
        #expect(s.count == 2)
        #expect(s.map(\.close) == [200, 200])
    }

    @Test("alignByOpenTime · primary 空 · 返回空 secondary 对齐")
    func alignEmptyPrimary() {
        let (p, s) = MultiInstrumentNormalizer.alignByOpenTime(primary: [], secondary: [makeBar(close: 100)])
        #expect(p.isEmpty)
        #expect(s.isEmpty)
    }

    // MARK: - Mode metadata

    @Test("Mode allCases · 2 种 · displayName 非空")
    func modeMetadata() {
        let cases = MultiInstrumentNormalizer.Mode.allCases
        #expect(cases.count == 2)
        for c in cases {
            #expect(!c.displayName.isEmpty)
        }
    }
}

// MARK: - helper

fileprivate func makeBar(
    time: Date = Date(timeIntervalSinceReferenceDate: 0),
    close: Decimal
) -> KLine {
    KLine(
        instrumentID: "TEST",
        period: .minute1,
        openTime: time,
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 100,
        openInterest: 0,
        turnover: 0
    )
}
