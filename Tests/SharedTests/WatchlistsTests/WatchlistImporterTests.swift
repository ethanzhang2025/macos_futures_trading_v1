// WP-64 · WatchlistImporter 单元测试
// 覆盖：切分（无/单/多）+ 注释/空行 + 同组去重 + merge（同名追加 / 新名创建 / 重复跳过）+ DoD 50+ 合约

import Testing
import Foundation
@testable import Shared

@Suite("WatchlistImporter · 解析 + 合并到 Book")
struct WatchlistImporterTests {

    // MARK: - parse

    @Test("无标头 · 整文件单组 '导入'")
    func untitledSingleGroup() {
        let text = """
        rb2510
        ag2510
        au2512
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].name == "导入")
        #expect(r.groups[0].instrumentIDs == ["rb2510", "ag2510", "au2512"])
    }

    @Test("单组标头 · 名称取自 {GROUP}")
    func singleGroupHeader() {
        let text = """
        {黑色系}
        rb2510
        i2509
        j2509
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].name == "黑色系")
        #expect(r.groups[0].instrumentIDs == ["rb2510", "i2509", "j2509"])
    }

    @Test("多组分隔 · 顺序保留")
    func multipleGroups() {
        let text = """
        {黑色}
        rb2510
        i2509

        {贵金属}
        au2512
        ag2510
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups.count == 2)
        #expect(r.groups.map(\.name) == ["黑色", "贵金属"])
        #expect(r.groups[0].instrumentIDs == ["rb2510", "i2509"])
        #expect(r.groups[1].instrumentIDs == ["au2512", "ag2510"])
    }

    @Test("# 注释行 + 空行 · 全部忽略")
    func commentsAndBlankLinesIgnored() {
        let text = """
        # 文件级注释
        {黑色}

        # 这一组有 3 个合约
        rb2510
        # 螺纹 10 月

        i2509
        j2509
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups[0].instrumentIDs == ["rb2510", "i2509", "j2509"])
    }

    @Test("同组内重复合约 · 仅保留首次（顺序保留）")
    func sameGroupDeduplicate() {
        let text = """
        {黑色}
        rb2510
        i2509
        rb2510
        j2509
        i2509
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups[0].instrumentIDs == ["rb2510", "i2509", "j2509"])
    }

    @Test("空标头组（仅注释 / 空行 / 无合约）· 跳过 · 不入结果")
    func emptyGroupSkipped() {
        let text = """
        {EMPTY}

        # 无合约

        {黑色}
        rb2510
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups.count == 1)
        #expect(r.groups[0].name == "黑色")
    }

    @Test("totalInstruments · 累加全部组合约数")
    func totalInstrumentsCount() {
        let text = """
        {A}
        a1
        a2
        {B}
        b1
        b2
        b3
        """
        #expect(WatchlistImporter.parse(text).totalInstruments == 5)
    }

    @Test("空标头 `{}` 视作匿名组 · fallback '导入'")
    func emptyHeaderName() {
        let text = """
        {}
        rb2510
        """
        let r = WatchlistImporter.parse(text)
        #expect(r.groups[0].name == "导入")
    }

    // MARK: - merge

    @Test("merge · 全新分组 · 创建分组 + 添加全部合约")
    func mergeAllNew() {
        var book = WatchlistBook()
        let result = WatchlistImporter.parse("""
        {黑色}
        rb2510
        i2509
        """)
        let summary = WatchlistImporter.merge(result, into: &book)
        #expect(summary.newGroupsCreated == 1)
        #expect(summary.instrumentsAdded == 2)
        #expect(summary.instrumentsSkippedDuplicate == 0)
        #expect(book.groups.count == 1)
        #expect(book.groups[0].name == "黑色")
        #expect(book.groups[0].instrumentIDs == ["rb2510", "i2509"])
    }

    @Test("merge · 同名分组 · 追加到现有 + 跳过已存在合约")
    func mergeSameNameGroup() {
        var book = WatchlistBook()
        book.addGroup(name: "黑色")
        book.addInstrument("rb2510", to: book.groups[0].id)

        let result = WatchlistImporter.parse("""
        {黑色}
        rb2510
        i2509
        j2509
        """)
        let summary = WatchlistImporter.merge(result, into: &book)
        #expect(summary.newGroupsCreated == 0)
        #expect(summary.instrumentsAdded == 2)
        #expect(summary.instrumentsSkippedDuplicate == 1)  // rb2510 已存在
        #expect(book.groups.count == 1)
        #expect(book.groups[0].instrumentIDs == ["rb2510", "i2509", "j2509"])
    }

    @Test("merge · 多组混合（同名 + 新名）· 各自正确处理")
    func mergeMixed() {
        var book = WatchlistBook()
        book.addGroup(name: "黑色")
        book.addInstrument("rb2510", to: book.groups[0].id)

        let result = WatchlistImporter.parse("""
        {黑色}
        i2509

        {贵金属}
        au2512
        ag2510
        """)
        let summary = WatchlistImporter.merge(result, into: &book)
        #expect(summary.newGroupsCreated == 1)  // 贵金属
        #expect(summary.instrumentsAdded == 3)  // i2509 + au + ag
        #expect(summary.instrumentsSkippedDuplicate == 0)
        #expect(book.groups.count == 2)
    }

    // MARK: - WP-64 DoD · 50+ 合约

    @Test("WP-64 DoD · 5 组 50+ 合约 · 全部导入无丢失")
    func wp64DoD_50PlusInstruments() {
        let text = """
        # WP-64 DoD · 5 组 50+ 合约（覆盖黑色 / 化工 / 农产品 / 有色 / 贵金属）
        {黑色系}
        rb2510
        rb2601
        i2509
        i2601
        j2509
        j2601
        jm2509
        jm2601
        hc2510
        hc2601
        sm2509
        sm2601

        {化工}
        ma2509
        ma2601
        l2509
        l2601
        pp2509
        pp2601
        ta2509
        ta2601
        ru2509
        ru2601

        {农产品}
        m2509
        m2601
        a2509
        a2601
        y2509
        y2601
        c2509
        c2601
        cs2509
        cs2601

        {有色}
        cu2509
        cu2510
        al2509
        al2510
        zn2509
        zn2510
        ni2509
        ni2510
        sn2509
        sn2510
        pb2509
        pb2510

        {贵金属}
        au2510
        au2512
        au2602
        ag2510
        ag2512
        ag2602
        """
        let result = WatchlistImporter.parse(text)
        #expect(result.groups.count == 5)
        #expect(result.totalInstruments >= 50, "应至少 50 合约 · 实际 \(result.totalInstruments)")

        var book = WatchlistBook()
        let summary = WatchlistImporter.merge(result, into: &book)
        #expect(summary.newGroupsCreated == 5)
        #expect(summary.instrumentsAdded == result.totalInstruments)
        #expect(summary.instrumentsSkippedDuplicate == 0)

        // 顺序与映射：每组 instrumentIDs 与原文一致 · 无丢失无错位
        let bookIDs = book.groups.flatMap(\.instrumentIDs)
        let importedIDs = result.groups.flatMap(\.instrumentIDs)
        #expect(bookIDs == importedIDs, "Book 内合约顺序应与原文一致")
    }
}
