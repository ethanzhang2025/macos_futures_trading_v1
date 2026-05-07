// SyncableSettings 测试 · WP-60 batch005

import Testing
import Foundation
@testable import Shared
import SyncCore

@Suite("SyncableSettings · 行为")
struct SyncableSettingsTests {

    @Test("set 已知 key · 成功 + version+1")
    func setKnownKey() {
        var s = SyncableSettings()
        let v0 = s.version
        let ok = s.set("theme.preferred", .string("dark"))
        #expect(ok)
        #expect(s.version == v0 + 1)
        #expect(s.get("theme.preferred")?.asString == "dark")
    }

    @Test("set 未知 key · 拒绝")
    func setUnknownKey() {
        var s = SyncableSettings()
        let ok = s.set("not.in.whitelist", .bool(true))
        #expect(!ok)
        #expect(s.values.isEmpty)
    }

    @Test("set 同值不重复 bump version")
    func setSameValueNoBump() {
        var s = SyncableSettings()
        _ = s.set("theme.preferred", .string("dark"))
        let v = s.version
        _ = s.set("theme.preferred", .string("dark"))
        #expect(s.version == v)
    }

    @Test("remove 已存 key")
    func removeKey() {
        var s = SyncableSettings()
        _ = s.set("theme.preferred", .string("dark"))
        let ok = s.remove("theme.preferred")
        #expect(ok)
        #expect(s.get("theme.preferred") == nil)
    }

    @Test("remove 不存在 key · false")
    func removeMissing() {
        var s = SyncableSettings()
        let ok = s.remove("theme.preferred")
        #expect(!ok)
    }

    @Test("snapshot from UserDefaults · 仅采集白名单 key")
    func snapshotFromDefaults() {
        let defaults = UserDefaults(suiteName: "test.synccore.settings")!
        defaults.removePersistentDomain(forName: "test.synccore.settings")

        defaults.set("dark", forKey: "theme.preferred")
        defaults.set(42, forKey: "subChartHeight.v1")
        defaults.set("ignored", forKey: "not.in.whitelist")  // 不应进 snapshot

        let s = SyncableSettings.snapshot(from: defaults)
        #expect(s.get("theme.preferred")?.asString == "dark")
        #expect(s.get("subChartHeight.v1")?.asInt == 42)
        #expect(s.get("not.in.whitelist") == nil)

        defaults.removePersistentDomain(forName: "test.synccore.settings")
    }

    @Test("syncRecordType = settings · id 是 singletonID")
    func syncRecordTypeAndID() {
        #expect(SyncableSettings.syncRecordType == "settings")
        let s = SyncableSettings()
        #expect(s.id == SyncableSettings.singletonID)
    }

    @Test("round-trip 还原")
    func roundTrip() throws {
        var original = SyncableSettings()
        _ = original.set("theme.preferred", .string("dark"))
        _ = original.set("subChartHeight.v1", .int(120))
        _ = original.set("review.dateFilter", .data(Data([0x01, 0x02, 0x03])))

        let record = try original.toSyncRecord()
        #expect(record.id == SyncableSettings.singletonID)
        #expect(record.recordType == "settings")

        let restored = try SyncableSettings.decode(from: record)
        #expect(restored.get("theme.preferred")?.asString == "dark")
        #expect(restored.get("subChartHeight.v1")?.asInt == 120)
        #expect(restored.get("review.dateFilter")?.asData == Data([0x01, 0x02, 0x03]))
        #expect(restored.version == original.version)
    }

    @Test("旧 JSON 缺字段 · 回退默认")
    func legacyJSON() throws {
        let json = """
        { "values": {} }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let s = try decoder.decode(SyncableSettings.self, from: Data(json.utf8))
        #expect(s.version == 1)
        #expect(s.deletedAt == nil)
    }

    @Test("SettingsValue 各类型解构 helper")
    func settingsValueAccessors() {
        #expect(SettingsValue.bool(true).asBool == true)
        #expect(SettingsValue.int(42).asInt == 42)
        #expect(SettingsValue.double(3.14).asDouble == 3.14)
        #expect(SettingsValue.string("x").asString == "x")
        #expect(SettingsValue.data(Data()).asData == Data())
        #expect(SettingsValue.bool(true).asInt == nil)
    }
}
