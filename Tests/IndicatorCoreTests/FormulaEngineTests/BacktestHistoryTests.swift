// v17.39 D5 · BacktestHistoryEntry / BacktestHistoryLog / BacktestMarkdownReport 单测

import Testing
import Foundation
@testable import IndicatorCore

private func makeEntry(daysAgo: Int, pnl: Double, signalLine: String = "BUY",
                       trajectory: String = "random") -> BacktestHistoryEntry {
    let date = Date().addingTimeInterval(-Double(daysAgo) * 86400)
    return BacktestHistoryEntry(
        id: UUID(), createdAt: date,
        signalLineName: signalLine,
        trajectoryRaw: trajectory,
        barCount: 200,
        initialEquity: 100_000,
        endingPnL: Decimal(pnl),
        maxDrawdown: Decimal(50),
        sharpe: 0.8,
        winRate: 0.55,
        expectancy: Decimal(pnl / 10),
        tradeCount: 10
    )
}

@Suite("BacktestHistoryEntry · v17.39 D5 历史持久化模型")
struct BacktestHistoryEntryTests {

    @Test("Codable round-trip · 所有字段保留")
    func codableRoundTrip() throws {
        let e = makeEntry(daysAgo: 0, pnl: 1234.56)
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(BacktestHistoryEntry.self, from: data)
        #expect(decoded == e)
    }

    @Test("dateLabel · MM-dd HH:mm 格式（Asia/Shanghai）")
    func dateLabelFormat() {
        let comps = DateComponents(year: 2026, month: 5, day: 11, hour: 14, minute: 30)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let date = cal.date(from: comps)!
        let label = BacktestHistoryEntry.dateLabel(date)
        #expect(label == "05-11 14:30")
    }
}

@Suite("BacktestHistoryLog · v17.39 D5 集合 + 区间筛选")
struct BacktestHistoryLogTests {

    @Test("entries(in:) · 按 [start,end) 过滤 · 降序排序")
    func entriesInRange() {
        let log = BacktestHistoryLog(entries: [
            makeEntry(daysAgo: 0, pnl: 100),    // 今天 · 含
            makeEntry(daysAgo: 5, pnl: 200),    // 5 天前 · 含
            makeEntry(daysAgo: 40, pnl: 300),   // 40 天前 · 排除
        ])
        let start = Date().addingTimeInterval(-30 * 86400)
        let end = Date().addingTimeInterval(86400)   // 明天
        let result = log.entries(in: start..<end)
        #expect(result.count == 2)
        // 降序：第 0 应该是今天的 100
        #expect(result[0].endingPnL == 100)
        #expect(result[1].endingPnL == 200)
    }

    @Test("entries(in:) · 空区间返回空数组")
    func entriesInEmptyRange() {
        let log = BacktestHistoryLog(entries: [makeEntry(daysAgo: 0, pnl: 100)])
        let past = Date().addingTimeInterval(-100 * 86400)
        let result = log.entries(in: past..<past.addingTimeInterval(86400))
        #expect(result.isEmpty)
    }

    @Test("Codable round-trip · entries 保序")
    func logCodableRoundTrip() throws {
        let log = BacktestHistoryLog(entries: [
            makeEntry(daysAgo: 0, pnl: 100),
            makeEntry(daysAgo: 1, pnl: 200),
        ])
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(BacktestHistoryLog.self, from: data)
        #expect(decoded == log)
    }
}

@Suite("BacktestMarkdownReport · v17.39 D5 月报 annex 生成")
struct BacktestMarkdownReportTests {

    @Test("空区间 · 输出 '无回测记录' 提示")
    func emptyAnnex() {
        let log = BacktestHistoryLog(entries: [])
        let start = Date().addingTimeInterval(-30 * 86400)
        let end = Date()
        let md = BacktestMarkdownReport.generateMonthlyAnnex(log, start: start, end: end)
        #expect(md.contains("## 公式回测"))
        #expect(md.contains("无保存的回测记录"))
    }

    @Test("有记录 · 输出概览 + 表格表头")
    func nonEmptyAnnex() {
        let log = BacktestHistoryLog(entries: [
            makeEntry(daysAgo: 1, pnl: 1000, signalLine: "BUY", trajectory: "up"),
            makeEntry(daysAgo: 2, pnl: -500, signalLine: "SELL", trajectory: "down"),
        ])
        let start = Date().addingTimeInterval(-30 * 86400)
        let end = Date().addingTimeInterval(86400)
        let md = BacktestMarkdownReport.generateMonthlyAnnex(log, start: start, end: end)
        #expect(md.contains("## 公式回测"))
        #expect(md.contains("区间内保存次数：**2**"))
        #expect(md.contains("| 时间 | 信号 |"))
        #expect(md.contains("上涨趋势"))
        #expect(md.contains("下跌趋势"))
        #expect(md.contains("BUY"))
        #expect(md.contains("SELL"))
    }

    @Test("rowLimit 截断 · 显示剩余条数提示")
    func rowLimitTruncation() {
        var entries: [BacktestHistoryEntry] = []
        for i in 0..<25 {
            entries.append(makeEntry(daysAgo: i, pnl: Double(i * 10)))
        }
        let log = BacktestHistoryLog(entries: entries)
        let start = Date().addingTimeInterval(-100 * 86400)
        let end = Date().addingTimeInterval(86400)
        let md = BacktestMarkdownReport.generateMonthlyAnnex(log, start: start, end: end, rowLimit: 10)
        #expect(md.contains("最近 10 条"))
        #expect(md.contains("还有 15 条未显示"))
    }

    @Test("平均 / 最佳 / 最差 PnL 统计正确")
    func summaryStats() {
        let log = BacktestHistoryLog(entries: [
            makeEntry(daysAgo: 0, pnl: 100),
            makeEntry(daysAgo: 1, pnl: 200),
            makeEntry(daysAgo: 2, pnl: -50),
        ])
        let start = Date().addingTimeInterval(-30 * 86400)
        let end = Date().addingTimeInterval(86400)
        let md = BacktestMarkdownReport.generateMonthlyAnnex(log, start: start, end: end)
        // 平均 = (100+200-50)/3 = 83.33
        #expect(md.contains("+83.33"))
        // 最佳 = 200 · 最差 = -50
        #expect(md.contains("+200.00"))
        #expect(md.contains("-50.00"))
    }
}
