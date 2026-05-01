// WP-19a-4 · SQLiteAlertHistoryStore 协议合约测试

import Testing
import Foundation
import Shared
@testable import AlertCore

private func makeStore() throws -> SQLiteAlertHistoryStore {
    try SQLiteAlertHistoryStore(path: ":memory:")
}

private func makeEntry(
    alertID: UUID = UUID(),
    alertName: String = "测试预警",
    instrumentID: String = "rb2510",
    condition: AlertCondition = .priceAbove(3500),
    triggeredAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    triggerPrice: Decimal = 3520
) -> AlertHistoryEntry {
    AlertHistoryEntry(
        alertID: alertID, alertName: alertName, instrumentID: instrumentID,
        conditionSnapshot: condition,
        triggeredAt: triggeredAt, triggerPrice: triggerPrice,
        message: "上穿 3500"
    )
}

@Suite("SQLiteAlertHistoryStore · 协议合约")
struct SQLiteAlertHistoryStoreTests {

    @Test("空 store allHistory → 空")
    func emptyHistory() async throws {
        let store = try makeStore()
        #expect(try await store.allHistory().isEmpty)
    }

    @Test("append + history(forAlertID:) 按 triggeredAt 降序")
    func historyByAlertID() async throws {
        let store = try makeStore()
        let aid = UUID()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.append(makeEntry(alertID: aid, triggeredAt: t))
        try await store.append(makeEntry(alertID: aid, triggeredAt: t.addingTimeInterval(60)))
        try await store.append(makeEntry(alertID: UUID(), triggeredAt: t.addingTimeInterval(30)))  // 不同 alert

        let h = try await store.history(forAlertID: aid)
        #expect(h.count == 2)
        #expect(h[0].triggeredAt == t.addingTimeInterval(60))  // 最近在前
        #expect(h[1].triggeredAt == t)
    }

    @Test("allHistory 按 triggeredAt 降序")
    func allHistorySorted() async throws {
        let store = try makeStore()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.append(makeEntry(triggeredAt: t))
        try await store.append(makeEntry(triggeredAt: t.addingTimeInterval(120)))
        try await store.append(makeEntry(triggeredAt: t.addingTimeInterval(60)))

        let all = try await store.allHistory()
        #expect(all.count == 3)
        #expect(all[0].triggeredAt == t.addingTimeInterval(120))
        #expect(all[2].triggeredAt == t)
    }

    @Test("AlertCondition JSON 往返（含 v15.12 openInterestSpike）")
    func conditionRoundtrip() async throws {
        let store = try makeStore()
        let drawingID = UUID()
        let conditions: [AlertCondition] = [
            .priceAbove(3500),
            .priceCrossBelow(3200.5),
            .volumeSpike(multiple: 3, windowBars: 20),
            .openInterestSpike(multiple: 2, windowBars: 20),  // v15.12 WP-52 v3
            .priceMoveSpike(percentThreshold: 1.5, windowSeconds: 300),
            .horizontalLineTouched(drawingID: drawingID, price: 3500)
        ]
        for c in conditions {
            try await store.append(makeEntry(condition: c))
        }
        let all = try await store.allHistory()
        #expect(all.count == 6)
        let storedConditions = all.map { $0.conditionSnapshot }
        // 6 种条件都序列化反序列化成功 → 都在结果集
        for c in conditions {
            #expect(storedConditions.contains(c))
        }
    }

    @Test("clear(alertID:) 仅删指定 alert 的历史")
    func clearByAlert() async throws {
        let store = try makeStore()
        let aid = UUID()
        try await store.append(makeEntry(alertID: aid))
        try await store.append(makeEntry(alertID: aid))
        try await store.append(makeEntry(alertID: UUID()))

        try await store.clear(alertID: aid)
        #expect(try await store.history(forAlertID: aid).isEmpty)
        #expect(try await store.allHistory().count == 1)
    }

    @Test("clearAll 全删")
    func clearAll() async throws {
        let store = try makeStore()
        try await store.append(makeEntry())
        try await store.append(makeEntry())
        try await store.clearAll()
        #expect(try await store.allHistory().isEmpty)
    }

    @Test("triggerPrice Decimal 精度保留")
    func decimalPrecision() async throws {
        let store = try makeStore()
        try await store.append(makeEntry(triggerPrice: 3520.1234))
        let all = try await store.allHistory()
        #expect(all[0].triggerPrice == 3520.1234)
    }

    @Test("文件持久化 · 重启数据完整")
    func filePersistence() async throws {
        let path = NSTemporaryDirectory() + "wp19a4_\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store1 = try SQLiteAlertHistoryStore(path: path)
        try await store1.append(makeEntry())
        try await store1.append(makeEntry())
        await store1.close()

        let store2 = try SQLiteAlertHistoryStore(path: path)
        #expect(try await store2.allHistory().count == 2)
        await store2.close()
    }

    // MARK: - 时间区间查询（v5.0+ · UI 历史面板）

    @Test("history(from:to:) 区间命中 · 按 triggeredAt 降序")
    func rangeQueryDescending() async throws {
        let store = try makeStore()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_001_000)
        let t2 = Date(timeIntervalSince1970: 1_700_002_000)
        let t3 = Date(timeIntervalSince1970: 1_700_003_000)
        try await store.append(makeEntry(triggeredAt: t0))
        try await store.append(makeEntry(triggeredAt: t1))
        try await store.append(makeEntry(triggeredAt: t2))
        try await store.append(makeEntry(triggeredAt: t3))

        let result = try await store.history(from: t1, to: t2)
        #expect(result.count == 2)
        #expect(result[0].triggeredAt == t2)  // 降序
        #expect(result[1].triggeredAt == t1)
    }

    @Test("history(from:to:) 闭区间边界 · from = to 命中精确时刻")
    func rangeQueryClosedBoundary() async throws {
        let store = try makeStore()
        let exact = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.append(makeEntry(triggeredAt: exact))
        try await store.append(makeEntry(triggeredAt: exact.addingTimeInterval(1)))

        let result = try await store.history(from: exact, to: exact)
        #expect(result.count == 1)
        #expect(result[0].triggeredAt == exact)
    }

    @Test("history(from:to:) from > to → 空数组（不抛错）")
    func rangeQueryInvertedReturnsEmpty() async throws {
        let store = try makeStore()
        try await store.append(makeEntry())
        let now = Date()
        let result = try await store.history(from: now, to: now.addingTimeInterval(-3600))
        #expect(result.isEmpty)
    }

    @Test("history(from:to:) 空 store → 空数组")
    func rangeQueryOnEmptyStore() async throws {
        let store = try makeStore()
        let result = try await store.history(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 9_999_999_999)
        )
        #expect(result.isEmpty)
    }
}
