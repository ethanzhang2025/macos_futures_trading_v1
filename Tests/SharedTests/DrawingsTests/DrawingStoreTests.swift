// WP-42 v13.2 · DrawingStore 协议合约 + InMemory + SQLite 双实现等价测试

import Testing
import Foundation
@testable import Shared

private func makeSampleDrawings() -> [Drawing] {
    [
        Drawing.trendLine(
            from: DrawingPoint(barIndex: 100, price: 3200),
            to: DrawingPoint(barIndex: 150, price: 3300)
        ),
        Drawing.horizontalLine(price: 3215, barIndex: 0),
        Drawing.rectangle(
            from: DrawingPoint(barIndex: 50, price: 3100),
            to: DrawingPoint(barIndex: 80, price: 3250)
        ),
        Drawing.fibonacci(
            from: DrawingPoint(barIndex: 200, price: 3500),
            to: DrawingPoint(barIndex: 250, price: 3000)
        ),
        Drawing.text(
            at: DrawingPoint(barIndex: 120, price: 3260),
            content: "支撑位"
        )
    ]
}

@Suite("InMemoryDrawingStore · 协议合约")
struct InMemoryDrawingStoreTests {

    @Test("空 store load → 空数组")
    func emptyLoad() async throws {
        let store = InMemoryDrawingStore()
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
    }

    @Test("save 后 load 完整往返（5 种画线类型）")
    func saveLoadRoundTrip() async throws {
        let store = InMemoryDrawingStore()
        let drawings = makeSampleDrawings()
        try await store.save(drawings, instrumentID: "RB0", period: .minute15)
        let loaded = try await store.load(instrumentID: "RB0", period: .minute15)
        #expect(loaded == drawings)
    }

    @Test("不同 (instrumentID, period) 组合独立隔离")
    func keyIsolation() async throws {
        let store = InMemoryDrawingStore()
        let rb15 = makeSampleDrawings()
        let if60 = [Drawing.horizontalLine(price: 4500)]
        try await store.save(rb15, instrumentID: "RB0", period: .minute15)
        try await store.save(if60, instrumentID: "IF0", period: .hour1)

        #expect(try await store.load(instrumentID: "RB0", period: .minute15) == rb15)
        #expect(try await store.load(instrumentID: "IF0", period: .hour1) == if60)
        // RB0 60min 没保存过 → 空
        #expect(try await store.load(instrumentID: "RB0", period: .hour1).isEmpty)
    }

    @Test("clear 仅清指定组合 · 不影响其他")
    func clearIsolated() async throws {
        let store = InMemoryDrawingStore()
        try await store.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        try await store.save([Drawing.horizontalLine(price: 4500)], instrumentID: "IF0", period: .hour1)
        try await store.clear(instrumentID: "RB0", period: .minute15)
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
        #expect(try await store.load(instrumentID: "IF0", period: .hour1).count == 1)
    }

    @Test("clearAll 清空全部")
    func clearAll() async throws {
        let store = InMemoryDrawingStore()
        try await store.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        try await store.save([Drawing.horizontalLine(price: 4500)], instrumentID: "IF0", period: .hour1)
        try await store.clearAll()
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
        #expect(try await store.load(instrumentID: "IF0", period: .hour1).isEmpty)
    }
}

@Suite("SQLiteDrawingStore · 协议合约")
struct SQLiteDrawingStoreTests {

    private static func tempPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DrawingStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("drawings.sqlite").path
    }

    @Test("空 store load → 空数组")
    func emptyLoad() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
        await store.close()
    }

    @Test("save 后 load 完整往返（5 种画线类型 · JSON 序列化保真）")
    func saveLoadRoundTrip() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        let drawings = makeSampleDrawings()
        try await store.save(drawings, instrumentID: "RB0", period: .minute15)
        let loaded = try await store.load(instrumentID: "RB0", period: .minute15)
        #expect(loaded == drawings)
        await store.close()
    }

    @Test("不同 (instrumentID, period) 组合独立隔离")
    func keyIsolation() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        try await store.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        try await store.save([Drawing.horizontalLine(price: 4500)], instrumentID: "IF0", period: .hour1)
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).count == 5)
        #expect(try await store.load(instrumentID: "IF0", period: .hour1).count == 1)
        #expect(try await store.load(instrumentID: "RB0", period: .hour1).isEmpty)
        await store.close()
    }

    @Test("二次 save 同 key UPSERT 覆盖")
    func upsertOverwrites() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        try await store.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        let single = [Drawing.horizontalLine(price: 9999)]
        try await store.save(single, instrumentID: "RB0", period: .minute15)
        let loaded = try await store.load(instrumentID: "RB0", period: .minute15)
        #expect(loaded.count == 1)
        #expect(loaded.first?.startPoint.price == 9999)
        await store.close()
    }

    @Test("重启重连后数据持久（path 持久 · close + 重开）")
    func restartPersistence() async throws {
        let path = Self.tempPath()
        let store1 = try SQLiteDrawingStore(path: path)
        try await store1.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        await store1.close()

        let store2 = try SQLiteDrawingStore(path: path)
        let loaded = try await store2.load(instrumentID: "RB0", period: .minute15)
        #expect(loaded.count == 5)
        await store2.close()
    }

    @Test("clear 仅清指定组合")
    func clearIsolated() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        try await store.save(makeSampleDrawings(), instrumentID: "RB0", period: .minute15)
        try await store.save([Drawing.horizontalLine(price: 4500)], instrumentID: "IF0", period: .hour1)
        try await store.clear(instrumentID: "RB0", period: .minute15)
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
        #expect(try await store.load(instrumentID: "IF0", period: .hour1).count == 1)
        await store.close()
    }

    @Test("空数组 save → load 也是空数组")
    func emptyArrayRoundTrip() async throws {
        let store = try SQLiteDrawingStore(path: Self.tempPath())
        try await store.save([], instrumentID: "RB0", period: .minute15)
        #expect(try await store.load(instrumentID: "RB0", period: .minute15).isEmpty)
        await store.close()
    }
}
