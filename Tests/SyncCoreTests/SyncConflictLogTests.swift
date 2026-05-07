// SyncConflictLog 行为测试 · WP-60 batch002
// 覆盖：record / cap 截断 / filter recordType / since / entries(for:) / paginate

import Testing
import Foundation
@testable import SyncCore

@Suite("InMemoryConflictLog")
struct SyncConflictLogTests {

    private let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    private func conflict(recordType: String = "watchlist",
                          recordID: UUID = UUID(),
                          resolvedOffset: TimeInterval = 0) -> SyncConflict {
        SyncConflict(
            recordType: recordType,
            recordID: recordID,
            localVersion: 1,
            remoteVersion: 2,
            localModified: baseTime,
            remoteModified: baseTime,
            resolution: .local,
            resolvedAt: baseTime.addingTimeInterval(resolvedOffset)
        )
    }

    @Test("record + all")
    func recordAndAll() async {
        let log = InMemoryConflictLog()
        await log.record(conflict())
        await log.record(conflict())
        let count = await log.count()
        #expect(count == 2)
    }

    @Test("cap 触发 FIFO 截断")
    func capTruncates() async {
        let log = InMemoryConflictLog(cap: 3)
        for i in 0..<5 {
            await log.record(conflict(resolvedOffset: TimeInterval(i)))
        }
        let count = await log.count()
        #expect(count == 3)
        let all = await log.all()
        // 留下的应该是最后 3 条（offset 2/3/4）
        #expect(all.first?.resolvedAt == baseTime.addingTimeInterval(2))
        #expect(all.last?.resolvedAt == baseTime.addingTimeInterval(4))
    }

    @Test("filter recordType")
    func filterRecordType() async {
        let log = InMemoryConflictLog()
        await log.record(conflict(recordType: "watchlist"))
        await log.record(conflict(recordType: "workspace"))
        await log.record(conflict(recordType: "watchlist", resolvedOffset: 5))

        let watchlistConflicts = await log.filter(recordType: "watchlist")
        #expect(watchlistConflicts.count == 2)
        // 倒序：offset=5 在前
        #expect(watchlistConflicts.first?.resolvedAt == baseTime.addingTimeInterval(5))
    }

    @Test("since 时间过滤")
    func sinceFilters() async {
        let log = InMemoryConflictLog()
        await log.record(conflict(resolvedOffset: 0))
        await log.record(conflict(resolvedOffset: 10))
        await log.record(conflict(resolvedOffset: 20))

        let recent = await log.since(baseTime.addingTimeInterval(5))
        #expect(recent.count == 2)
        // 倒序 · 最新在前
        #expect(recent.first?.resolvedAt == baseTime.addingTimeInterval(20))
    }

    @Test("entries(for: recordID)")
    func entriesForRecordID() async {
        let log = InMemoryConflictLog()
        let id = UUID()
        await log.record(conflict(recordID: id, resolvedOffset: 0))
        await log.record(conflict(recordID: UUID(), resolvedOffset: 5))
        await log.record(conflict(recordID: id, resolvedOffset: 10))

        let entries = await log.entries(for: id)
        #expect(entries.count == 2)
        #expect(entries.first?.resolvedAt == baseTime.addingTimeInterval(10))
    }

    @Test("paginate offset + limit")
    func paginate() async {
        let log = InMemoryConflictLog()
        for i in 0..<10 {
            await log.record(conflict(resolvedOffset: TimeInterval(i)))
        }
        let page1 = await log.paginate(offset: 0, limit: 3)
        #expect(page1.count == 3)
        // 最近 3 条（9/8/7）
        #expect(page1.first?.resolvedAt == baseTime.addingTimeInterval(9))
        #expect(page1.last?.resolvedAt == baseTime.addingTimeInterval(7))

        let page2 = await log.paginate(offset: 3, limit: 3)
        #expect(page2.count == 3)
        #expect(page2.first?.resolvedAt == baseTime.addingTimeInterval(6))

        let outOfRange = await log.paginate(offset: 100, limit: 5)
        #expect(outOfRange.isEmpty)
    }

    @Test("clear 清空")
    func clear() async {
        let log = InMemoryConflictLog()
        await log.record(conflict())
        await log.clear()
        let count = await log.count()
        #expect(count == 0)
    }

    @Test("recordAll 批量")
    func recordAll() async {
        let log = InMemoryConflictLog()
        await log.recordAll([conflict(), conflict(), conflict()])
        let count = await log.count()
        #expect(count == 3)
    }
}
