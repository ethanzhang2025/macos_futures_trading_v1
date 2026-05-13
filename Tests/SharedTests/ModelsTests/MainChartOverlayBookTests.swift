// v17.139 · MainChartOverlayBook 数据契约 + Codable + Store 测试

import Testing
import Foundation
@testable import Shared

@Suite("MainChartOverlayBook · 主图叠加偏好（VWAP / Pivot / SuperTrend）")
struct MainChartOverlayBookTests {

    @Test("default · 全关 · superTrend 默认 10/3")
    func defaults() {
        let d = MainChartOverlayBook.default
        #expect(d.enabled.isEmpty)
        #expect(!d.anyEnabled)
        #expect(d.superTrendPeriod == 10)
        #expect(d.superTrendMultiplier == Decimal(3))
    }

    @Test("MainChartOverlayKind allCases 3 类完整 · 顺序固定 vwap/pivot/superTrend")
    func allCases() {
        let cases = MainChartOverlayKind.allCases
        #expect(cases.count == 3)
        #expect(cases == [.vwap, .pivot, .superTrend])
    }

    @Test("displayName / icon 三类均非空 · 中文化 trader 友好")
    func displayMetadata() {
        for k in MainChartOverlayKind.allCases {
            #expect(!k.displayName.isEmpty)
            #expect(!k.icon.isEmpty)
        }
        #expect(MainChartOverlayKind.vwap.displayName.contains("VWAP"))
        #expect(MainChartOverlayKind.pivot.displayName.contains("Pivot"))
        #expect(MainChartOverlayKind.superTrend.displayName.contains("SuperTrend"))
    }

    @Test("setEnabled 切换 · isEnabled 反映状态 · anyEnabled 反映非空")
    func setEnabledToggle() {
        var book = MainChartOverlayBook.default
        #expect(!book.isEnabled(.vwap))
        book.setEnabled(.vwap, true)
        #expect(book.isEnabled(.vwap))
        #expect(book.anyEnabled)
        #expect(book.enabled == [.vwap])
        book.setEnabled(.pivot, true)
        #expect(book.enabled == [.vwap, .pivot])
        book.setEnabled(.vwap, false)
        #expect(!book.isEnabled(.vwap))
        #expect(book.enabled == [.pivot])
        book.setEnabled(.pivot, false)
        #expect(!book.anyEnabled)
    }

    @Test("Codable 往返 · 全关 default")
    func codableRoundTripDefault() throws {
        let book = MainChartOverlayBook.default
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded == book)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
    }

    @Test("Codable 往返 · 三全开 + 自定义 SuperTrend 参数 14/2.5")
    func codableRoundTripCustom() throws {
        let book = MainChartOverlayBook(
            enabled: [.vwap, .pivot, .superTrend],
            superTrendPeriod: 14,
            superTrendMultiplier: Decimal(string: "2.5")!
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled == [.vwap, .pivot, .superTrend])
        #expect(decoded.superTrendPeriod == 14)
        #expect(decoded.superTrendMultiplier == Decimal(string: "2.5"))
    }

    @Test("旧 JSON 兼容 · 缺字段 fallback 默认（decodeIfPresent 守）")
    func backwardCompatible() throws {
        // 模拟极简旧 JSON 仅有 enabled · 缺 superTrend 参数 → fallback 默认
        let json = "{\"enabled\":[]}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled.isEmpty)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
    }

    @Test("旧 JSON 完全空 · 全字段 fallback 默认")
    func emptyJSONFallback() throws {
        let data = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MainChartOverlayBook.self, from: data)
        #expect(decoded.enabled.isEmpty)
        #expect(decoded.superTrendPeriod == 10)
        #expect(decoded.superTrendMultiplier == Decimal(3))
    }

    @Test("Store load/save 隔离 UserDefaults")
    func storeRoundTrip() {
        let suiteName = "MainChartOverlayBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // 不存在 → nil
        #expect(MainChartOverlayStore.load(defaults: defaults) == nil)
        // 写入 → 读回
        let book = MainChartOverlayBook(
            enabled: [.vwap, .superTrend],
            superTrendPeriod: 7,
            superTrendMultiplier: Decimal(2)
        )
        MainChartOverlayStore.save(book, defaults: defaults)
        let loaded = MainChartOverlayStore.load(defaults: defaults)
        #expect(loaded != nil)
        #expect(loaded?.enabled == [.vwap, .superTrend])
        #expect(loaded?.superTrendPeriod == 7)
        #expect(loaded?.superTrendMultiplier == Decimal(2))
    }

    @Test("Store load 损坏数据 · 返回 nil 不崩")
    func storeCorruptedData() {
        let suiteName = "MainChartOverlayBookTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data([0xFF, 0xEE, 0xDD]), forKey: MainChartOverlayStore.key)
        #expect(MainChartOverlayStore.load(defaults: defaults) == nil)
    }

    @Test("Equatable 正常工作 · 两本字段全等才相等")
    func equatable() {
        let a = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let b = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let c = MainChartOverlayBook(enabled: [.pivot], superTrendPeriod: 10, superTrendMultiplier: Decimal(3))
        let d = MainChartOverlayBook(enabled: [.vwap], superTrendPeriod: 14, superTrendMultiplier: Decimal(3))
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}
