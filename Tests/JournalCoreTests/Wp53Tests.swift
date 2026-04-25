// WP-53 · 交易日志测试
// Trade / RawDeal CSV 解析（文华+通用）/ TradeJournal / JournalStore CRUD / JournalGenerator 聚合

import Testing
import Foundation
import Shared
@testable import JournalCore

// MARK: - 测试辅助

private func makeTrade(
    _ instrumentID: String = "rb2510",
    direction: Direction = .buy,
    offset: OffsetFlag = .open,
    price: Decimal = 3500,
    volume: Int = 1,
    commission: Decimal = 5,
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
    source: TradeSource = .wenhua
) -> Trade {
    Trade(
        tradeReference: "ref-\(UUID().uuidString.prefix(8))",
        instrumentID: instrumentID,
        direction: direction, offsetFlag: offset,
        price: price, volume: volume, commission: commission,
        timestamp: timestamp, source: source
    )
}

// MARK: - 1. Trade 模型契约

@Suite("Trade · 数据契约")
struct TradeTests {

    @Test("Codable JSON 往返（含 Direction/OffsetFlag）")
    func codableRoundTrip() throws {
        let t = makeTrade(direction: .sell, offset: .closeToday, price: 3600, volume: 5)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(t)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Trade.self, from: data)
        #expect(decoded == t)
    }

    @Test("notional = price × volume × multiple")
    func notionalCalc() {
        let t = makeTrade(price: 3500, volume: 2)
        #expect(t.notional(volumeMultiple: 10) == 70_000)
    }

    @Test("TradeSource 3 类全枚举")
    func tradeSourceCases() {
        #expect(TradeSource.allCases.count == 3)
        #expect(Set(TradeSource.allCases.map(\.rawValue)) == Set(["wenhua", "generic", "manual"]))
    }
}

// MARK: - 2. CSV 解析（文华格式）

@Suite("DealCSVParser · 文华格式")
struct WenhuaCSVTests {

    private let csv = """
    合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号
    rb2510,买,开仓,3500,2,5.00,2026-04-25 09:30:00,W001
    rb2510,卖,平仓,3520,2,5.00,2026-04-25 14:00:00,W002
    """

    @Test("解析文华 CSV 得 2 条 RawDeal + 字段对齐")
    func parseWenhua() throws {
        let raws = try DealCSVParser.parse(csv, format: .wenhua)
        #expect(raws.count == 2)
        #expect(raws[0].fields["合约"] == "rb2510")
        #expect(raws[0].fields["买卖"] == "买")
        #expect(raws[0].lineNumber == 2)
        #expect(raws[1].lineNumber == 3)
    }

    @Test("RawDeal.toTrade 转换文华格式")
    func wenhuaToTrade() throws {
        let raws = try DealCSVParser.parse(csv, format: .wenhua)
        let t1 = try raws[0].toTrade()
        #expect(t1.instrumentID == "rb2510")
        #expect(t1.direction == .buy)
        #expect(t1.offsetFlag == .open)
        #expect(t1.price == 3500)
        #expect(t1.volume == 2)
        #expect(t1.commission == 5)
        #expect(t1.tradeReference == "W001")
        #expect(t1.source == .wenhua)

        let t2 = try raws[1].toTrade()
        #expect(t2.direction == .sell)
        #expect(t2.offsetFlag == .close)
    }

    @Test("缺关键列抛 missingColumn")
    func missingColumnThrows() {
        let bad = "买卖,成交价\n买,3500"
        #expect(throws: DealCSVError.self) {
            _ = try DealCSVParser.parse(bad, format: .wenhua)
        }
    }

    @Test("非法买卖字段抛 invalidValue")
    func invalidDirectionThrows() throws {
        let bad = """
        合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号
        rb2510,xxx,开仓,3500,2,5.00,2026-04-25 09:30:00,W001
        """
        let raws = try DealCSVParser.parse(bad, format: .wenhua)
        #expect(throws: DealCSVError.self) {
            _ = try raws[0].toTrade()
        }
    }

    @Test("空行 / 表头被跳过")
    func skipEmptyLines() throws {
        let withEmpty = """
        合约,买卖,开平,成交价,成交量,手续费,成交时间,成交编号

        rb2510,买,开仓,3500,2,5,2026-04-25 09:30:00,W001

        """
        let raws = try DealCSVParser.parse(withEmpty, format: .wenhua)
        #expect(raws.count == 1)
    }
}

// MARK: - 3. CSV 解析（通用格式）

@Suite("DealCSVParser · 通用格式")
struct GenericCSVTests {

