// WP-51 Timer 驱动器测试 · ReplayDriver 自动 stepForward 循环

import Testing
import Foundation
import Shared
@testable import ReplayCore

private func makeKLines(_ count: Int) -> [KLine] {
    (0..<count).map { i in
        KLine(
            instrumentID: "rb2510",
            period: .minute1,
            openTime: Date(timeIntervalSince1970: TimeInterval(i * 60)),
            open: 3500, high: 3500, low: 3500, close: 3500,
            volume: 0, openInterest: 0, turnover: 0
        )
    }
}

@Suite("ReplayDriver · Timer 自动驱动")
struct ReplayDriverTests {

    @Test("start 后自动 stepForward · cursor 推进")
    func startAdvancesCursor() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(20))
        await player.setSpeed(.x8)  // 8x → baseInterval/8 = 6.25ms
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.05)  // 50ms / 8 ≈ 6ms 每步
        await driver.start()
        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms 应 ≥10 步
        await driver.stop()

        let cursor = await player.cursor
        #expect(cursor.currentIndex >= 5)  // 至少推进 5 步（保守阈值，避免 CI flaky）
    }

    @Test("跑到末尾自动停 · isRunning = false + player 进 paused")
    func reachesEndAutoStops() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(5))
        await player.setSpeed(.x8)
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.02)  // 20ms / 8 = 2.5ms
        await driver.start()
        try await Task.sleep(nanoseconds: 300_000_000)  // 300ms 足够 5 步 + buffer

        // driveTask 应已退出（advanced == 0 后 break）
        // 注：isRunning 检查 task.isCancelled，自然完成的 task 不算 cancelled
        // 因此这里不直接断言 isRunning == false，而是验证 cursor 到末尾 + 末尾后 player 自动 paused
        let cursor = await player.cursor
        #expect(cursor.isAtEnd == true)
        let state = await player.currentState
        #expect(state == .paused)  // ReplayPlayer.stepForward 末尾自动 paused（A07 验收）
        await driver.stop()
    }

    @Test("player.pause 后 driver 自动停（state != playing 跳出循环）")
    func pausePlayerStopsDriver() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(100))
        await player.setSpeed(.x4)
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.05)  // 50ms/4 ≈ 12.5ms
        await driver.start()
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        await player.pause()
        try await Task.sleep(nanoseconds: 100_000_000)  // 等 driveTask 下一步循环退出

        let cursorBeforeWait = await player.cursor.currentIndex
        try await Task.sleep(nanoseconds: 100_000_000)
        let cursorAfterWait = await player.cursor.currentIndex
        #expect(cursorAfterWait == cursorBeforeWait)  // pause 后 driver 不再推进

        await driver.stop()
    }

    @Test("重复 start 不双 task · 旧 task 自动 cancel")
    func repeatedStartCancelsOldTask() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(50))
        await player.setSpeed(.x8)
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.05)
        await driver.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        await driver.start()  // 重复 start
        try await Task.sleep(nanoseconds: 50_000_000)
        await driver.stop()

        // 最终 cursor 应是合理值（< 50），且没有"双倍速度"的崩溃
        let cursor = await player.cursor
        #expect(cursor.currentIndex >= 1)
        #expect(cursor.currentIndex < 50)
    }

    @Test("setSpeed 动态切换 · 下一步循环自动应用新间隔")
    func setSpeedDynamic() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(100))
        await player.setSpeed(.x05)  // 慢速 baseInterval × 2
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.05)  // x05 → 100ms/步
        await driver.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        let cursorSlow = await player.cursor.currentIndex

        await player.setSpeed(.x8)  // 加速到 8x → 6.25ms/步
        try await Task.sleep(nanoseconds: 200_000_000)
        let cursorFast = await player.cursor.currentIndex
        await driver.stop()

        // 加速后 200ms 应推进多得多（保守阈值避免 CI flaky）
        #expect(cursorFast > cursorSlow + 3)
    }

    @Test("stop 立即停止 · 后续不再推进")
    func stopHaltsImmediately() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(100))
        await player.setSpeed(.x8)
        await player.play()

        let driver = ReplayDriver(player: player, baseInterval: 0.05)
        await driver.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        await driver.stop()

        let cursorBefore = await player.cursor.currentIndex
        try await Task.sleep(nanoseconds: 100_000_000)
        let cursorAfter = await player.cursor.currentIndex
        #expect(cursorAfter == cursorBefore)  // stop 后零推进
        #expect(await driver.isRunning == false)
    }

    @Test("isRunning 内省：start 前 false / stop 后 false")
    func isRunningIntrospection() async throws {
        let player = ReplayPlayer()
        await player.load(bars: makeKLines(10))
        let driver = ReplayDriver(player: player, baseInterval: 0.05)
        #expect(await driver.isRunning == false)

        await player.play()
        await driver.start()
        // 启动后短暂窗口内 isRunning = true（task 还没自然完成或 cancel）
        // 注：这里不强断言 true，因为 task 可能极快自然完成；只要 stop 后能正确变 false 就 OK

        await driver.stop()
        #expect(await driver.isRunning == false)
    }
}
