// WP-53 v15.23 batch168/169 · JournalMarkdownReport 跨平台测试
//
// 覆盖：
// - generateSingle：标题 / 元数据 / 理由 / 教训 / 关联成交表格
// - generate：filter 应用 / 概览 / 情绪偏差分布 / 标签 top10 / 最近 N 篇

import Foundation
import Testing
@testable import JournalCore
import Shared

@Suite("JournalMarkdownReport · v15.23 batch168/169")
struct JournalMarkdownReportTests {

    private func makeJournal(
        title: String = "今日复盘",
        reason: String = "",
        emotion: JournalEmotion = .calm,
        deviation: JournalDeviation = .asPlanned,
        lesson: String = "",
        tags: Set<String> = [],
        tradeIDs: [UUID] = [],
        createdAt: Date = Date(timeIntervalSince1970: 1_734_000_000),
        updatedAt: Date? = nil
    ) -> TradeJournal {
        TradeJournal(
            tradeIDs: tradeIDs,
            title: title,
            reason: reason,
            emotion: emotion,
            deviation: deviation,
            lesson: lesson,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )
    }

    private func makeTrade(
        id: UUID = UUID(),
        instrumentID: String = "rb2510",
        direction: Direction = .buy,
        offsetFlag: OffsetFlag = .open,
        price: Decimal = 3500,
        volume: Int = 1,
        timestamp: Date = Date(timeIntervalSince1970: 1_734_000_000)
    ) -> Trade {
        Trade(
            id: id,
            tradeReference: "ref",
            instrumentID: instrumentID,
            direction: direction,
            offsetFlag: offsetFlag,
            price: price,
            volume: volume,
            commission: 0,
            timestamp: timestamp,
            source: .manual
        )
    }

    // MARK: - generateSingle

    @Test("单篇 · 标题与时间戳出现")
    func singleTitleAndTimestamps() {
        let j = makeJournal(title: "螺纹追多复盘")
        let md = JournalMarkdownReport.generateSingle(j, generatedAt: Date(timeIntervalSince1970: 1_734_100_000))
        #expect(md.contains("# 螺纹追多复盘"))
        #expect(md.contains("生成时间："))
        #expect(md.contains("创建："))
        #expect(md.contains("更新："))
    }

    @Test("单篇 · 元数据 含情绪/偏差/标签")
    func singleMetadata() {
        let j = makeJournal(emotion: .greedy, deviation: .chaseHigh, tags: ["反弹", "螺纹"])
        let md = JournalMarkdownReport.generateSingle(j)
        #expect(md.contains("情绪：**贪婪**"))
        #expect(md.contains("偏差：**追高**"))
        #expect(md.contains("`反弹`"))
        #expect(md.contains("`螺纹`"))
    }

    @Test("单篇 · 空标签显示破折号")
    func singleEmptyTags() {
        let j = makeJournal(tags: [])
        let md = JournalMarkdownReport.generateSingle(j)
        #expect(md.contains("- 标签：—"))
    }

    @Test("单篇 · 空 reason/lesson 显示_未填写_")
    func singleEmptyReasonLesson() {
        let j = makeJournal(reason: "", lesson: "")
        let md = JournalMarkdownReport.generateSingle(j)
        #expect(md.contains("## 交易理由"))
        #expect(md.contains("_未填写_"))
        #expect(md.contains("## 教训 / 复盘"))
    }

