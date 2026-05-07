// AlertSyncAdapter 测试 · WP-60 batch007

import Testing
import Foundation
import Shared
@testable import AlertCore
import SyncCore

@Suite("AlertSyncAdapter · 双向转换")
struct AlertSyncAdapterTests {

    private let now = Date(timeIntervalSince1970: 1_730_000_000)

    private func sample(version: Int = 1, deletedAt: Date? = nil) -> Alert {
        Alert(
            id: UUID(),
            name: "RB 突破 3500",
            instrumentID: "rb0",
            condition: .priceAbove(3500),
            status: .active,
            channels: [.inApp, .systemNotice],
            cooldownSeconds: 60,
            createdAt: now,
            lastTriggeredAt: nil,
            updatedAt: now.addingTimeInterval(60),
            version: version,
            deletedAt: deletedAt
        )
    }

    @Test("syncRecordType = alert")
    func recordType() {
        #expect(Alert.syncRecordType == "alert")
    }

    @Test("toSyncRecord · 字段映射")
    func toSyncRecordMapping() throws {
        let a = sample(version: 5)
        let record = try a.toSyncRecord()
        #expect(record.recordType == "alert")
        #expect(record.id == a.id)
        #expect(record.lastModified == a.updatedAt)
        #expect(record.version == 5)
        #expect(record.deletedAt == nil)
    }

    @Test("round-trip 还原 · 含 condition / channels")
    func roundTrip() throws {
        let original = sample(version: 7)
        let record = try original.toSyncRecord()
        let restored = try Alert.decode(from: record)

        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.instrumentID == original.instrumentID)
        #expect(restored.condition == original.condition)
        #expect(restored.channels == original.channels)
        #expect(restored.cooldownSeconds == original.cooldownSeconds)
        #expect(restored.version == original.version)
    }

    @Test("tombstone 保留 payload + canTrigger 返回 false")
    func tombstoneCanTrigger() throws {
        let a = sample(version: 3, deletedAt: now.addingTimeInterval(120))
        let record = try a.toSyncRecord()
        #expect(record.isDeleted)
        #expect(a.canTrigger(at: now) == false)
    }

    @Test("markDeleted · 设 deletedAt + updatedAt + version+1")
    func markDeleted() {
        var a = sample(version: 2)
        let now = Date()
        a.markDeleted(now: now)
        #expect(a.deletedAt == now)
        #expect(a.updatedAt == now)
        #expect(a.version == 3)
    }

    @Test("decode · metadata 以 SyncRecord 为准")
    func decodeMetadataPriority() throws {
        let a = sample()
        var record = try a.toSyncRecord()
        record = SyncRecord(
            recordType: record.recordType,
            id: record.id,
            lastModified: now.addingTimeInterval(999),
            version: 99,
            deletedAt: now.addingTimeInterval(999),
            payload: record.payload
        )
        let restored = try Alert.decode(from: record)
        #expect(restored.version == 99)
        #expect(restored.deletedAt == now.addingTimeInterval(999))
    }
}

@Suite("Alert · Codable 向后兼容")
struct AlertCodableCompatTests {

    @Test("旧 JSON 缺 updatedAt/version/deletedAt · 回退")
    func legacyJSON() throws {
        // 用真实 encode 产出"旧格式"再剔除新字段，确保 condition 编码与运行时一致
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let alert = Alert(
            id: UUID(),
            name: "old",
            instrumentID: "rb0",
            condition: .priceAbove(3500),
            status: .active,
            channels: [.inApp],
            cooldownSeconds: 60,
            createdAt: createdAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let fullData = try encoder.encode(alert)
        var dict = try #require(try JSONSerialization.jsonObject(with: fullData) as? [String: Any])
        dict.removeValue(forKey: "updatedAt")
        dict.removeValue(forKey: "version")
        dict.removeValue(forKey: "deletedAt")
        let trimmed = try JSONSerialization.data(withJSONObject: dict)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let a = try decoder.decode(Alert.self, from: trimmed)
        #expect(a.version == 1)
        #expect(a.deletedAt == nil)
        #expect(a.updatedAt == a.createdAt)
    }
}
