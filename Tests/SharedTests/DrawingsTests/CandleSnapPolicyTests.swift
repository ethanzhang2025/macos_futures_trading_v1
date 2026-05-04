// WP-42 · CandleSnapPolicy 价格吸附单测（v15.18）
//
// 覆盖：5 候选价 / 阈值内外 / 等距打破平局 / 边界 OHLC

import Testing
import Foundation
@testable import Shared

@Suite("CandleSnapPolicy · 价格吸附")
struct CandleSnapPolicyTests {

    // span = 100 · threshold = 100 * 0.015 = 1.5
    // candle: O=50 H=55 L=45 C=52 → mid = 51

    @Test("距 H 0.3 在阈值内 · 吸到 H")
    func snapsToHigh() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 55.3,
            open: 50, high: 55, low: 45, close: 52,
            visibleSpan: 100
        )
        #expect(p == 55)
    }

    @Test("距 L 0.5 在阈值内 · 吸到 L")
    func snapsToLow() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 44.5,
            open: 50, high: 55, low: 45, close: 52,
            visibleSpan: 100
        )
        #expect(p == 45)
    }

    @Test("距 mid 0.4 在阈值内 · 吸到 mid（(O+C)/2 = 51）")
    func snapsToMid() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 50.6,
            open: 50, high: 55, low: 45, close: 52,
            visibleSpan: 100
        )
        // 候选距离：O=0.6 / H=4.4 / L=5.6 / C=1.4 / mid=0.4 → mid 最近
        #expect(p == 51)
    }

    @Test("距所有候选 > 阈值 · 保留 raw 不吸附（精确画线）")
    func keepsRawWhenOutOfThreshold() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 47.5,
            open: 50, high: 55, low: 45, close: 52,
            visibleSpan: 100
        )
        // 候选距离：O=2.5 / H=7.5 / L=2.5 / C=4.5 / mid=3.5 · 阈值 1.5 · 全部 > 阈值
        #expect(p == 47.5)
    }

    @Test("mid 距 0 完全命中 · 直接吸（mid = (O+C)/2）")
    func snapsToMidWhenExactMatch() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 51.0,
            open: 50, high: 60, low: 40, close: 52,
            visibleSpan: 100
        )
        // 距离：O=1 / H=9 / L=11 / C=1 / mid=0 · mid 距 0 优先吸
        #expect(p == 51.0)
    }

    @Test("零跨度（hi==lo）· threshold=0 · 仅完全相等才吸附")
    func zeroSpanRequiresExactMatch() {
        let p1 = CandleSnapPolicy.snapPrice(
            rawPrice: 50,
            open: 50, high: 50, low: 50, close: 50,
            visibleSpan: 0
        )
        #expect(p1 == 50)   // raw 正好在 OHLC 上 · 吸附

        let p2 = CandleSnapPolicy.snapPrice(
            rawPrice: 50.001,
            open: 50, high: 50, low: 50, close: 50,
            visibleSpan: 0
        )
        #expect(p2 == 50.001)  // threshold=0 · 不吸附
    }

    @Test("自定义 thresholdRatio 5% · 更松吸附（远价位也咬住）")
    func customThresholdLooserSnap() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 49.0,
            open: 50, high: 55, low: 45, close: 52,
            visibleSpan: 100,
            thresholdRatio: 0.05   // 阈值 5
        )
        // 距 O=1.0 在阈值 5 内 · 吸到 O
        #expect(p == 50)
    }

    @Test("负 visibleSpan 视为 0 · threshold 非负（健壮性）")
    func negativeSpanClampedToZero() {
        let p = CandleSnapPolicy.snapPrice(
            rawPrice: 50.001,
            open: 50, high: 50, low: 50, close: 50,
            visibleSpan: -1
        )
        // threshold = max(0, -1) * 0.015 = 0 · 不吸附
        #expect(p == 50.001)
    }
}
