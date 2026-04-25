// WP-21a · 子模块 3 K 线缓存层测试
// InMemory + JSONFile 双实现 · 协议合约 / 持久化 / 合并去重 / 截尾 / 多合约隔离

import Testing
import Foundation
import Shared
@testable import DataCore

// MARK: - 测试辅助

private func makeKLine(
    _ instrumentID: String = "rb2510",
    period: KLinePeriod = .minute1,
    openTime: Date,
    close: Decimal = 3500
) -> KLine {
    KLine(
        instrumentID: instrumentID,
        period: period,
        openTime: openTime,
        open: close, high: close, low: close, close: close,
        volume: 0, openInterest: 0, turnover: 0
    )
}

private func date(_ minute: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(minute) * 60)
}

private func tempCacheDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wp21a-cache-test-\(UUID().uuidString)")
}

// MARK: - 1. InMemoryKLineCacheStore

@Suite("InMemoryKLineCacheStore · 协议合约")
struct InMemoryStoreTests {

    @Test("load 空缓存返回 []")
    func loadEmpty() async throws {
        let store = InMemoryKLineCacheStore()
        let result = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(result.isEmpty)
    }

    @Test("save → load 往返 + 按 openTime 排序")
    func saveLoadRoundTrip() async throws {
        let store = InMemoryKLineCacheStore()
        let unsorted = [
            makeKLine(openTime: date(2)),
            makeKLine(openTime: date(0)),
            makeKLine(openTime: date(1)),
        ]
        try await store.save(unsorted, instrumentID: "rb2510", period: .minute1)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.map(\.openTime) == [date(0), date(1), date(2)])
    }

    @Test("append 合并 + 排序 + 去重（同 openTime 覆盖）")
    func appendMergesAndDedups() async throws {
        let store = InMemoryKLineCacheStore()
        try await store.save([
            makeKLine(openTime: date(0), close: 100),
            makeKLine(openTime: date(1), close: 110),
        ], instrumentID: "rb2510", period: .minute1)

        try await store.append([
            makeKLine(openTime: date(1), close: 999),  // 覆盖 openTime=1
            makeKLine(openTime: date(2), close: 120),  // 新增
        ], instrumentID: "rb2510", period: .minute1, maxBars: 0)

        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 3)
        #expect(loaded.map(\.openTime) == [date(0), date(1), date(2)])
        #expect(loaded[1].close == 999)
    }

    @Test("append maxBars 截尾保留最近 N 根")
    func appendCaps() async throws {
        let store = InMemoryKLineCacheStore()
        let bars = (0..<10).map { makeKLine(openTime: date($0)) }
        try await store.append(bars, instrumentID: "rb2510", period: .minute1, maxBars: 3)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 3)
        #expect(loaded.map(\.openTime) == [date(7), date(8), date(9)])
    }

    @Test("append maxBars=0 表示不限")
    func appendUnlimited() async throws {
        let store = InMemoryKLineCacheStore()
        let bars = (0..<100).map { makeKLine(openTime: date($0)) }
        try await store.append(bars, instrumentID: "rb2510", period: .minute1, maxBars: 0)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 100)
    }

    @Test("append 空数组保留现有 + 排序")
    func appendEmptyKeepsExisting() async throws {
        let store = InMemoryKLineCacheStore()
        try await store.save([
            makeKLine(openTime: date(2)),
            makeKLine(openTime: date(0)),
        ], instrumentID: "rb2510", period: .minute1)

        try await store.append([], instrumentID: "rb2510", period: .minute1, maxBars: 0)

        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.map(\.openTime) == [date(0), date(2)])
    }

    @Test("clear 单合约单周期")
    func clearSingle() async throws {
        let store = InMemoryKLineCacheStore()
        try await store.save([makeKLine(openTime: date(0))], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine("hc2510", openTime: date(0))], instrumentID: "hc2510", period: .minute1)

        try await store.clear(instrumentID: "rb2510", period: .minute1)

        let rb = try await store.load(instrumentID: "rb2510", period: .minute1)
        let hc = try await store.load(instrumentID: "hc2510", period: .minute1)
        #expect(rb.isEmpty)
        #expect(hc.count == 1)
    }

    @Test("clearAll 清全部")
    func clearAll() async throws {
        let store = InMemoryKLineCacheStore()
        try await store.save([makeKLine(openTime: date(0))], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine("hc2510", openTime: date(0))], instrumentID: "hc2510", period: .minute1)
        try await store.clearAll()
        #expect(try await store.load(instrumentID: "rb2510", period: .minute1).isEmpty)
        #expect(try await store.load(instrumentID: "hc2510", period: .minute1).isEmpty)
    }

    @Test("多合约多周期隔离")
    func multiKeyIsolation() async throws {
        let store = InMemoryKLineCacheStore()
        try await store.save([makeKLine(openTime: date(0), close: 100)], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine(openTime: date(0), close: 200)], instrumentID: "rb2510", period: .minute5)
        try await store.save([makeKLine("hc2510", openTime: date(0), close: 300)], instrumentID: "hc2510", period: .minute1)

        let rb1m = try await store.load(instrumentID: "rb2510", period: .minute1)
        let rb5m = try await store.load(instrumentID: "rb2510", period: .minute5)
        let hc1m = try await store.load(instrumentID: "hc2510", period: .minute1)
        #expect(rb1m[0].close == 100)
        #expect(rb5m[0].close == 200)
        #expect(hc1m[0].close == 300)
    }
}

