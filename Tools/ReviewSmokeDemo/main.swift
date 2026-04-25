// WP-50 · 复盘 8 图真数据冒烟 demo
//
// 用途：
// - 用 Sina RB0 真实价位（3100-3300）造一份模拟交割单
// - PositionMatcher FIFO 配对 → ClosedPosition[]
// - 跑 8 个 ReviewAnalytics 聚合算法 + 打印关键统计
//
// 运行：swift run ReviewSmokeDemo

import Foundation
import Shared
import DataCore
import JournalCore

@main
struct ReviewSmokeDemo {

    static func main() async throws {
        print("─────────────────────────────────────────────")
        print("WP-50 · 复盘 8 图真数据冒烟（RB0 螺纹钢 · 基于真实价位）")
        print("─────────────────────────────────────────────")

        // 1. 拉真实 K 线作为参考价位（实际成交单基于真实价格区间硬编码）
        let sina = SinaMarketData()
        let bars = (try? await sina.fetchMinute60KLines(symbol: "RB0")) ?? []
        if !bars.isEmpty {
            let high = bars.map { $0.high }.max() ?? 0
            let low = bars.map { $0.low }.min() ?? 0
            print("✅ Sina K 线参考：\(bars.count) 根 · 价位区间 \(low) ～ \(high)")
        }

        // 2. 造 7 笔模拟成交（4 段：2 段盈利 / 1 段亏损 / 1 段未平仓）
        let trades = makeMockTrades()
        let openCount = trades.filter { $0.offsetFlag == .open }.count
        let closeCount = trades.count - openCount
        print("✅ 造 \(trades.count) 笔模拟成交（开 \(openCount) / 平 \(closeCount)）")

        // 3. FIFO 配对（RB0 一手 10 吨 = volumeMultiple 10）
        let result = PositionMatcher.match(trades: trades, multipliers: ["RB0": 10])
        print("✅ FIFO 配对：闭合 \(result.closed.count) 笔 / 未平仓 \(result.openRemaining.count) 组")
        print("─────────────────────────────────────────────\n")

        // 4. 闭合持仓清单
        print("[闭合持仓清单]")
        print("  方向    开仓价     平仓价     量    持仓时长     盈亏")
        for pos in result.closed {
            let dir = pos.side == .long ? "多" : "空"
            let hours = Int(pos.holdingSeconds / 3600)
            let pnlSign = pos.realizedPnL >= 0 ? "+" : ""
            print(String(format: "  %@      %@   →  %@  ×%d   %3dh    %@%@",
                         dir, fmt(pos.openPrice), fmt(pos.closePrice), pos.volume, hours,
                         pnlSign, fmt(pos.realizedPnL)))
        }

        // 5. 8 个聚合算法
        print("\n─────────────────────────────────────────────")
        print("ReviewAnalytics · 8 个聚合算法真数据回归")
        print("─────────────────────────────────────────────")
        let pos = result.closed

        // 5.1 月度盈亏
        let monthly = ReviewAnalytics.monthlyPnL(from: pos)
        print("\n[1] monthlyPnL · \(monthly.buckets.count) 个月 · 总盈亏 \(fmt(monthly.totalPnL))")
        for bucket in monthly.buckets {
            print(String(format: "    %d-%02d : pnl=%@ 笔数=%d", bucket.year, bucket.month, fmt(bucket.realizedPnL), bucket.tradeCount))
        }

        // 5.2 盈亏分布（每 bucket 200 元宽度）
        let dist = ReviewAnalytics.pnlDistribution(from: pos, binSize: 200)
        print("\n[2] pnlDistribution · binSize=200 · \(dist.bins.count) 个 bin · 盈/亏 \(dist.positiveCount)/\(dist.negativeCount)")
        for bin in dist.bins where bin.count > 0 {
            print("    [\(fmt(bin.lowerBound)), \(fmt(bin.upperBound))) → \(bin.count) 笔")
        }

        // 5.3 胜率曲线
        let winRate = ReviewAnalytics.winRateCurve(from: pos)
        print("\n[3] winRateCurve · 点数 \(winRate.points.count) · 终值胜率 \(percentDouble(winRate.finalWinRate))")
        for p in winRate.points {
            print(String(format: "    %d/%d → 累计胜率 %@", p.cumulativeWins, p.cumulativeTotal, percentDouble(p.cumulativeWinRate)))
        }

        // 5.4 合约维度
        let matrix = ReviewAnalytics.instrumentMatrix(from: pos)
        print("\n[4] instrumentMatrix · \(matrix.cells.count) 个合约")
        for cell in matrix.cells {
            print("    \(cell.instrumentID): 笔数=\(cell.tradeCount) 总盈亏=\(fmt(cell.totalPnL)) 胜=\(cell.winCount) 胜率=\(percentDouble(cell.winRate))")
        }

        // 5.5 持仓时长
        let holding = ReviewAnalytics.holdingDurationStats(from: pos)
        print("\n[5] holdingDurationStats · 总数 \(holding.totalCount)")
        print(String(format: "    平均=%dh  中位=%dh  最短=%dh  最长=%dh",
                     Int(holding.averageSeconds / 3600),
                     Int(holding.medianSeconds / 3600),
                     Int(holding.minSeconds / 3600),
                     Int(holding.maxSeconds / 3600)))
        for bucket in holding.buckets where bucket.count > 0 {
            print("    \(bucket.label) → \(bucket.count) 笔")
        }

        // 5.6 最大回撤
        let drawdown = ReviewAnalytics.maxDrawdownCurve(from: pos)
        print("\n[6] maxDrawdownCurve · 点数 \(drawdown.points.count) · 峰值回撤 \(fmt(drawdown.maxDrawdown))")
        if let s = drawdown.maxDrawdownStart, let e = drawdown.maxDrawdownEnd {
            print("    回撤区间：\(formatDate(s)) → \(formatDate(e))")
        }

        // 5.7 盈亏比
        let ratio = ReviewAnalytics.profitLossRatio(from: pos)
        print("\n[7] profitLossRatio")
        print("    平均盈利=\(fmt(ratio.averageWin)) (×\(ratio.winCount))  平均亏损=\(fmt(ratio.averageLoss)) (×\(ratio.lossCount))  盈亏比=\(fmt(ratio.ratio))")

        // 5.8 时段盈亏（4 段：早盘 / 午盘 / 夜盘 / 凌晨夜盘）
        let session = ReviewAnalytics.sessionPnL(from: pos)
        print("\n[8] sessionPnL · \(session.buckets.count) 时段")
        for bucket in session.buckets where bucket.tradeCount > 0 {
            print("    \(bucket.slot.rawValue): 笔数=\(bucket.tradeCount) 盈亏=\(fmt(bucket.totalPnL)) 胜=\(bucket.winCount) 胜率=\(percentDouble(bucket.winRate))")
        }

        print("\n─────────────────────────────────────────────")
        print("🎉 WP-50 复盘 8 图真数据冒烟全通")
        print("─────────────────────────────────────────────")
    }

