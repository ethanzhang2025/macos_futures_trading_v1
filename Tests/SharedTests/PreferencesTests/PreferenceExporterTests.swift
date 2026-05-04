// v15.18 · PreferenceExporter 单测

import Testing
import Foundation
@testable import Shared

@Suite("PreferenceExporter · 偏好导出 / 导入")
struct PreferenceExporterTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "test.pref.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return defaults
    }

    @Test("export · 仅含白名单前缀的 key")
    func exportFiltersByPrefix() throws {
        let defaults = makeDefaults()
        defaults.set("RB0", forKey: "settings.defaultInstrumentID")
        defaults.set(true, forKey: "featureFlag.alert.center")
        defaults.set("not-included", forKey: "secret.token")    // 非白名单
        defaults.set("device-uuid", forKey: "com.futures-terminal.analytics.deviceID")  // 非白名单

        let data = PreferenceExporter.export(defaults: defaults)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["settings.defaultInstrumentID"] as? String == "RB0")
        #expect(dict["featureFlag.alert.center"] as? Bool == true)
        #expect(dict["secret.token"] == nil)
        #expect(dict["com.futures-terminal.analytics.deviceID"] == nil)
    }

    @Test("import · 仅写入白名单前缀 key · 返回 written 数")
    func importWritesWhitelisted() throws {
        let defaults = makeDefaults()
        let json: [String: Any] = [
            "settings.defaultInstrumentID": "AU0",
            "featureFlag.alert.sound": false,
            "evil.injection": "should not write"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let written = try PreferenceExporter.import(from: data, defaults: defaults)
        #expect(written == 2)
        #expect(defaults.string(forKey: "settings.defaultInstrumentID") == "AU0")
        #expect(defaults.bool(forKey: "featureFlag.alert.sound") == false)
        #expect(defaults.string(forKey: "evil.injection") == nil)
    }

    @Test("export → import roundtrip · 偏好完整保留")
    func roundtripPreservesAll() throws {
        let src = makeDefaults()
        src.set("CU0", forKey: "settings.defaultInstrumentID")
        src.set(false, forKey: "featureFlag.analytics.enabled")
        src.set(["a", "b"], forKey: "subIndicators.v1")

        let exported = PreferenceExporter.export(defaults: src)

        let dst = makeDefaults()
        let written = try PreferenceExporter.import(from: exported, defaults: dst)
        #expect(written == 3)
        #expect(dst.string(forKey: "settings.defaultInstrumentID") == "CU0")
        #expect(dst.bool(forKey: "featureFlag.analytics.enabled") == false)
        #expect(dst.array(forKey: "subIndicators.v1") as? [String] == ["a", "b"])
    }

    @Test("import 非法 JSON · 抛错")
    func invalidJSONThrows() {
        let defaults = makeDefaults()
        let data = "not json".data(using: .utf8)!
        do {
            _ = try PreferenceExporter.import(from: data, defaults: defaults)
            Issue.record("应抛错")
        } catch {
            // 期望抛
        }
    }

    @Test("exportedPrefixes 涵盖关键前缀（防漏配置）")
    func exportedPrefixesCoverKeyAreas() {
        let prefixes = PreferenceExporter.exportedPrefixes
        #expect(prefixes.contains("settings."))
        #expect(prefixes.contains("featureFlag."))
        #expect(prefixes.contains("indicators.params.v1"))
        #expect(prefixes.contains("chartTheme.v1"))
        #expect(prefixes.contains("viewState.v1."))   // v15.20 batch60
    }

    @Test("v15.20 batch60 · viewState.v1 系列 key 进出导出")
    func viewStateRoundTrip() throws {
        let suite = "PreferenceExporterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("month:2026-05", forKey: "viewState.v1.review.dateFilter")
        defaults.set("changePct", forKey: "viewState.v1.watchlist.sortFieldRaw")
        defaults.set(true, forKey: "viewState.v1.watchlist.sortAscending")

        let data = PreferenceExporter.export(defaults: defaults)
        defaults.removePersistentDomain(forName: suite)
        #expect(defaults.string(forKey: "viewState.v1.review.dateFilter") == nil)

        try PreferenceExporter.import(from: data, defaults: defaults)
        #expect(defaults.string(forKey: "viewState.v1.review.dateFilter") == "month:2026-05")
        #expect(defaults.string(forKey: "viewState.v1.watchlist.sortFieldRaw") == "changePct")
        #expect(defaults.bool(forKey: "viewState.v1.watchlist.sortAscending") == true)
    }
}