    private let csv = """
    instrument,direction,offset,price,volume,commission,timestamp,trade_id
    hc2510,buy,open,3000,1,3.5,2026-04-25 09:30:00,G001
    hc2510,sell,close_today,3050,1,3.5,2026-04-25 14:00:00,G002
    """

    @Test("解析通用 CSV 转换 Trade")
    func parseAndConvert() throws {
        let raws = try DealCSVParser.parse(csv, format: .generic)
        #expect(raws.count == 2)

        let t1 = try raws[0].toTrade()
        #expect(t1.instrumentID == "hc2510")
        #expect(t1.direction == .buy)
        #expect(t1.offsetFlag == .open)
        #expect(t1.source == .generic)

        let t2 = try raws[1].toTrade()
        #expect(t2.offsetFlag == .closeToday)
        #expect(t2.tradeReference == "G002")
    }
}

// MARK: - 4. TradeJournal 模型

@Suite("TradeJournal · 数据契约")
struct TradeJournalTests {

    @Test("默认值")
    func defaults() {
        let j = TradeJournal(title: "test")
        #expect(j.tradeIDs.isEmpty)
        #expect(j.emotion == .calm)
        #expect(j.deviation == .asPlanned)
        #expect(j.tags.isEmpty)
    }

    @Test("Codable 往返（含 Set<String> tags）")
    func codable() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let j = TradeJournal(
            tradeIDs: [UUID()],
            title: "t",
            reason: "r",
            emotion: .confident,
            deviation: .chaseHigh,
            lesson: "L",
            tags: ["趋势", "突破"],
            createdAt: now,
            updatedAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(j)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TradeJournal.self, from: data)
        #expect(decoded == j)
    }

    @Test("JournalEmotion / JournalDeviation 全枚举")
    func emotionsAndDeviationsCount() {
        #expect(JournalEmotion.allCases.count == 5)
        #expect(JournalDeviation.allCases.count == 8)
    }
}

// MARK: - 5. JournalStore CRUD

@Suite("InMemoryJournalStore · Trade 持久化")
struct StoreTradeTests {

    @Test("saveTrades + loadAllTrades 按时间升序")
    func saveLoad() async throws {
        let store = InMemoryJournalStore()
        let t1 = makeTrade(timestamp: Date(timeIntervalSince1970: 1000))
        let t2 = makeTrade(timestamp: Date(timeIntervalSince1970: 500))
        try await store.saveTrades([t1, t2])
        let loaded = try await store.loadAllTrades()
        #expect(loaded.map(\.timestamp) == [Date(timeIntervalSince1970: 500), Date(timeIntervalSince1970: 1000)])
    }

    @Test("loadTrades(forInstrumentID:) 按合约过滤")
    func filterByInstrument() async throws {
        let store = InMemoryJournalStore()
        try await store.saveTrades([
            makeTrade("rb2510"),
            makeTrade("hc2510"),
            makeTrade("rb2510"),
        ])
        let rb = try await store.loadTrades(forInstrumentID: "rb2510")
        #expect(rb.count == 2)
    }

    @Test("loadTrades(from:to:) 按时间范围 [from, to)")
    func filterByTimeRange() async throws {
        let store = InMemoryJournalStore()
        try await store.saveTrades([
            makeTrade(timestamp: Date(timeIntervalSince1970: 500)),
            makeTrade(timestamp: Date(timeIntervalSince1970: 1000)),
            makeTrade(timestamp: Date(timeIntervalSince1970: 2000)),
        ])
        let result = try await store.loadTrades(
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 1500)
        )
        #expect(result.count == 2)
    }

    @Test("deleteTrade 移除指定")
    func delete() async throws {
        let store = InMemoryJournalStore()
        let t = makeTrade()
        try await store.saveTrades([t])
        try await store.deleteTrade(id: t.id)
        #expect(try await store.loadAllTrades().isEmpty)
    }
}

@Suite("InMemoryJournalStore · Journal 持久化")
struct StoreJournalTests {

    private func makeJ(_ title: String, createdAt: Date = Date(timeIntervalSince1970: 1_000_000), tags: Set<String> = []) -> TradeJournal {
        TradeJournal(title: title, tags: tags, createdAt: createdAt)
    }

    @Test("saveJournal + loadAllJournals 按 createdAt 降序")
    func saveLoad() async throws {
        let store = InMemoryJournalStore()
        let early = makeJ("早", createdAt: Date(timeIntervalSince1970: 500))
        let late = makeJ("晚", createdAt: Date(timeIntervalSince1970: 1000))
        try await store.saveJournal(early)
        try await store.saveJournal(late)
        let loaded = try await store.loadAllJournals()
        #expect(loaded.map(\.title) == ["晚", "早"])
    }