    @Test("单篇 · 关联成交表格")
    func singleTradeTable() {
        let id1 = UUID()
        let id2 = UUID()
        let t1 = makeTrade(id: id1, direction: .buy, offsetFlag: .open, price: 3500, timestamp: Date(timeIntervalSince1970: 1_734_000_000))
        let t2 = makeTrade(id: id2, direction: .sell, offsetFlag: .close, price: 3520, timestamp: Date(timeIntervalSince1970: 1_734_010_000))
        let j = makeJournal(tradeIDs: [id1, id2])
        let md = JournalMarkdownReport.generateSingle(j, trades: [t2, t1])
        #expect(md.contains("## 关联成交"))
        #expect(md.contains("| 时间 | 合约 | 方向 | 开/平 | 价格 | 数量 |"))
        #expect(md.contains("买"))
        #expect(md.contains("卖"))
        // 按 timestamp 排序：t1 早于 t2
        let i1 = md.range(of: "买")?.lowerBound
        let i2 = md.range(of: "卖")?.lowerBound
        #expect(i1 != nil && i2 != nil)
        if let i1 = i1, let i2 = i2 { #expect(i1 < i2) }
    }

    @Test("单篇 · 关联但 trades 列表为空")
    func singleOrphanTradeIDs() {
        let id1 = UUID()
        let j = makeJournal(tradeIDs: [id1])
        let md = JournalMarkdownReport.generateSingle(j, trades: [])
        #expect(md.contains("关联 1 笔"))
        #expect(md.contains("找不到对应记录"))
    }

    @Test("单篇 · 无关联成交")
    func singleNoTrades() {
        let j = makeJournal(tradeIDs: [])
        let md = JournalMarkdownReport.generateSingle(j)
        #expect(md.contains("_无关联成交_"))
    }

    // MARK: - generate (月报)

    @Test("月报 · 篇数 + 关联合计 + 唯一标签数")
    func monthOverview() {
        let id1 = UUID()
        let j1 = makeJournal(tags: ["A", "B"], tradeIDs: [id1])
        let j2 = makeJournal(tags: ["B", "C"])
        let md = JournalMarkdownReport.generate([j1, j2])
        #expect(md.contains("篇数：**2**"))
        #expect(md.contains("关联成交合计：**1**"))
        #expect(md.contains("唯一标签数：**3**"))
    }

    @Test("月报 · 情绪/偏差分布表（含 0 计数）")
    func monthDistributions() {
        let j = makeJournal(emotion: .confident, deviation: .breakStopLoss)
        let md = JournalMarkdownReport.generate([j])
        #expect(md.contains("## 情绪分布"))
        #expect(md.contains("| 自信 | 1 |"))
        #expect(md.contains("| 贪婪 | 0 |"))
        #expect(md.contains("## 偏差分布"))
        #expect(md.contains("| 破止损 | 1 |"))
    }

    @Test("月报 · 标签 top10 按计数降序")
    func monthTopTags() {
        let j1 = makeJournal(tags: ["螺纹", "反弹"])
        let j2 = makeJournal(tags: ["螺纹"])
        let j3 = makeJournal(tags: ["螺纹", "夜盘"])
        let md = JournalMarkdownReport.generate([j1, j2, j3])
        #expect(md.contains("| `螺纹` | 3 |"))
        let i螺 = md.range(of: "`螺纹`")?.lowerBound
        let i反 = md.range(of: "`反弹`")?.lowerBound
        #expect(i螺 != nil && i反 != nil)
        if let i螺 = i螺, let i反 = i反 { #expect(i螺 < i反) }
    }

    @Test("月报 · 标签 top10 空时显示_暂无标签_")
    func monthEmptyTags() {
        let j = makeJournal(tags: [])
        let md = JournalMarkdownReport.generate([j])
        #expect(md.contains("_暂无标签_"))
    }

    @Test("月报 · filterEmotion 应用")
    func monthFilterEmotion() {
        let j1 = makeJournal(title: "A", emotion: .confident)
        let j2 = makeJournal(title: "B", emotion: .greedy)
        let md = JournalMarkdownReport.generate([j1, j2], filterEmotion: .greedy)
        #expect(md.contains("篇数：**1**"))
        #expect(md.contains("| B |"))
        #expect(!md.contains("| A |"))
    }

    @Test("月报 · filterCutoff 应用")
    func monthFilterCutoff() {
        let cutoff = Date(timeIntervalSince1970: 1_734_050_000)
        let j1 = makeJournal(title: "Old", createdAt: Date(timeIntervalSince1970: 1_734_000_000))
        let j2 = makeJournal(title: "New", createdAt: Date(timeIntervalSince1970: 1_734_100_000))
        let md = JournalMarkdownReport.generate([j1, j2], filterCutoff: cutoff)
        #expect(md.contains("篇数：**1**"))
        #expect(md.contains("| New |"))
        #expect(!md.contains("| Old |"))
    }

    @Test("月报 · filterLabel 出现在标题")
    func monthFilterLabel() {
        let j = makeJournal()
        let md = JournalMarkdownReport.generate([j], filterLabel: "本月 · 自信")
        #expect(md.contains("（本月 · 自信）"))
    }

    @Test("月报 · 最近 N 篇按 updatedAt desc")
    func monthRecentDesc() {
        let j1 = makeJournal(title: "Old", updatedAt: Date(timeIntervalSince1970: 1_734_000_000))
        let j2 = makeJournal(title: "New", updatedAt: Date(timeIntervalSince1970: 1_734_100_000))
        let md = JournalMarkdownReport.generate([j1, j2], recentLimit: 10)
        let iNew = md.range(of: "| New |")?.lowerBound
        let iOld = md.range(of: "| Old |")?.lowerBound
        #expect(iNew != nil && iOld != nil)
        if let iNew = iNew, let iOld = iOld { #expect(iNew < iOld) }
    }

    @Test("月报 · 标题中的 | 转义")
    func monthTitlePipeEscape() {
        let j = makeJournal(title: "A | B")
        let md = JournalMarkdownReport.generate([j])
        #expect(md.contains("A \\| B"))
    }

    @Test("月报 · 空 journals 显示_暂无日志_")
    func monthEmpty() {
        let md = JournalMarkdownReport.generate([])
        #expect(md.contains("_暂无日志_"))
    }

    @Test("月报 · filterMonth 应用 yyyy-MM")
    func monthFilterMonth() {
        // 构造两篇不同月份的 journal · Asia/Shanghai 时区
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dApr = cal.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let dMay = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let j1 = makeJournal(title: "Apr", createdAt: dApr)
        let j2 = makeJournal(title: "May", createdAt: dMay)
        let md = JournalMarkdownReport.generate([j1, j2], filterMonth: "2026-04")
        #expect(md.contains("篇数：**1**"))
        #expect(md.contains("| Apr |"))
        #expect(!md.contains("| May |"))
    }
}
