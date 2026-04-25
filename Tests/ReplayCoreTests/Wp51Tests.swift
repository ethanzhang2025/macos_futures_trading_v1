// WP-51 · K 线回放测试
// 类型契约 / 加载与游标 / 播放控制状态转移 / 步进边界 / seek / speed/direction / 自动暂停 / AsyncStream / TradeMark 时间窗

import Testing
import Foundation
import Shared
@testable import ReplayCore

// MARK: - 测试辅助

private func makeBars(_ count: Int, instrumentID: String = "rb2510", baseTime: Date = Date(timeIntervalSince1970: 0), intervalSeconds: Int = 60) -> [KLine] {
    (0..<count).map { i in
        KLine(
            instrumentID: instrumentID, period: .minute1,
            openTime: baseTime.addingTimeInterval(TimeInterval(i * intervalSeconds)),
            open: 100, high: 100, low: 100, close: 100,
            volume: 0, openInterest: 0, turnover: 0
        )
    }
}

private func makeTradeMark(_ instrumentID: String = "rb2510", time: Date, price: Decimal = 100, side: TradeMarkSide = .buy) -> TradeMark {
    TradeMark(instrumentID: instrumentID, time: time, price: price, side: side, volume: 1)
}

private actor UpdateCollector {
    private(set) var updates: [ReplayUpdate] = []
    func append(_ u: ReplayUpdate) { updates.append(u) }
    func count() -> Int { updates.count }
    func snapshot() -> [ReplayUpdate] { updates }
}

private func consume(_ stream: AsyncStream<ReplayUpdate>, into collector: UpdateCollector) -> Task<Void, Never> {
    Task { for await u in stream { await collector.append(u) } }
}

// MARK: - 1. 类型契约

@Suite("ReplaySpeed / Cursor / TradeMark 类型")
struct ReplayTypesTests {

    @Test("ReplaySpeed multiplier 5 档")
    func speedMultipliers() {
        #expect(ReplaySpeed.x05.multiplier == 0.5)
        #expect(ReplaySpeed.x1.multiplier == 1.0)
        #expect(ReplaySpeed.x2.multiplier == 2.0)
        #expect(ReplaySpeed.x4.multiplier == 4.0)
        #expect(ReplaySpeed.x8.multiplier == 8.0)
        #expect(ReplaySpeed.allCases.count == 5)
    }

    @Test("ReplayCursor progress / isAtEnd / isAtStart")
    func cursorProperties() {
        #expect(ReplayCursor(currentIndex: 0, totalCount: 10).progress == 0.1)
        #expect(ReplayCursor(currentIndex: 9, totalCount: 10).progress == 1.0)
        #expect(ReplayCursor(currentIndex: 9, totalCount: 10).isAtEnd)
        #expect(ReplayCursor(currentIndex: 0, totalCount: 10).isAtStart)
        #expect(ReplayCursor(currentIndex: -1, totalCount: 0).progress == 0)
    }

    @Test("TradeMark Codable 往返")
    func tradeMarkCodable() throws {
        let m = makeTradeMark(time: Date(timeIntervalSince1970: 1_700_000_000), price: 3500)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(m)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TradeMark.self, from: data)
        #expect(decoded == m)
    }
}

// MARK: - 2. 加载与初始游标

@Suite("ReplayPlayer · 加载")
struct LoadTests {

    @Test("空 bars 加载 → cursor index = -1")
    func emptyLoad() async {
        let p = ReplayPlayer()
        await p.load(bars: [])
        let cursor = await p.cursor
        #expect(cursor.currentIndex == -1)
        #expect(cursor.totalCount == 0)
        #expect(await p.currentBar == nil)
    }

    @Test("加载 N 根 → cursor index = 0 / state = stopped")
    func loadResetsCursor() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))
        let cursor = await p.cursor
        #expect(cursor.currentIndex == 0)
        #expect(cursor.totalCount == 10)
        #expect(await p.currentState == .stopped)
    }

    @Test("乱序加载自动按 openTime 升序")
    func sortsBars() async {
        let p = ReplayPlayer()
        let unsorted = makeBars(3).reversed().map { $0 }
        await p.load(bars: unsorted)
        let bar = await p.currentBar
        #expect(bar?.openTime == Date(timeIntervalSince1970: 0))
    }
}

