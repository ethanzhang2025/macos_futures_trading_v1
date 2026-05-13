// v17.160 · IndicatorFavorites 数据契约 + Codable + Store 测试

import Testing
import Foundation
@testable import Shared

@Suite("IndicatorFavorites · 副图指标收藏夹（v17.160）")
struct IndicatorFavoritesTests {

    @Test("default · 空集合")
    func defaults() {
        let f = IndicatorFavorites.default
        #expect(f.rawValues.isEmpty)
        #expect(!f.contains("macd"))
    }

    @Test("toggle · 不在则加入 / 在则移除 · 加入顺序保留")
    func toggleAddRemove() {
        var f = IndicatorFavorites()
        f.toggle("macd")
        #expect(f.rawValues == ["macd"])
        #expect(f.contains("macd"))
        f.toggle("kdj")
        #expect(f.rawValues == ["macd", "kdj"])
        f.toggle("macd")   // 移除
        #expect(f.rawValues == ["kdj"])
        #expect(!f.contains("macd"))
    }

    @Test("add 已存在不重复 · remove 不存在静默")
    func addRemoveIdempotent() {
        var f = IndicatorFavorites()
        f.add("rsi")
        f.add("rsi")   // 不重复
        #expect(f.rawValues == ["rsi"])
        f.remove("kdj")  // 不存在 · 静默
        #expect(f.rawValues == ["rsi"])
        f.remove("rsi")
        #expect(f.rawValues.isEmpty)
    }

    @Test("clear 清空全部")
    func clearAll() {
        var f = IndicatorFavorites(rawValues: ["macd", "kdj", "rsi"])
        f.clear()
        #expect(f.rawValues.isEmpty)
    }

    @Test("Codable 往返 · 空 + 多项")
    func codableRoundTrip() throws {
        // 空
        let empty = IndicatorFavorites()
        let emptyData = try JSONEncoder().encode(empty)
        let emptyDecoded = try JSONDecoder().decode(IndicatorFavorites.self, from: emptyData)
        #expect(emptyDecoded == empty)

        // 多项 + 顺序保留
        let multi = IndicatorFavorites(rawValues: ["macd", "kdj", "rsi", "obv"])
        let multiData = try JSONEncoder().encode(multi)
        let multiDecoded = try JSONDecoder().decode(IndicatorFavorites.self, from: multiData)
        #expect(multiDecoded.rawValues == ["macd", "kdj", "rsi", "obv"])
    }

    @Test("Store load/save 隔离 UserDefaults")
    func storeRoundTrip() {
        let suiteName = "IndicatorFavoritesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // 不存在 → nil
        #expect(IndicatorFavoritesStore.load(defaults: defaults) == nil)
        // 写入 → 读回
        let f = IndicatorFavorites(rawValues: ["macd", "kdj"])
        IndicatorFavoritesStore.save(f, defaults: defaults)
        let loaded = IndicatorFavoritesStore.load(defaults: defaults)
        #expect(loaded?.rawValues == ["macd", "kdj"])
    }

    @Test("Store load 损坏数据 · 返回 nil 不崩")
    func storeCorruptedData() {
        let suiteName = "IndicatorFavoritesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data([0xFF, 0xEE, 0xDD]), forKey: IndicatorFavoritesStore.key)
        #expect(IndicatorFavoritesStore.load(defaults: defaults) == nil)
    }

    @Test("Equatable")
    func equatable() {
        let a = IndicatorFavorites(rawValues: ["macd", "kdj"])
        let b = IndicatorFavorites(rawValues: ["macd", "kdj"])
        let c = IndicatorFavorites(rawValues: ["kdj", "macd"])   // 顺序不同
        #expect(a == b)
        #expect(a != c)
    }
}
