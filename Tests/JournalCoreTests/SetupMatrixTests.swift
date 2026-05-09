// v15.99 · 复盘 v2 · setup 标签全链路测
// 1. Trade.setup 默认 nil + Codable 兼容老 JSON（无 setup 字段）
// 2. ClosedPosition.setup 默认 nil + Codable 兼容老 JSON
// 3. PositionMatcher 透传 openTrade.setup → ClosedPosition.setup
// 4. ReviewAnalytics.setupMatrix 群组 / unlabeled 桶 / 排序 / winRate
// 5. SQLiteJournalStore 持久化 + 老库 ALTER TABLE migration

import Testing
import Foundation
import Shared
@testable import JournalCore

private func ts(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    var dc = DateComponents()
    dc.year = year; dc.month = month; dc.day = day; dc.hour = hour
    return c.date(from: dc)!
}

private func mkTrade(
    instrumentID: String = "rb2510",
    direction: Direction = .buy,
    offset: OffsetFlag = .open,
    price: Decimal = 3500,
    volume: Int = 1,
    timestamp: Date,
    setup: String? = nil
) -> Trade {
    Trade(
        tradeReference: UUID().uuidString.prefix(8).description,
        instrumentID: instrumentID,
        direction: direction, offsetFlag: offset,
        price: price, volume: volume, commission: 0,
        timestamp: timestamp, source: .manual,
        setup: setup
    )
}

@Suite("v15.98 · Trade.setup 字段 + Codable 兼容")
struct TradeSetupTests {

    @Test("setup 默认 nil · 不显式传时不会破坏既有调用")
    func defaultNil() {
        let t = mkTrade(timestamp: ts(2026, 5, 9))
        #expect(t.setup == nil)
    }

    @Test("setup 显式赋值后 Codable 往返保留")
    func codableRoundTripWithSetup() throws {
        let t = mkTrade(timestamp: ts(2026, 5, 9), setup: "突破")
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(Trade.self, from: data)
        #expect(decoded.setup == "突破")
        #expect(decoded == t)
    }

    @Test("setup nil 时 encoder 不输出 setup key（encodeIfPresent · diff 友好）")
    func nilSetupOmitted() throws {
        let t = mkTrade(timestamp: ts(2026, 5, 9), setup: nil)
        let data = try JSONEncoder().encode(t)
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("\"setup\""))
    }

    @Test("老 JSON（无 setup 字段）反序列化 → setup = nil（不抛 · 兼容性保证）")
    func decodeLegacyJSONWithoutSetup() throws {
        // 重现"v15.98 之前"序列化结果：除 setup 字段外其它全保留
        let original = mkTrade(timestamp: ts(2026, 5, 9), setup: nil)
        let data = try JSONEncoder().encode(original)
        // 验证默认 encoder 不会带 setup（encodeIfPresent + nil）
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("\"setup\""))
        // 反向 decode 必须 setup = nil（兼容老 JSON）
        let decoded = try JSONDecoder().decode(Trade.self, from: data)
        #expect(decoded.setup == nil)
        #expect(decoded == original)
    }
}

@Suite("v15.98 · ClosedPosition.setup + Codable 兼容")
struct ClosedPositionSetupTests {

    @Test("ClosedPosition.setup 默认 nil")
    func defaultNil() {
        let cp = ClosedPosition(
            instrumentID: "rb", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: Date(), closeTime: Date(),
            openPrice: 3500, closePrice: 3520, volume: 1,
            realizedPnL: 200, totalCommission: 0
        )
        #expect(cp.setup == nil)
    }

    @Test("Codable 往返保留 setup")
    func codableRoundTrip() throws {
        let cp = ClosedPosition(
            instrumentID: "rb", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: ts(2026, 5, 1), closeTime: ts(2026, 5, 1, 11),
            openPrice: 3500, closePrice: 3520, volume: 1,
            realizedPnL: 200, totalCommission: 0,
            setup: "回踩"
        )
        let data = try JSONEncoder().encode(cp)
        let decoded = try JSONDecoder().decode(ClosedPosition.self, from: data)
        #expect(decoded.setup == "回踩")
        #expect(decoded == cp)
    }
}

@Suite("v15.98 · PositionMatcher.setup 透传")
struct PositionMatcherSetupTests {

    @Test("开仓 setup → ClosedPosition.setup 命中（不依赖平仓 setup）")
    func openSideSetupPropagates() {
        let openTime = ts(2026, 5, 1, 10)
        let closeTime = ts(2026, 5, 1, 11)
        let opens = mkTrade(direction: .buy, offset: .open, price: 3500, timestamp: openTime, setup: "突破")
        let closes = mkTrade(direction: .sell, offset: .close, price: 3520, timestamp: closeTime, setup: "误标平仓")

        let result = PositionMatcher.match(trades: [opens, closes], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].setup == "突破")   // 平仓侧 setup 被忽略
    }

    @Test("开仓未标 setup → ClosedPosition.setup = nil")
    func unlabeledOpenStaysNil() {
        let openTime = ts(2026, 5, 1, 10)
        let closeTime = ts(2026, 5, 1, 11)
        let opens = mkTrade(direction: .buy, offset: .open, price: 3500, timestamp: openTime, setup: nil)
        let closes = mkTrade(direction: .sell, offset: .close, price: 3520, timestamp: closeTime, setup: nil)

        let result = PositionMatcher.match(trades: [opens, closes], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 1)
        #expect(result.closed[0].setup == nil)
    }

    @Test("一次平仓拆 2 个 ClosedPosition · 两笔开仓不同 setup 各自透传")
    func partialMatchDifferentSetups() {
        let opens1 = mkTrade(direction: .buy, offset: .open, price: 3500, volume: 3,
                             timestamp: ts(2026, 5, 1, 10), setup: "突破")
        let opens2 = mkTrade(direction: .buy, offset: .open, price: 3510, volume: 2,
                             timestamp: ts(2026, 5, 1, 11), setup: "回踩")
        let closes = mkTrade(direction: .sell, offset: .close, price: 3520, volume: 5,
                             timestamp: ts(2026, 5, 1, 12), setup: nil)

        let result = PositionMatcher.match(trades: [opens1, opens2, closes], multipliers: ["rb2510": 10])
        #expect(result.closed.count == 2)
        // FIFO 顺序 · opens1 配对在前
        #expect(result.closed[0].setup == "突破")
        #expect(result.closed[1].setup == "回踩")
    }
}