// MARK: - 3. 播放控制状态转移

@Suite("ReplayPlayer · 状态转移")
struct StateTransitionTests {

    @Test("play 仅在已加载时进入 playing")
    func playRequiresLoaded() async {
        let p = ReplayPlayer()
        await p.play()
        #expect(await p.currentState == .stopped)

        await p.load(bars: makeBars(5))
        await p.play()
        #expect(await p.currentState == .playing)
    }

    @Test("pause 仅 playing 时生效")
    func pauseFromPlaying() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(5))
        await p.pause()
        #expect(await p.currentState == .stopped)  // 未 playing 时 pause noop

        await p.play()
        await p.pause()
        #expect(await p.currentState == .paused)
    }

    @Test("stop 重置游标 + 状态")
    func stopResets() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(5))
        _ = await p.stepForward(count: 3)
        #expect(await p.cursor.currentIndex == 3)

        await p.stop()
        #expect(await p.cursor.currentIndex == 0)
        #expect(await p.currentState == .stopped)
    }
}

// MARK: - 4. 步进

@Suite("ReplayPlayer · 步进")
struct StepTests {

    @Test("stepForward N 根（默认 1）")
    func stepForwardN() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))

        let s1 = await p.stepForward()
        #expect(s1 == 1)
        #expect(await p.cursor.currentIndex == 1)

        let s5 = await p.stepForward(count: 5)
        #expect(s5 == 5)
        #expect(await p.cursor.currentIndex == 6)
    }

    @Test("stepForward 到末尾 clamp + 自动暂停")
    func stepForwardClampsAndAutoPauses() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(5))
        await p.play()
        #expect(await p.currentState == .playing)

        let s = await p.stepForward(count: 100)
        #expect(s == 4)  // 0 → 4 = 4 步
        #expect(await p.cursor.currentIndex == 4)
        #expect(await p.cursor.isAtEnd)
        #expect(await p.currentState == .paused)  // 自动暂停
    }

    @Test("末尾继续 stepForward 返回 0")
    func stepForwardAtEndNoop() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(3))
        _ = await p.stepForward(count: 100)
        let extra = await p.stepForward()
        #expect(extra == 0)
    }

    @Test("stepBackward N 根")
    func stepBackwardN() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))
        _ = await p.stepForward(count: 5)
        let b = await p.stepBackward(count: 2)
        #expect(b == 2)
        #expect(await p.cursor.currentIndex == 3)
    }

    @Test("stepBackward 到 0 不再后退")
    func stepBackwardClampsAtZero() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(5))
        let b = await p.stepBackward(count: 10)
        #expect(b == 0)  // 已在 0
        _ = await p.stepForward(count: 2)
        let b2 = await p.stepBackward(count: 100)
        #expect(b2 == 2)
        #expect(await p.cursor.currentIndex == 0)
    }
}

// MARK: - 5. seek

@Suite("ReplayPlayer · seek")
struct SeekTests {

    @Test("seek 到指定 index")
    func seekToIndex() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))
        let r = await p.seek(to: 5)
        #expect(r)
        #expect(await p.cursor.currentIndex == 5)
    }

    @Test("seek 越界自动 clamp")
    func seekClamps() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))
        let r1 = await p.seek(to: 100)
        #expect(r1)
        #expect(await p.cursor.currentIndex == 9)
        let r2 = await p.seek(to: -5)
        #expect(r2)
        #expect(await p.cursor.currentIndex == 0)
    }

    @Test("seek 到当前位置返回 false")
    func seekToCurrentNoop() async {
        let p = ReplayPlayer()
        await p.load(bars: makeBars(10))
        let r = await p.seek(to: 0)
        #expect(!r)
    }
}

// MARK: - 6. speed / direction

@Suite("ReplayPlayer · speed / direction")
struct ConfigTests {

    @Test("setSpeed 改变 currentSpeed")
    func setSpeed() async {
        let p = ReplayPlayer()
        #expect(await p.currentSpeed == .x1)
        await p.setSpeed(.x4)
        #expect(await p.currentSpeed == .x4)
    }

