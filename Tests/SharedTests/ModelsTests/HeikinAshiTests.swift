// v17.13 A1.1 · Heikin Ashi 变换测试

import Testing
import Foundation
@testable import Shared

@Suite("KLine.heikinAshi · v17.13 A1.1")
struct HeikinAshiTests {

    private func bar(_ o: Int, _ h: Int, _ l: Int, _ c: Int, time: TimeInterval = 1_700_000_000) -> KLine {
        KLine(
            instrumentID: "rb2510",
            period: .minute1,
            openTime: Date(timeIntervalSince1970: time),
            open: Decimal(o),
            high: Decimal(h),
            low: Decimal(l),
            close: Decimal(c),
            volume: 100,
            openInterest: 0,
            turnover: 0
        )
    }

    @Test("空数组返回空")
    func empty() {
        #expect(KLine.heikinAshi(from: []).isEmpty)
    }

    @Test("首根 HA_open = (open + close) / 2 · HA_close = (O+H+L+C) / 4")
    func firstBar() {
        let bars = [bar(100, 110, 95, 105)]  // O=100 H=110 L=95 C=105
        let ha = KLine.heikinAshi(from: bars)
        #expect(ha.count == 1)
        // HA_open = (100 + 105) / 2 = 102.5
        #expect(ha[0].open == Decimal(string: "102.5")!)
        // HA_close = (100 + 110 + 95 + 105) / 4 = 102.5
        #expect(ha[0].close == Decimal(string: "102.5")!)
        // HA_high = max(110, 102.5, 102.5) = 110
        #expect(ha[0].high == Decimal(110))
        // HA_low = min(95, 102.5, 102.5) = 95
        #expect(ha[0].low == Decimal(95))
    }

    @Test("第 2 根 HA_open = (prev_HA_open + prev_HA_close) / 2")
    func secondBarOpenRelativeToPrev() {
        let bars = [
            bar(100, 110, 95, 105),    // ha[0]: open=102.5 close=102.5
            bar(105, 120, 100, 115)    // ha[1]: open = (102.5 + 102.5) / 2 = 102.5, close = (105+120+100+115)/4 = 110
        ]
        let ha = KLine.heikinAshi(from: bars)
        #expect(ha.count == 2)
        #expect(ha[1].open == Decimal(string: "102.5")!)
        #expect(ha[1].close == Decimal(110))
        // HA_high = max(120, 102.5, 110) = 120
        #expect(ha[1].high == Decimal(120))
        // HA_low = min(100, 102.5, 110) = 100
        #expect(ha[1].low == Decimal(100))
    }

    @Test("volume / openInterest / turnover 不变")
    func volumePreserved() {
        let raw = KLine(
            instrumentID: "rb", period: .minute5,
            openTime: Date(timeIntervalSince1970: 1_700_000_000),
            open: 100, high: 110, low: 90, close: 105,
            volume: 1234, openInterest: Decimal(string: "5678")!, turnover: Decimal(string: "9012.34")!
        )
        let ha = KLine.heikinAshi(from: [raw])
        #expect(ha[0].volume == 1234)
        #expect(ha[0].openInterest == Decimal(string: "5678")!)
        #expect(ha[0].turnover == Decimal(string: "9012.34")!)
        #expect(ha[0].instrumentID == "rb")
        #expect(ha[0].period == .minute5)
        #expect(ha[0].openTime == raw.openTime)
    }

    @Test("纯上涨序列 · HA 也全阳（HA_close >= HA_open）")
    func uptrendAllBullish() {
        let bars = (0..<20).map { i -> KLine in
            let base = 100 + i
            return bar(base, base + 2, base - 1, base + 1)  // 每根都涨 1 块
        }
        let ha = KLine.heikinAshi(from: bars)
        for h in ha {
            #expect(h.close >= h.open, "HA close \(h.close) 应 >= HA open \(h.open)（纯上涨）")
        }
    }

    @Test("HA_high 永远 >= HA_open / HA_close · HA_low 永远 <= 两者")
    func haGeometryInvariant() {
        let bars = (0..<50).map { i -> KLine in
            let o = 100 + (i % 7) - 3
            let c = o + (i % 5) - 2
            let h = max(o, c) + 3
            let l = min(o, c) - 3
            return bar(o, h, l, c)
        }
        let ha = KLine.heikinAshi(from: bars)
        for h in ha {
            #expect(h.high >= h.open)
            #expect(h.high >= h.close)
            #expect(h.low <= h.open)
            #expect(h.low <= h.close)
        }
    }
}
