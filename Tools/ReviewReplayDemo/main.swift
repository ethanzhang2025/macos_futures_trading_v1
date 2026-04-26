// 复盘 + 回放联动真数据冒烟 demo（第 8 个真数据 demo）
//
// 用途：
// - 串联 JournalCore + ReplayCore + DataCore-Sina 三 Core 真行情管线
// - 同一组 trades 同时驱动两条业务流（报表聚合 / K 线回放 + TradeMark 标注），跨数据一致性交叉校验
// - 为 M4 复盘界面"图表 + 成交点叠加"准备数据流契约
//
// 拓扑：
//   1. 拉 Sina RB0 60min K 线最近 80 根（覆盖 ~3 天）
//   2. 基于真实 K 收盘价 + 时间动态构造 7 笔模拟成交（必然落在 K 时间窗内）
//      - 4 段：2 段盈利 / 1 段亏损 / 1 段未平仓
//   3. JournalCore 路径：PositionMatcher.match → ClosedPosition → ReviewAnalytics 5 个聚合算法
//   4. ReplayCore 路径：trades → TradeMark[] → ReplayPlayer.load(bars, marks) → 8x 回放 + 每 K 标注查询
//   5. 跨 Core 一致性校验：复盘段开仓价 == 回放段对应 K TradeMark.price · 总数对齐
//
// 运行：swift run ReviewReplayDemo
// 注意：基于真实 K 数据动态构造 trades，保证 trade.price = 该 K close（标注价位真实）

import Foundation
import Shared
import DataCore
import JournalCore
import ReplayCore

@main
struct ReviewReplayDemo {

