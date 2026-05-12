// v17.52 A1.2 · Renko 砖块图变换测试

import Testing
import Foundation
@testable import Shared

@Suite("KLine.renko · v17.52 A1.2")
struct RenkoTests {

    private func bar(_ o: Int, _ h: Int, _ l: Int, _ c: Int, time: TimeInterval = 1_700_000_000) -> KLine {
        KLine(
            instrumentID: "rb2510",
            period: .minute1,
            openTime: Date(timeIntervalSince1970: time),
            open: Decimal(o), high: Decimal(h), low: Decimal(l), close: Decimal(c),
            volume: 100, openInterest: 0, turnover: 0
        )
    }

    @Test("空数组 / 非正 brickSize → 空")
    func empty() {
        #expect(KLine.renko(from: [], brickSize: 1).isEmpty)
        #expect(KLine.renko(from: [bar(100, 100, 100, 100)], brickSize: 0).isEmpty)
        #expect(KLine.renko(from: [bar(100, 100, 100, 100)], brickSize: -5).isEmpty)
    }

    @Test("close 一直不动 → 不产砖")
    func flatNoBricks() {
        let bars = (0..<10).map { _ in bar(100, 101, 99, 100) }
        let bricks = KLine.renko(from: bars, brickSize: 5)
        #expect(bricks.isEmpty)
    }

    @Test("上涨 brickSize·2 → 出 2 个阳砖")
    func twoUpBricks() {
        let bars = [
            bar(100, 100, 100, 100),  // anchor=100
            bar(100, 110, 100, 110),  // 涨 10 = 2 × 5 → 2 砖
        ]
        let bricks = KLine.renko(from: bars, brickSize: 5)
        #expect(bricks.count == 2)
        // 第 1 砖：open=100 close=105
        #expect(bricks[0].open == Decimal(100))
        #expect(bricks[0].close == Decimal(105))
        #expect(bricks[0].high == Decimal(105))
        #expect(bricks[0].low == Decimal(100))
        // 第 2 砖：open=105 close=110
        #expect(bricks[1].open == Decimal(105))
        #expect(bricks[1].close == Decimal(110))
    }

    @Test("下跌 brickSize·3 → 出 3 个阴砖")
    func threeDownBricks() {
        let bars = [
            bar(100, 100, 100, 100),
            bar(100, 100, 85, 85),  // 跌 15 = 3 × 5
        ]
        let bricks = KLine.renko(from: bars, brickSize: 5)
        #expect(bricks.count == 3)
        #expect(bricks[0].open == Decimal(100))
        #expect(bricks[0].close == Decimal(95))
        // 阴砖：high=open low=close
        #expect(bricks[0].high == Decimal(100))
        #expect(bricks[0].low == Decimal(95))
        #expect(bricks[2].close == Decimal(85))
    }

    @Test("不足 brickSize 不产砖")
    func belowThresholdNoBrick() {
        let bars = [
            bar(100, 100, 100, 100),
            bar(100, 104, 100, 104),  // 4 < 5
        ]
        #expect(KLine.renko(from: bars, brickSize: 5).isEmpty)
    }

    @Test("元数据保留")
    func metadataPreserved() {
        let bars = [
            bar(100, 100, 100, 100),
            bar(100, 110, 100, 110),
        ]
        let bricks = KLine.renko(from: bars, brickSize: 5)
        #expect(bricks.first?.instrumentID == "rb2510")
        #expect(bricks.first?.period == .minute1)
    }

    @Test("defaultRenkoBrickSize = close × 0.5%")
    func defaultBrick() {
        let b = bar(0, 0, 0, 4000)
        let size = KLine.defaultRenkoBrickSize(for: [b])
        // 4000 × 0.005 = 20
        #expect(size == Decimal(20))
    }

    @Test("空 bars 默认 brickSize 返回 1（fallback）")
    func defaultBrickEmpty() {
        #expect(KLine.defaultRenkoBrickSize(for: []) == Decimal(1))
    }

    @Test("Renko 砖块 open 与 close 相差严格 = brickSize")
    func bricksExactBrickSize() {
        let bars = (0..<30).map { i -> KLine in
            let c = 100 + (i * 3 % 17) - 5
            return bar(c, c + 2, c - 2, c)
        }
        let bricks = KLine.renko(from: bars, brickSize: 3)
        for b in bricks {
            let diff = abs(b.close - b.open)
            #expect(diff == Decimal(3))
        }
    }
}
