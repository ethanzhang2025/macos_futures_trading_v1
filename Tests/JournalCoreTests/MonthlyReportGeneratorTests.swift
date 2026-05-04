// WP-50/53 v15.19 batch24 · 月度复盘 Markdown 生成测试

import Testing
import Foundation
@testable import JournalCore
import Shared

@Suite("MonthlyReportGenerator · v15.19 batch24")
struct MonthlyReportGeneratorTests {

    private let cn = TimeZone(identifier: "Asia/Shanghai")!

    /// 2026-05-04 12:00 Asia/Shanghai · 用 Calendar 计算避免硬编码 epoch 错误
    private var mayMidday: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = cn
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 4; c.hour = 12; c.minute = 0
        return cal.date(from: c)!
    }

    private func position(_ pnl: Decimal, instrument: String = "rb2501",
                          at: Date) -> ClosedPosition {
        ClosedPosition(
            instrumentID: instrument, side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: at.addingTimeInterval(-600),
            closeTime: at,
            openPrice: 3500, closePrice: 3500 + pnl,
            volume: 1, realizedPnL: pnl, totalCommission: 0
        )
    }

    @Test("空仓位 · Markdown 含基本骨架 · 概览部分 0 笔")
    func emptyPositions() {
        let md = MonthlyReportGenerator.generate(
            positions: [], year: 2026, month: 5, now: mayMidday
        )
        #expect(md.contains("# 2026 年 5 月复盘报告"))
        #expect(md.contains("## 概览"))
        #expect(md.contains("| 闭合笔数 | 0 |"))
        #expect(md.contains("无显著心理风险信号") || md.contains("命中笔数"))
        #expect(md.contains("_本月无成交_"))
    }

    @Test("月内仓位 · 概览数字正确（笔数 / 总 PnL / 胜率）")
    func basicAggregation() {
        let monthDate = mayMidday
        let positions = [
            position(100, at: monthDate),
            position(-50, at: monthDate.addingTimeInterval(3600)),
            position(200, at: monthDate.addingTimeInterval(7200))
        ]
        let md = MonthlyReportGenerator.generate(
            positions: positions, year: 2026, month: 5, now: monthDate
        )
        #expect(md.contains("| 闭合笔数 | 3 |"))
        #expect(md.contains("| 总 PnL | +250 |"))
        #expect(md.contains("66.7%"))   // 胜率 2/3
    }

    @Test("月份切片 · 跨月 position 不计入")
    func monthBoundaryFilter() {
        let may = mayMidday
        let april = may.addingTimeInterval(-30 * 86400)
        let june = may.addingTimeInterval(30 * 86400)
        let positions = [
            position(100, at: may),
            position(-200, at: april),
            position(300, at: june)
        ]
        let md = MonthlyReportGenerator.generate(
            positions: positions, year: 2026, month: 5, now: may
        )
        #expect(md.contains("| 闭合笔数 | 1 |"))
    }

    @Test("心理标签分布章节 · 出现命中标签时显示表格")
    func psychTagsSection() {
        let base = mayMidday
        let positions: [ClosedPosition] = (0..<5).map { i in
            let pnl: Decimal = i < 4 ? -100 : 50
            return position(pnl, at: base.addingTimeInterval(TimeInterval(i * 3600)))
        }
        let md = MonthlyReportGenerator.generate(
            positions: positions, year: 2026, month: 5, now: base
        )
        #expect(md.contains("复仇心态"))
        #expect(md.contains("命中笔数"))
    }

    @Test("品种分布章节 · 多合约按 PnL 降序")
    func instrumentSection() {
        let base = mayMidday
        let positions = [
            position(500, instrument: "rb2501", at: base),
            position(-100, instrument: "rb2501", at: base.addingTimeInterval(60)),
            position(1000, instrument: "if2506", at: base),
            position(-200, instrument: "au2512", at: base)
        ]
        let md = MonthlyReportGenerator.generate(
            positions: positions, year: 2026, month: 5, now: base
        )
        // if2506 总 PnL +1000 应在 rb2501 +400 之前
        let ifIdx = md.range(of: "| if2506 |")?.lowerBound
        let rbIdx = md.range(of: "| rb2501 |")?.lowerBound
        #expect(ifIdx != nil && rbIdx != nil)
        if let ifI = ifIdx, let rbI = rbIdx {
            #expect(ifI < rbI)
        }
    }

    @Test("时段分析章节 · 5 段固定输出（早/午/夜/凌晨/其他）")
    func sessionSection() {
        let md = MonthlyReportGenerator.generate(
            positions: [], year: 2026, month: 5
        )
        #expect(md.contains("早盘 09:00-11:30"))
        #expect(md.contains("午盘 13:00-15:00"))
        #expect(md.contains("夜盘 21:00-23:59"))
        #expect(md.contains("凌晨 00:00-02:30"))
    }

    @Test("生成时间脚注存在")
    func footer() {
        let md = MonthlyReportGenerator.generate(
            positions: [], year: 2026, month: 5, now: mayMidday
        )
        #expect(md.contains("生成时间："))
        #expect(md.contains("Asia/Shanghai"))
        #expect(md.contains("v15.19"))
    }
}