    @Test("loadJournal(id:) 命中与不命中")
    func loadByID() async throws {
        let store = InMemoryJournalStore()
        let j = makeJ("t")
        try await store.saveJournal(j)
        #expect(try await store.loadJournal(id: j.id)?.title == "t")
        #expect(try await store.loadJournal(id: UUID()) == nil)
    }

    @Test("loadJournals(withAnyTag:) 含任一标签即匹配")
    func filterByTag() async throws {
        let store = InMemoryJournalStore()
        let j1 = makeJ("t1", tags: ["趋势"])
        let j2 = makeJ("t2", tags: ["突破", "短线"])
        let j3 = makeJ("t3", tags: ["套利"])
        try await store.saveJournal(j1)
        try await store.saveJournal(j2)
        try await store.saveJournal(j3)

        let result = try await store.loadJournals(withAnyTag: ["趋势", "突破"])
        #expect(result.count == 2)
        #expect(Set(result.map(\.title)) == Set(["t1", "t2"]))
    }

    @Test("deleteJournal 不级联删 trades（A09 单向约束）")
    func deleteJournalDoesNotAffectTrades() async throws {
        let store = InMemoryJournalStore()
        let t = makeTrade()
        let j = TradeJournal(tradeIDs: [t.id], title: "j")
        try await store.saveTrades([t])
        try await store.saveJournal(j)

        try await store.deleteJournal(id: j.id)
        #expect(try await store.loadAllJournals().isEmpty)
        // trade 仍在
        #expect(try await store.loadAllTrades().count == 1)
    }
}

// MARK: - 6. JournalGenerator 聚合

@Suite("JournalGenerator · 半自动初稿")
struct GeneratorTests {

    @Test("空 trades → 空 drafts")
    func emptyInput() {
        let drafts = JournalGenerator.generateDrafts(from: [])
        #expect(drafts.isEmpty)
    }

    @Test("同合约连续 trades（窗口内）→ 1 篇 draft")
    func consecutiveSameInstrument() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let trades = [
            makeTrade("rb2510", timestamp: base),
            makeTrade("rb2510", timestamp: base.addingTimeInterval(3600)),  // +1h
            makeTrade("rb2510", timestamp: base.addingTimeInterval(7200)),  // +2h
        ]
        let drafts = JournalGenerator.generateDrafts(from: trades)
        #expect(drafts.count == 1)
        #expect(drafts[0].tradeIDs.count == 3)
        #expect(drafts[0].title.contains("rb2510"))
    }

    @Test("跨窗口 → 拆分为多篇 draft")
    func splitAcrossWindows() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let trades = [
            makeTrade("rb2510", timestamp: base),
            makeTrade("rb2510", timestamp: base.addingTimeInterval(3600)),
            // 间隔 > 8h（默认窗口） → 新段
            makeTrade("rb2510", timestamp: base.addingTimeInterval(3600 + 9 * 3600)),  // 9h after t2
        ]
        let drafts = JournalGenerator.generateDrafts(from: trades)
        let rbDrafts = drafts.filter { $0.title.contains("rb2510") }
        #expect(rbDrafts.count == 2)
    }

    @Test("不同合约 → 各自独立 draft")
    func multipleInstruments() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let trades = [
            makeTrade("rb2510", timestamp: base),
            makeTrade("hc2510", timestamp: base.addingTimeInterval(60)),
        ]
        let drafts = JournalGenerator.generateDrafts(from: trades)
        #expect(drafts.count == 2)
        #expect(Set(drafts.map { $0.title.split(separator: " ").first.map(String.init) ?? "" })
                == Set(["rb2510", "hc2510"]))
    }

    @Test("draft 包含统计模板（开/平/总手数）")
    func draftReasonContainsStats() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let trades = [
            makeTrade("rb2510", offset: .open, volume: 2, timestamp: base),
            makeTrade("rb2510", offset: .close, volume: 2, timestamp: base.addingTimeInterval(60)),
        ]
        let drafts = JournalGenerator.generateDrafts(from: trades)
        let reason = drafts[0].reason
        #expect(reason.contains("开 1"))
        #expect(reason.contains("平 1"))
        #expect(reason.contains("总手数：4"))
    }

    @Test("draft 不修改原始 trades（A09 单向约束）")
    func draftDoesNotMutateTrades() {
        let original = [makeTrade("rb2510")]
        let originalCopy = original
        _ = JournalGenerator.generateDrafts(from: original)
        // value type 拷贝，原数组与拷贝不变
        #expect(original == originalCopy)
    }
}
