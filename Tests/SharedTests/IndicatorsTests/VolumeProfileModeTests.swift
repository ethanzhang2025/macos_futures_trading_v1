// v17.63 · VolumeProfile 模式（Full / Visible / Session / Fixed）单测

import Testing
import Foundation
@testable import Shared

@Suite("VolumeProfile.Mode · v17.63 B2 深化")
struct VolumeProfileModeTests {

    private func bar(low: Decimal, high: Decimal, volume: Int) -> KLine {
        KLine(
            instrumentID: "RB0", period: .minute15,
            openTime: Date(),
            open: low, high: high, low: low, close: high,
            volume: volume, openInterest: 0, turnover: 0
        )
    }

    private var bars20: [KLine] {
        (0..<20).map { i in bar(low: Decimal(100 + i), high: Decimal(102 + i), volume: 10 + i) }
    }

    @Test("fullRange · 等同 compute(bars:) 不传 mode")
    func fullRangeEquivalent() {
        let bars = bars20
        let withMode = VolumeProfile.compute(bars: bars, mode: .fullRange, binCount: 10)
        let withoutMode = VolumeProfile.compute(bars: bars, binCount: 10)
        #expect(withMode.count == withoutMode.count)
        let totalWith = withMode.reduce(0.0) { $0 + $1.volume }
        let totalWithout = withoutMode.reduce(0.0) { $0 + $1.volume }
        #expect(abs(totalWith - totalWithout) < 1e-6)
    }

    @Test("visibleRange · 仅 startIndex..<endIndex bars 参与")
    func visibleRange() {
        let bars = bars20
        // 取后 5 根
        let vp = VolumeProfile.compute(bars: bars, mode: .visibleRange,
                                       visibleRange: (15, 20), binCount: 10)
        let expectedVol = (15..<20).map { Double(10 + $0) }.reduce(0, +)
        let actualVol = vp.reduce(0.0) { $0 + $1.volume }
        #expect(abs(actualVol - expectedVol) < 1e-6, "可见区只应包含后 5 根的 volume")
    }

    @Test("session · 取最后 N 根 bars")
    func session() {
        let bars = bars20
        let vp = VolumeProfile.compute(bars: bars, mode: .session, sessionBarCount: 8, binCount: 10)
        let expectedVol = (12..<20).map { Double(10 + $0) }.reduce(0, +)
        let actualVol = vp.reduce(0.0) { $0 + $1.volume }
        #expect(abs(actualVol - expectedVol) < 1e-6)
    }

    @Test("fixedRange · 用户指定 startIndex/endIndex")
    func fixedRange() {
        let bars = bars20
        let vp = VolumeProfile.compute(bars: bars, mode: .fixedRange,
                                       fixedRange: (5, 10), binCount: 10)
        let expectedVol = (5..<10).map { Double(10 + $0) }.reduce(0, +)
        let actualVol = vp.reduce(0.0) { $0 + $1.volume }
        #expect(abs(actualVol - expectedVol) < 1e-6)
    }

    @Test("visibleRange 缺参数 · fallback 全量")
    func visibleRangeNilParam() {
        let bars = bars20
        let vpA = VolumeProfile.compute(bars: bars, mode: .visibleRange, visibleRange: nil, binCount: 10)
        let vpFull = VolumeProfile.compute(bars: bars, mode: .fullRange, binCount: 10)
        let totalA = vpA.reduce(0.0) { $0 + $1.volume }
        let totalF = vpFull.reduce(0.0) { $0 + $1.volume }
        #expect(abs(totalA - totalF) < 1e-6)
    }

    @Test("session bar count 超出 · clamp 到 bars.count")
    func sessionClamp() {
        let bars = bars20
        let vp = VolumeProfile.compute(bars: bars, mode: .session, sessionBarCount: 9999, binCount: 10)
        let vpFull = VolumeProfile.compute(bars: bars, mode: .fullRange, binCount: 10)
        let totalA = vp.reduce(0.0) { $0 + $1.volume }
        let totalF = vpFull.reduce(0.0) { $0 + $1.volume }
        #expect(abs(totalA - totalF) < 1e-6)
    }

    @Test("4 mode displayName 不空")
    func displayNamesNotEmpty() {
        for m in VolumeProfileMode.allCases {
            #expect(!m.displayName.isEmpty)
        }
    }
}
