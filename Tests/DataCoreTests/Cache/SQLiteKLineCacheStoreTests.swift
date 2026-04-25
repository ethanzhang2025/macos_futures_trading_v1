// WP-19a-2 · SQLiteKLineCacheStore 协议合约测试

import Testing
import Foundation
import Shared
@testable import DataCore

private func makeKLine(
    instrumentID: String = "rb2510",
    period: KLinePeriod = .minute1,
    openTime: Date,
    close: Decimal = 3500
) -> KLine {
    KLine(
        instrumentID: instrumentID, period: period, openTime: openTime,
        open: close, high: close, low: close, close: close,
        volume: 100, openInterest: 12345, turnover: 1_000_000
    )
}

private func makeStore() throws -> SQLiteKLineCacheStore {
    try SQLiteKLineCacheStore(path: ":memory:")
}

@Suite("SQLiteKLineCacheStore · 协议合约")
struct SQLiteKLineCacheStoreTests {

    @Test("空缓存 load → 空数组")
    func emptyLoad() async throws {
        let store = try makeStore()
        let bars = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(bars.isEmpty)
    }

    @Test("save 全量替换 + load 升序")
    func saveAndLoad() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let bars = [
            makeKLine(openTime: t.addingTimeInterval(120), close: 3502),
            makeKLine(openTime: t, close: 3500),
            makeKLine(openTime: t.addingTimeInterval(60), close: 3501)
        ]
        try await store.save(bars, instrumentID: "rb2510", period: .minute1)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 3)
        #expect(loaded[0].close == 3500)
        #expect(loaded[1].close == 3501)
        #expect(loaded[2].close == 3502)
    }

    @Test("save 替换覆盖之前的数据")
    func saveReplaces() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save(
            [makeKLine(openTime: t, close: 3500)],
            instrumentID: "rb2510", period: .minute1
        )
        try await store.save(
            [makeKLine(openTime: t, close: 3600)],
            instrumentID: "rb2510", period: .minute1
        )
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 1)
        #expect(loaded[0].close == 3600)
    }

    @Test("append 增量 · openTime 重复覆盖")
    func appendDeduplicates() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.append(
            [makeKLine(openTime: t, close: 3500)],
            instrumentID: "rb2510", period: .minute1, maxBars: 0
        )
        try await store.append(
            [
                makeKLine(openTime: t, close: 3501),  // 覆盖
                makeKLine(openTime: t.addingTimeInterval(60), close: 3502)  // 新
            ],
            instrumentID: "rb2510", period: .minute1, maxBars: 0
        )
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 2)
        #expect(loaded[0].close == 3501)
        #expect(loaded[1].close == 3502)
    }

    @Test("append maxBars 截尾 · 仅保留最近 N 根")
    func appendMaxBars() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let bars = (0..<10).map { i in
            makeKLine(openTime: t.addingTimeInterval(TimeInterval(i) * 60), close: 3500 + Decimal(i))
        }
        try await store.append(bars, instrumentID: "rb2510", period: .minute1, maxBars: 5)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 5)
        #expect(loaded.first?.close == 3505)
        #expect(loaded.last?.close == 3509)
    }

    @Test("不同 instrumentID + period 严格隔离")
    func keyIsolation() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save([makeKLine(instrumentID: "rb2510", openTime: t)], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine(instrumentID: "hc2510", openTime: t)], instrumentID: "hc2510", period: .minute1)
        try await store.save([makeKLine(period: .minute5, openTime: t)], instrumentID: "rb2510", period: .minute5)

        #expect(try await store.load(instrumentID: "rb2510", period: .minute1).count == 1)
        #expect(try await store.load(instrumentID: "hc2510", period: .minute1).count == 1)
        #expect(try await store.load(instrumentID: "rb2510", period: .minute5).count == 1)
    }

    @Test("clear 仅删除指定 key")
    func clearSpecific() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save([makeKLine(openTime: t)], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine(openTime: t)], instrumentID: "hc2510", period: .minute1)

        try await store.clear(instrumentID: "rb2510", period: .minute1)
        #expect(try await store.load(instrumentID: "rb2510", period: .minute1).isEmpty)
        #expect(try await store.load(instrumentID: "hc2510", period: .minute1).count == 1)
    }

    @Test("clearAll 全删")
    func clearAll() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save([makeKLine(openTime: t)], instrumentID: "rb2510", period: .minute1)
        try await store.clearAll()
        #expect(try await store.load(instrumentID: "rb2510", period: .minute1).isEmpty)
    }

    @Test("Decimal 精度保留（4 位小数）")
    func decimalPrecision() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let bar = KLine(
            instrumentID: "rb2510", period: .minute1, openTime: t,
            open: 3500.1234, high: 3500.5678, low: 3500.0001, close: 3500.9999,
            volume: 100, openInterest: 0, turnover: 12345.6789
        )
        try await store.save([bar], instrumentID: "rb2510", period: .minute1)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded[0].open == 3500.1234)
        #expect(loaded[0].close == 3500.9999)
        #expect(loaded[0].turnover == 12345.6789)
    }

    @Test("文件持久化 · 重启数据完整")
    func filePersistenceAcrossRestarts() async throws {
        let path = NSTemporaryDirectory() + "wp19a2_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store1 = try SQLiteKLineCacheStore(path: path)
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store1.save(
            [makeKLine(openTime: t, close: 3500), makeKLine(openTime: t.addingTimeInterval(60), close: 3501)],
            instrumentID: "rb2510", period: .minute1
        )
        await store1.close()

        let store2 = try SQLiteKLineCacheStore(path: path)
        let loaded = try await store2.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 2)
        await store2.close()
    }
}