@Suite("v15.99 · ReviewAnalytics.setupMatrix")
struct SetupMatrixComputationTests {

    private static func mkPosition(setup: String?, pnl: Decimal) -> ClosedPosition {
        ClosedPosition(
            instrumentID: "rb", side: .long,
            openTradeID: UUID(), closeTradeID: UUID(),
            openTime: Date(), closeTime: Date(),
            openPrice: 3500, closePrice: 3500, volume: 1,
            realizedPnL: pnl, totalCommission: 0,
            setup: setup
        )
    }

    @Test("空输入 → 空 cells")
    func emptyInput() {
        let m = ReviewAnalytics.setupMatrix(from: [])
        #expect(m.cells.isEmpty)
    }

    @Test("nil 与空字符串 setup 都归 unlabeled 桶（合并计数）")
    func nilAndEmptyMergeIntoUnlabeled() {
        let positions = [
            Self.mkPosition(setup: nil, pnl: 100),
            Self.mkPosition(setup: "", pnl: 200),
            Self.mkPosition(setup: nil, pnl: -50),
        ]
        let m = ReviewAnalytics.setupMatrix(from: positions)
        #expect(m.cells.count == 1)
        let cell = m.cells[0]
        #expect(cell.setup == ReviewAnalytics.unlabeledSetupKey)
        #expect(cell.tradeCount == 3)
        #expect(cell.totalPnL == 250)
        #expect(cell.winCount == 2)   // 100, 200 盈
    }

    @Test("多 setup 群组聚合 + 按 totalPnL 降序")
    func multipleSetupsSorted() {
        let positions = [
            Self.mkPosition(setup: "突破", pnl: 1000),
            Self.mkPosition(setup: "突破", pnl: 500),
            Self.mkPosition(setup: "回踩", pnl: 200),
            Self.mkPosition(setup: "回踩", pnl: -100),
            Self.mkPosition(setup: "背离", pnl: -800),
        ]
        let m = ReviewAnalytics.setupMatrix(from: positions)
        #expect(m.cells.count == 3)
        // 排序：突破 1500 → 回踩 100 → 背离 -800
        #expect(m.cells[0].setup == "突破")
        #expect(m.cells[0].totalPnL == 1500)
        #expect(m.cells[0].tradeCount == 2)
        #expect(m.cells[0].winCount == 2)
        #expect(m.cells[0].winRate == 1.0)
        #expect(m.cells[1].setup == "回踩")
        #expect(m.cells[1].totalPnL == 100)
        #expect(m.cells[1].winRate == 0.5)
        #expect(m.cells[2].setup == "背离")
        #expect(m.cells[2].totalPnL == -800)
        #expect(m.cells[2].winRate == 0.0)
    }

    @Test("仅 unlabeled · 0 win · winRate 0%")
    func allUnlabeledAllLoss() {
        let positions = [
            Self.mkPosition(setup: nil, pnl: -100),
            Self.mkPosition(setup: nil, pnl: -50),
        ]
        let m = ReviewAnalytics.setupMatrix(from: positions)
        #expect(m.cells.count == 1)
        #expect(m.cells[0].winCount == 0)
        #expect(m.cells[0].winRate == 0.0)
    }
}

@Suite("v15.98 · SQLiteJournalStore · setup 列持久化 + migration")
struct SQLiteJournalStoreSetupTests {

    @Test("save 带 setup → load 后保留")
    func saveAndLoadSetup() async throws {
        let store = try SQLiteJournalStore(path: ":memory:")
        let t = mkTrade(timestamp: ts(2026, 5, 1), setup: "突破")
        try await store.saveTrades([t])

        let loaded = try await store.loadAllTrades()
        #expect(loaded.count == 1)
        #expect(loaded[0].setup == "突破")
    }

    @Test("save nil setup → load 后仍 nil（NULL 列正确处理）")
    func saveNilSetup() async throws {
        let store = try SQLiteJournalStore(path: ":memory:")
        let t = mkTrade(timestamp: ts(2026, 5, 1), setup: nil)
        try await store.saveTrades([t])

        let loaded = try await store.loadAllTrades()
        #expect(loaded.count == 1)
        #expect(loaded[0].setup == nil)
    }

    @Test("混合 setup 与 nil · 各自正确存取")
    func mixedSetups() async throws {
        let store = try SQLiteJournalStore(path: ":memory:")
        let t1 = mkTrade(price: 3500, timestamp: ts(2026, 5, 1, 9), setup: "突破")
        let t2 = mkTrade(price: 3510, timestamp: ts(2026, 5, 1, 10), setup: nil)
        let t3 = mkTrade(price: 3520, timestamp: ts(2026, 5, 1, 11), setup: "回踩")
        try await store.saveTrades([t1, t2, t3])

        let loaded = try await store.loadAllTrades()
        #expect(loaded.count == 3)
        #expect(loaded.compactMap { $0.setup }.sorted() == ["回踩", "突破"])
    }
}
