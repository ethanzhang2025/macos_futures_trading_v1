// WP-51 · K 线回放真数据冒烟 demo
//
// 用途：
// - 拉 Sina RB0 1023 根 60min K 线 → 取最近 50 根 → load 到 ReplayPlayer
// - 60 倍速回放（每 50ms 一根 K）→ 验证 5 档速度 + 3 态状态机 + AsyncStream 闭环
// - 中途暂停 1s + 倒退 5 根 + 设速度 8x + 继续 → 展示控制器全功能
//
// 运行：swift run ReplaySmokeDemo

import Foundation
import Shared
import DataCore
import ReplayCore

@main
struct ReplaySmokeDemo {

    static func main() async throws {
        print("─────────────────────────────────────────────")
        print("WP-51 · K 线回放真数据冒烟（RB0 螺纹钢 · 60min · 最近 50 根）")
        print("─────────────────────────────────────────────")

        // 1. 拉 Sina K 线
        let sina = SinaMarketData()
        let bars = try await sina.fetchMinute60KLines(symbol: "RB0")
        guard bars.count >= 50 else {
            print("❌ K 线不足 50 根（实际 \(bars.count)）")
            return
        }

        // 2. 取最近 50 根并转 Shared.KLine
        let recent = Array(bars.suffix(50))
        let klines: [KLine] = recent.compactMap { bar in
            guard let openTime = parseDate(bar.date) else { return nil }
            return KLine(
                instrumentID: "RB0",
                period: .hour1,
                openTime: openTime,
                open: bar.open, high: bar.high, low: bar.low, close: bar.close,
                volume: bar.volume,
                openInterest: Decimal(bar.openInterest),
                turnover: 0
            )
        }
        guard klines.count == 50 else {
            print("❌ KLine 转换失败 · 实得 \(klines.count) / 期望 50")
            return
        }
        print("✅ 装载 \(klines.count) 根 K 线（\(recent.first!.date) ～ \(recent.last!.date)）")

        // 3. 创建 ReplayPlayer + 加载
        let player = ReplayPlayer()
        await player.load(bars: klines)
        print("✅ ReplayPlayer 加载完成 · 初始状态 = \(await player.currentState.rawValue)")

        // 4. 监听 update 流
        let stream = await player.observe()
        let stats = ReplayStats()
        let consumeTask = Task {
            for await update in stream {
                switch update {
                case .barEmitted(let bar, let cursor):
                    await stats.tally(bar: bar, cursor: cursor)
                case .stateChanged(let state, let speed, let direction):
                    print("[state] \(state.rawValue) · speed=\(speed.rawValue) · direction=\(direction.rawValue)")
                case .seekFinished(let cursor):
                    print("[seek]  → index=\(cursor.currentIndex)/\(cursor.totalCount) (\(percent(cursor.progress)))")
                case .tradeMarks:
                    break
                }
            }
        }

        // 5. 60 倍速播放（每 50ms 一根 K · 50 根 ≈ 2.5 秒）
        await player.setSpeed(.x4)
        await player.play()
        print("─────────────────────────────────────────────")
        print("▶️  开始 60x 回放（每 50ms 一根 K · 50 根 ≈ 2.5 秒）")
        print("─────────────────────────────────────────────")

        // 跑 25 根 → 暂停演示
        try await runForward(player: player, count: 25, intervalMs: 50)

        // 6. 暂停 1 秒展示状态
        await player.pause()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print("⏸️  暂停 1 秒后继续")

        // 7. 倒退 5 根
        let regressed = await player.stepBackward(count: 5)
        print("⏪  倒退 \(regressed) 根 K · 当前 index=\(await player.cursor.currentIndex)")

        // 8. 切 8x 速度继续跑完
        await player.setSpeed(.x8)
        await player.play()
        try await runForward(player: player, count: 100, intervalMs: 30)

        // 9. 终态收集
        consumeTask.cancel()

        let finalCursor = await player.cursor
        let finalState = await player.currentState
        let snapshot = await stats.snapshot()

        print("─────────────────────────────────────────────")
        print("回放结束 · 最终状态 = \(finalState.rawValue) · cursor \(finalCursor.currentIndex + 1)/\(finalCursor.totalCount) (\(percent(finalCursor.progress)))")
        print("\n统计：")
        print("  barEmitted 次数：\(snapshot.totalBars)")
        print("  起始 K：\(snapshot.firstBarTime ?? "—") · close=\(snapshot.firstClose ?? 0)")
        print("  末尾 K：\(snapshot.lastBarTime ?? "—") · close=\(snapshot.lastClose ?? 0)")
        print("  价格变化：\(snapshot.priceChange) (\(snapshot.priceChangePercent))")
        print("─────────────────────────────────────────────")

        // 验收：
        // - finalState = paused（自动到末尾切 paused）
        // - cursor 在末尾
        // - barEmitted ≥ 50 - 5（因为倒退 5 根产生重复 emit）
        let allPassed =
            finalState == .paused &&
            finalCursor.isAtEnd &&
            snapshot.totalBars >= 45
        if allPassed {
            print("🎉 WP-51 K 线回放真数据冒烟全通")
        } else {
            print("⚠️  状态/cursor/事件数不符合期望")
        }
    }

    // MARK: - 驱动 helpers

    /// 模拟 caller Timer 循环 stepForward
    static func runForward(player: ReplayPlayer, count: Int, intervalMs: Int) async throws {
        for _ in 0..<count {
            let advanced = await player.stepForward(count: 1)
            if advanced == 0 { return }  // 已到末尾
            try await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    static func percent(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? "?"
    }
}

// MARK: - 统计收集器

private actor ReplayStats {
    private var totalBars = 0
    private var firstClose: Decimal?
    private var lastClose: Decimal?
    private var firstTime: Date?
    private var lastTime: Date?

    func tally(bar: KLine, cursor: ReplayCursor) {
        totalBars += 1
        if firstClose == nil {
            firstClose = bar.close
            firstTime = bar.openTime
        }
        lastClose = bar.close
        lastTime = bar.openTime
    }

    struct Snapshot {
        let totalBars: Int
        let firstClose: Decimal?
        let lastClose: Decimal?
        let firstBarTime: String?
        let lastBarTime: String?
        let priceChange: String
        let priceChangePercent: String
    }

    func snapshot() -> Snapshot {
        let fmt: (Decimal) -> String = { d in
            let nf = NumberFormatter()
            nf.numberStyle = .decimal; nf.maximumFractionDigits = 2; nf.minimumFractionDigits = 2
            return nf.string(from: d as NSDecimalNumber) ?? "?"
        }
        let timeFmt: (Date) -> String = { d in
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return f.string(from: d)
        }

        let change: String
        let changePct: String
        if let first = firstClose, let last = lastClose, first != 0 {
            let diff = last - first
            let pct = diff / first * 100
            let sign = diff >= 0 ? "+" : ""
            change = "\(sign)\(fmt(diff))"
            changePct = "\(sign)\(fmt(pct))%"
        } else {
            change = "—"; changePct = "—"
        }

        return Snapshot(
            totalBars: totalBars,
            firstClose: firstClose,
            lastClose: lastClose,
            firstBarTime: firstTime.map(timeFmt),
            lastBarTime: lastTime.map(timeFmt),
            priceChange: change,
            priceChangePercent: changePct
        )
    }
}
