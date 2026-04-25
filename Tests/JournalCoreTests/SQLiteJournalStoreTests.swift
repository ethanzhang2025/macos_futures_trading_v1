// WP-19a-3 · SQLiteJournalStore 协议合约测试

import Testing
import Foundation
import Shared
@testable import JournalCore

private func makeStore() throws -> SQLiteJournalStore {
    try SQLiteJournalStore(path: ":memory:")
}

private func makeTrade(
    instrumentID: String = "rb2510",
    direction: Direction = .buy,
    offsetFlag: OffsetFlag = .open,
    price: Decimal = 3500,
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> Trade {
    Trade(
        tradeReference: UUID().uuidString.prefix(8).description,
        instrumentID: instrumentID, direction: direction, offsetFlag: offsetFlag,
        price: price, volume: 1, commission: 4.5,
        timestamp: timestamp, source: .manual
    )
}

private func makeJournal(
    title: String = "标题",
    tags: Set<String> = [],
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> TradeJournal {
    TradeJournal(
        title: title, reason: "理由", emotion: .calm, deviation: .asPlanned,
        lesson: "教训", tags: tags,
        createdAt: createdAt, updatedAt: createdAt
    )
}

@Suite("SQLiteJournalStore · Trade")
struct SQLiteJournalStoreTradeTests {

    @Test("空 store loadAllTrades → 空")
    func emptyTrades() async throws {
        let store = try makeStore()
        #expect(try await store.loadAllTrades().isEmpty)
    }

    @Test("saveTrades + loadAll 按 timestamp 升序")
    func saveAndLoad() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveTrades([
            makeTrade(timestamp: t.addingTimeInterval(120)),
            makeTrade(timestamp: t),
            makeTrade(timestamp: t.addingTimeInterval(60))
        ])
        let trades = try await store.loadAllTrades()
        #expect(trades.count == 3)
        #expect(trades[0].timestamp == t)
        #expect(trades[2].timestamp == t.addingTimeInterval(120))
    }

    @Test("saveTrades 重复 id 覆盖")
    func saveReplaces() async throws {
        let store = try makeStore()
        let trade = makeTrade(price: 3500)
        try await store.saveTrades([trade])

        var updated = trade
        updated.price = 3600
        try await store.saveTrades([updated])

        let loaded = try await store.loadAllTrades()
        #expect(loaded.count == 1)
        #expect(loaded[0].price == 3600)
    }

    @Test("loadTrades(forInstrumentID:) 过滤")
    func loadByInstrument() async throws {
        let store = try makeStore()
        try await store.saveTrades([
            makeTrade(instrumentID: "rb2510"),
            makeTrade(instrumentID: "hc2510")
        ])
        let rb = try await store.loadTrades(forInstrumentID: "rb2510")
        #expect(rb.count == 1)
        #expect(rb[0].instrumentID == "rb2510")
    }

    @Test("loadTrades(from:to:) 时间范围 [from, to)")
    func loadByDateRange() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveTrades([
            makeTrade(timestamp: t),                      // 在
            makeTrade(timestamp: t.addingTimeInterval(60)),  // 在
            makeTrade(timestamp: t.addingTimeInterval(120)) // 不在 (== to)
        ])
        let inRange = try await store.loadTrades(
            from: t, to: t.addingTimeInterval(120)
        )
        #expect(inRange.count == 2)
    }

    @Test("deleteTrade 仅删指定")
    func deleteTrade() async throws {
        let store = try makeStore()
        let t1 = makeTrade()
        let t2 = makeTrade()
        try await store.saveTrades([t1, t2])
        try await store.deleteTrade(id: t1.id)
        let remaining = try await store.loadAllTrades()
        #expect(remaining.count == 1)
        #expect(remaining[0].id == t2.id)
    }
}

@Suite("SQLiteJournalStore · Journal")
struct SQLiteJournalStoreJournalTests {

    @Test("空 store loadAllJournals → 空")
    func emptyJournals() async throws {
        let store = try makeStore()
        #expect(try await store.loadAllJournals().isEmpty)
    }

    @Test("saveJournal + loadAll 按 createdAt 降序")
    func saveAndLoad() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.saveJournal(makeJournal(title: "B", createdAt: t.addingTimeInterval(60)))
        try await store.saveJournal(makeJournal(title: "A", createdAt: t))
        let journals = try await store.loadAllJournals()
        #expect(journals.count == 2)
        #expect(journals[0].title == "B")  // 后创建的在前
    }

    @Test("loadJournal(id:) 单查")
    func loadByID() async throws {
        let store = try makeStore()
        let j = makeJournal()
        try await store.saveJournal(j)
        let loaded = try await store.loadJournal(id: j.id)
        #expect(loaded?.id == j.id)
        #expect(loaded?.title == "标题")
    }

    @Test("loadJournals(withAnyTag:) 标签过滤")
    func loadByTags() async throws {
        let store = try makeStore()
        try await store.saveJournal(makeJournal(title: "A", tags: ["alpha", "beta"]))
        try await store.saveJournal(makeJournal(title: "B", tags: ["beta"]))
        try await store.saveJournal(makeJournal(title: "C", tags: ["gamma"]))

        let alphaOrBeta = try await store.loadJournals(withAnyTag: ["alpha", "beta"])
        #expect(alphaOrBeta.count == 2)
        let gamma = try await store.loadJournals(withAnyTag: ["gamma"])
        #expect(gamma.count == 1)
    }

    @Test("tradeIDs / tags JSON 持久化往返")
    func roundtripCollections() async throws {
        let store = try makeStore()
        let tids = [UUID(), UUID(), UUID()]
        let j = TradeJournal(
            tradeIDs: tids, title: "T",
            tags: ["a", "b"],
            createdAt: Date(), updatedAt: Date()
        )
        try await store.saveJournal(j)
        let loaded = try await store.loadJournal(id: j.id)
        #expect(loaded?.tradeIDs == tids)
        #expect(loaded?.tags == ["a", "b"])
    }

    @Test("deleteJournal 仅删指定")
    func deleteJournal() async throws {
        let store = try makeStore()
        let a = makeJournal(title: "A")
        let b = makeJournal(title: "B")
        try await store.saveJournal(a)
        try await store.saveJournal(b)

        try await store.deleteJournal(id: a.id)
        let remaining = try await store.loadAllJournals()
        #expect(remaining.count == 1)
        #expect(remaining[0].id == b.id)
    }
}

@Suite("SQLiteJournalStore · 文件持久化")
struct SQLiteJournalStoreFileTests {

    @Test("trades + journals 重启加载完整")
    func filePersistence() async throws {
        let path = NSTemporaryDirectory() + "wp19a3_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store1 = try SQLiteJournalStore(path: path)
        let trade = makeTrade()
        let journal = makeJournal(tags: ["x"])
        try await store1.saveTrades([trade])
        try await store1.saveJournal(journal)
        await store1.close()

        let store2 = try SQLiteJournalStore(path: path)
        #expect(try await store2.loadAllTrades().count == 1)
        #expect(try await store2.loadAllJournals().count == 1)
        #expect(try await store2.loadAllJournals()[0].tags == ["x"])
        await store2.close()
    }
}