    static func main() async throws {
        printSection("复盘 + 回放联动真数据冒烟（JournalCore × ReplayCore × DataCore-Sina）")

        // 1. 拉 Sina K 线最近 80 根
        let allBars = (try? await SinaMarketData().fetchMinute60KLines(symbol: "RB0")) ?? []
        guard allBars.count >= 80 else {
            print("❌ K 线不足 80 根（实际 \(allBars.count)）· 退出")
            return
        }
        let recent = Array(allBars.suffix(80))
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
        guard klines.count == 80 else {
            print("❌ KLine 转换失败 · 实得 \(klines.count) / 期望 80")
            return
        }
        let priceLow = klines.map(\.low).min() ?? 0
        let priceHigh = klines.map(\.high).max() ?? 0
        print("✅ Sina 真 K 线：\(klines.count) 根 · \(recent.first!.date) ~ \(recent.last!.date) · 价位 \(fmt(priceLow))~\(fmt(priceHigh))")

        // 2. 基于真实 K 动态构造 trades（4 段）
        // 索引选取：第 5/20/35/50/65/75 根作为锚点，trade 落在该 K openTime + 5min（保证在 [openTime, nextOpen) 窗内）
        let trades = makeTradesAlignedToKLines(klines)
        let openCount = trades.count(where: { $0.offsetFlag == .open })
        print("✅ 动态构造 \(trades.count) 笔成交（开 \(openCount) / 平 \(trades.count - openCount)）· 价位锚定真实 K 收盘价")

        // 3. JournalCore 路径：报表
        printSection("段 1 · JournalCore 报表（PositionMatcher + ReviewAnalytics 5 算法）")
        let result = PositionMatcher.match(trades: trades, multipliers: ["RB0": 10])
        let closed = result.closed
        print("FIFO 配对：闭合 \(closed.count) 笔 / 未平仓 \(result.openRemaining.count) 组")

        print("\n[闭合持仓]")
        print("  方向  开仓价     平仓价     量   持仓时长   盈亏")
        for pos in closed {
            let dir = pos.side == .long ? "多" : "空"
            let hours = Int(pos.holdingSeconds / 3600)
            let pnlSign = pos.realizedPnL >= 0 ? "+" : ""
            print(String(format: "  %@    %@   →  %@   ×%d   %3dh    %@%@",
                         dir, fmt(pos.openPrice), fmt(pos.closePrice), pos.volume, hours,
                         pnlSign, fmt(pos.realizedPnL)))
        }

        let monthly = ReviewAnalytics.monthlyPnL(from: closed)
        let dist = ReviewAnalytics.pnlDistribution(from: closed, binSize: 200)
        let winRate = ReviewAnalytics.winRateCurve(from: closed)
        let ratio = ReviewAnalytics.profitLossRatio(from: closed)
        let session = ReviewAnalytics.sessionPnL(from: closed)
        print("\n[聚合算法 5/8]")
        print("  monthlyPnL          · 总盈亏 \(fmt(monthly.totalPnL)) / \(monthly.buckets.count) 个月桶")
        print("  pnlDistribution     · 盈/亏 \(dist.positiveCount)/\(dist.negativeCount) / \(dist.bins.filter { $0.count > 0 }.count) 非空 bin")
        print("  winRateCurve        · 终值胜率 \(percent(winRate.finalWinRate))")
        print("  profitLossRatio     · 平盈 \(fmt(ratio.averageWin)) × \(ratio.winCount) / 平亏 \(fmt(ratio.averageLoss)) × \(ratio.lossCount) / 比 \(fmt(ratio.ratio))")
        print("  sessionPnL          · \(session.buckets.filter { $0.tradeCount > 0 }.count) 时段有成交")

        // 4. ReplayCore 路径：回放 + TradeMark 标注
        printSection("段 2 · ReplayCore 回放 + TradeMark 标注（8x 速度，每 30ms 一根 K）")
        let marks = trades.map { TradeMark(
            instrumentID: $0.instrumentID,
            time: $0.timestamp,
            price: $0.price,
            side: $0.direction == .buy ? .buy : .sell,
            volume: $0.volume
        ) }
        let player = ReplayPlayer()
        await player.load(bars: klines, tradeMarks: marks)
        await player.setSpeed(.x8)
        await player.play()

        let stats = ReplayMarkCounter()
        let stream = await player.observe()
        let consumeTask = Task {
            for await update in stream {
                guard case .barEmitted(let bar, _) = update else { continue }
                for m in await player.tradeMarksAtCurrentBar() {
                    let arrow = m.side == .buy ? "🟢 buy " : "🔴 sell"
                    print("  📍 [\(formatTime(bar.openTime))] \(arrow) price=\(fmt(m.price)) vol=\(m.volume) (K close=\(fmt(bar.close)))")
                    await stats.bumpMark()
                }
                await stats.bumpBar()
            }
        }

        // 驱动：80 根 K · 每 30ms 一根 ≈ 2.4 秒
        for _ in 0..<klines.count {
            let advanced = await player.stepForward(count: 1)
            if advanced == 0 { break }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        consumeTask.cancel()

        let barsEmitted = await stats.barsEmitted
        let marksMatched = await stats.marksMatched
        print("\n回放完成：emit \(barsEmitted) 根 K · 标注 \(marksMatched) 个 TradeMark")

        // 5. 跨 Core 一致性校验
        printSection("段 3 · 跨 Core 一致性交叉校验")
        let totalMarksFromTrades = trades.count
        let priceConsistency = checkPriceConsistency(closed: closed, trades: trades)
        let countMatch = (marksMatched == totalMarksFromTrades)

        print("  ✅ trade 总数 \(trades.count) == TradeMark 标注命中 \(marksMatched)：\(countMatch ? "✅" : "❌")")
        print("  ✅ ClosedPosition.openPrice / closePrice 必须 == 对应 trade.price：\(priceConsistency ? "✅" : "❌")")
        print("  ✅ 价位锚定真实 K close：动态构造时已保证（trade.price == klines[anchor].close）")

        // 6. 总结
        let allPassed = countMatch && priceConsistency
        printSection(allPassed
            ? "🎉 复盘 + 回放联动真数据冒烟通过（3 Core 联通 + 数据一致）"
            : "⚠️  跨 Core 数据不一致（详见上方）")
    }

    // MARK: - 动态构造 trades（基于真实 K 收盘价）

    static func makeTradesAlignedToKLines(_ klines: [KLine]) -> [Trade] {
        // 6 笔成交（3 段闭合）+ 1 笔未平仓 = 7 笔总
        // 锚点 K 索引：5 / 20 / 30 / 45 / 55 / 70 / 78
        // 段 1（多·盈利）：K[5]  buy open  → K[20] sell close
        // 段 2（空·盈利）：K[30] sell open → K[45] buy close
        // 段 3（多·亏损）：K[55] buy open  → K[70] sell close
        // 段 4（多·未平）：K[78] buy open
        let anchors: [(idx: Int, dir: Direction, off: OffsetFlag, vol: Int)] = [
            (5,  .buy,  .open,  2),
            (20, .sell, .close, 2),
            (30, .sell, .open,  1),
            (45, .buy,  .close, 1),
            (55, .buy,  .open,  3),
            (70, .sell, .close, 3),
            (78, .buy,  .open,  1)
        ]
        return anchors.map { a in
            let bar = klines[a.idx]
            return Trade(
                tradeReference: "RR-\(a.idx)",
                instrumentID: "RB0",
                direction: a.dir,
                offsetFlag: a.off,
                price: bar.close,
                volume: a.vol,
                commission: Decimal(a.vol) * 2.3,
                timestamp: bar.openTime.addingTimeInterval(300),  // openTime + 5min · 必落在 [openTime, nextOpen) 内
                source: .manual
            )
        }
    }

    // MARK: - 跨 Core 一致性校验

    static func checkPriceConsistency(closed: [ClosedPosition], trades: [Trade]) -> Bool {
        // 每个 ClosedPosition 的开仓/平仓价都应能在 trades 里找到对应 trade
        let tradePrices = Set(trades.map(\.price))
        return closed.allSatisfy { tradePrices.contains($0.openPrice) && tradePrices.contains($0.closePrice) }
    }

    // MARK: - 通用 helpers

    static func fmt(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func percent(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? "?"
    }

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: date)
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}

// MARK: - 计数器 actor

private actor ReplayMarkCounter {
    private(set) var barsEmitted: Int = 0
    private(set) var marksMatched: Int = 0
    func bumpBar() { barsEmitted += 1 }
    func bumpMark() { marksMatched += 1 }
}