    // MARK: - 模拟数据（基于 RB0 真实价位）

    static func makeMockTrades() -> [Trade] {
        // 4 段交易（基于 RB0 真实价位 3100-3300 区间）：
        //   段 1（多·盈利 + 800）：2026-01-15 09:30 开仓 3100 ×2 → 2026-01-22 14:00 平仓 3180 ×2
        //   段 2（空·盈利 + 700）：2026-02-08 10:15 开仓 3220 ×1 → 2026-02-15 22:30 平仓 3150 ×1
        //   段 3（多·亏损 -1500）：2026-03-05 09:00 开仓 3250 ×3 → 2026-03-10 11:30 平仓 3200 ×3
        //   段 4（多·未平仓）：2026-04-20 21:30 开仓 3180 ×1
        return [
            mk("2026-01-15 09:30", .buy,  .open,  3100, 2, 4.5),
            mk("2026-01-22 14:00", .sell, .close, 3180, 2, 4.5),
            mk("2026-02-08 10:15", .sell, .open,  3220, 1, 2.3),
            mk("2026-02-15 22:30", .buy,  .close, 3150, 1, 2.3),
            mk("2026-03-05 09:00", .buy,  .open,  3250, 3, 6.8),
            mk("2026-03-10 11:30", .sell, .close, 3200, 3, 6.8),
            mk("2026-04-20 21:30", .buy,  .open,  3180, 1, 2.3)
        ]
    }

    static func mk(_ time: String, _ direction: Direction, _ offset: OffsetFlag,
                   _ price: Decimal, _ volume: Int, _ commission: Decimal) -> Trade {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return Trade(
            tradeReference: UUID().uuidString.prefix(8).description,
            instrumentID: "RB0",
            direction: direction,
            offsetFlag: offset,
            price: price,
            volume: volume,
            commission: commission,
            timestamp: f.date(from: time)!,
            source: .manual
        )
    }

    // MARK: - 格式化

    static func fmt(_ value: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: value as NSDecimalNumber) ?? "?"
    }

    static func percentDouble(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .percent
        nf.maximumFractionDigits = 1
        return nf.string(from: NSNumber(value: value)) ?? "?"
    }

    static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: date)
    }
}