// MARK: - 2. JSONFileKLineCacheStore

@Suite("JSONFileKLineCacheStore · 持久化")
struct JSONFileStoreTests {

    @Test("load 文件不存在返回 [] + 不抛错")
    func loadMissingFileReturnsEmpty() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)
        let result = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(result.isEmpty)
    }

    @Test("save → load 文件往返 + 自动创建目录")
    func saveLoadRoundTrip() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)

        let bars = [
            makeKLine(openTime: date(0), close: 100),
            makeKLine(openTime: date(1), close: 110),
        ]
        try await store.save(bars, instrumentID: "rb2510", period: .minute1)
        #expect(FileManager.default.fileExists(atPath: dir.path))

        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 2)
        #expect(loaded[0].close == 100)
        #expect(loaded[1].close == 110)
        #expect(loaded[0].openTime == date(0))
    }

    @Test("append 持久化合并 + 截尾")
    func appendPersistsMerge() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)

        try await store.save([makeKLine(openTime: date(0))], instrumentID: "rb2510", period: .minute1)
        try await store.append((1..<5).map { makeKLine(openTime: date($0)) },
                                instrumentID: "rb2510", period: .minute1, maxBars: 3)

        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.count == 3)
        #expect(loaded.map(\.openTime) == [date(2), date(3), date(4)])
    }

    @Test("clear 删除单文件 + clear 不存在不抛错")
    func clearRemovesFile() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)

        try await store.save([makeKLine(openTime: date(0))], instrumentID: "rb2510", period: .minute1)
        try await store.clear(instrumentID: "rb2510", period: .minute1)
        let loaded = try await store.load(instrumentID: "rb2510", period: .minute1)
        #expect(loaded.isEmpty)

        // 不存在再清不抛错
        try await store.clear(instrumentID: "not-exist", period: .minute1)
    }

    @Test("clearAll 删除整个目录 + 重复调用不抛错")
    func clearAllRemovesDirectory() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)
        try await store.save([makeKLine(openTime: date(0))], instrumentID: "rb2510", period: .minute1)
        try await store.clearAll()
        #expect(!FileManager.default.fileExists(atPath: dir.path))

        // 重复调用不抛错
        try await store.clearAll()
    }

    @Test("多合约多周期隔离（独立文件路径）")
    func multiKeyFileIsolation() async throws {
        let dir = tempCacheDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileKLineCacheStore(rootDirectory: dir)

        try await store.save([makeKLine(openTime: date(0), close: 100)], instrumentID: "rb2510", period: .minute1)
        try await store.save([makeKLine(openTime: date(0), close: 200)], instrumentID: "rb2510", period: .minute5)
        try await store.save([makeKLine("hc2510", openTime: date(0), close: 300)], instrumentID: "hc2510", period: .minute1)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files.count == 3)
        #expect(files.contains("rb2510_1m.json"))
        #expect(files.contains("rb2510_5m.json"))
        #expect(files.contains("hc2510_1m.json"))
    }

    @Test("sanitize 把非法字符替换为下划线（含点号合约 ID）")
    func sanitizeFileName() {
        #expect(JSONFileKLineCacheStore.sanitize("rb2510") == "rb2510")
        #expect(JSONFileKLineCacheStore.sanitize("IF.CFFEX.2510") == "IF_CFFEX_2510")
        #expect(JSONFileKLineCacheStore.sanitize("../etc") == "___etc")
        #expect(JSONFileKLineCacheStore.sanitize("a/b\\c") == "a_b_c")
        #expect(JSONFileKLineCacheStore.sanitize("with-dash") == "with-dash")  // 连字符保留
    }
}

// MARK: - 3. merged 静态合并语义（直接验算法）

@Suite("InMemoryKLineCacheStore.merged · 合并语义")
struct MergedSemanticTests {

    @Test("空 existing + 非空 incoming → 排序 + cap")
    func emptyExisting() {
        let result = InMemoryKLineCacheStore.merged(
            existing: [],
            incoming: [
                makeKLine(openTime: date(2)),
                makeKLine(openTime: date(0)),
                makeKLine(openTime: date(1)),
            ],
            maxBars: 0
        )
        #expect(result.map(\.openTime) == [date(0), date(1), date(2)])
    }

    @Test("incoming 同 openTime 覆盖 existing")
    func incomingOverwrites() {
        let result = InMemoryKLineCacheStore.merged(
            existing: [makeKLine(openTime: date(0), close: 100)],
            incoming: [makeKLine(openTime: date(0), close: 999)],
            maxBars: 0
        )
        #expect(result.count == 1)
        #expect(result[0].close == 999)
    }

    @Test("cap 0 = 不限 / cap N 保留最近 N")
    func capBehavior() {
        let bars = (0..<5).map { makeKLine(openTime: date($0)) }
        let unlimited = InMemoryKLineCacheStore.merged(existing: [], incoming: bars, maxBars: 0)
        let capped = InMemoryKLineCacheStore.merged(existing: [], incoming: bars, maxBars: 2)
        #expect(unlimited.count == 5)
        #expect(capped.map(\.openTime) == [date(3), date(4)])
    }
}