    @Test("setDirection 改变 currentDirection")
    func setDirection() async {
        let p = ReplayPlayer()
        #expect(await p.currentDirection == .forward)
        await p.setDirection(.backward)
        #expect(await p.currentDirection == .backward)
    }
}

// MARK: - 7. AsyncStream 推送

@Suite("ReplayPlayer · AsyncStream 推送")
struct StreamTests {

    @Test("load → play → step → stateChanged + barEmitted 序列")
    func observeBasicSequence() async {
        let p = ReplayPlayer()
        let stream = await p.observe()
        let collector = UpdateCollector()
        let task = consume(stream, into: collector)

        await p.load(bars: makeBars(5))     // → stateChanged
        await p.play()                       // → stateChanged
        _ = await p.stepForward(count: 2)    // → barEmitted ×1（从 0 到 2，emit 当前 2）
        await p.pause()                      // → stateChanged

        // 等待异步推送
        let deadline = Date().addingTimeInterval(0.5)
        while await collector.count() < 4, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        let updates = await collector.snapshot()
        #expect(updates.count >= 4)

        var sawBar = false
        for u in updates {
            if case .barEmitted = u { sawBar = true }
        }
        #expect(sawBar)
        task.cancel()
    }

    @Test("seek → seekFinished 推送 cursor")
    func seekEmitsSeekFinished() async {
        let p = ReplayPlayer()
        let stream = await p.observe()
        let collector = UpdateCollector()
        let task = consume(stream, into: collector)

        await p.load(bars: makeBars(10))
        _ = await p.seek(to: 5)

        let deadline = Date().addingTimeInterval(0.5)
        while await collector.count() < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        let updates = await collector.snapshot()
        var sawSeek = false
        for u in updates {
            if case .seekFinished(let cursor) = u {
                sawSeek = true
                #expect(cursor.currentIndex == 5)
            }
        }
        #expect(sawSeek)
        task.cancel()
    }
}

// MARK: - 8. TradeMark 时间窗口

@Suite("ReplayPlayer · TradeMark 时间窗")
struct TradeMarkTests {

    @Test("当前 K 线时间窗口内的成交点")
    func marksWithinCurrentBar() async {
        let p = ReplayPlayer()
        let baseTime = Date(timeIntervalSince1970: 0)
        let bars = makeBars(3, baseTime: baseTime, intervalSeconds: 60)
        // bar0: 00:00 / bar1: 01:00 / bar2: 02:00
        let marks = [
            makeTradeMark(time: baseTime.addingTimeInterval(30)),    // 在 bar0 内
            makeTradeMark(time: baseTime.addingTimeInterval(70)),    // 在 bar1 内
            makeTradeMark(time: baseTime.addingTimeInterval(150)),   // 在 bar2 内
            makeTradeMark(time: baseTime.addingTimeInterval(60)),    // bar1 起点（等于 bar1.openTime）
        ]
        await p.load(bars: bars, tradeMarks: marks)

        // cursor=0 (bar0)
        let m0 = await p.tradeMarksAtCurrentBar()
        #expect(m0.count == 1)

        // cursor=1 (bar1)
        _ = await p.stepForward()
        let m1 = await p.tradeMarksAtCurrentBar()
        #expect(m1.count == 2)  // 70s + 60s 边界（>= openTime）

        // cursor=2 (bar2，最后一根，nextOpen = distantFuture)
        _ = await p.stepForward()
        let m2 = await p.tradeMarksAtCurrentBar()
        #expect(m2.count == 1)
    }

    @Test("不同 instrumentID 不串线")
    func marksFilteredByInstrument() async {
        let p = ReplayPlayer()
        let baseTime = Date(timeIntervalSince1970: 0)
        let bars = makeBars(2, instrumentID: "rb2510", baseTime: baseTime)
        let marks = [
            makeTradeMark("rb2510", time: baseTime.addingTimeInterval(30)),
            makeTradeMark("hc2510", time: baseTime.addingTimeInterval(30)),  // 不同合约
        ]
        await p.load(bars: bars, tradeMarks: marks)

        let m = await p.tradeMarksAtCurrentBar()
        #expect(m.count == 1)
        #expect(m[0].instrumentID == "rb2510")
    }
}
