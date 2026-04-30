// MainApp v15.2 · IndicatorParamsBook 数据契约 + Codable 测试

import Testing
import Foundation
@testable import Shared

@Suite("IndicatorParamsBook · 数据契约 + Codable")
struct IndicatorParamsBookTests {

    @Test("default 出厂值 = 5/20/60 + BOLL 20/2 + MACD 12/26/9 + KDJ 9/3/3 + RSI 14")
    func defaults() {
        let d = IndicatorParamsBook.default
        #expect(d.mainMAPeriods == [5, 20, 60])
        #expect(d.mainBOLLParams == [20, 2])
        #expect(d.macdParams == [12, 26, 9])
        #expect(d.kdjParams == [9, 3, 3])
        #expect(d.rsiPeriod == 14)
    }

    @Test("Codable JSON 往返")
    func codableRoundTrip() throws {
        let book = IndicatorParamsBook(
            mainMAPeriods: [7, 33, 99],
            mainBOLLParams: [25, 3],
            macdParams: [10, 22, 8],
            kdjParams: [14, 5, 5],
            rsiPeriod: 9
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(IndicatorParamsBook.self, from: data)
        #expect(decoded == book)
    }

    @Test("Decimal 转换 helper · MA 三条独立 [Decimal] 数组")
    func mainMAPeriodsDecimal() {
        let d = IndicatorParamsBook.default
        let decimal = d.mainMAPeriodsDecimal
        #expect(decimal.count == 3)
        #expect(decimal[0] == [Decimal(5)])
        #expect(decimal[1] == [Decimal(20)])
        #expect(decimal[2] == [Decimal(60)])
    }

    @Test("Decimal 转换 helper · MACD/KDJ/RSI 平铺 [Decimal]")
    func compositeDecimals() {
        let d = IndicatorParamsBook.default
        #expect(d.mainBOLLParamsDecimal == [Decimal(20), Decimal(2)])
        #expect(d.macdParamsDecimal == [Decimal(12), Decimal(26), Decimal(9)])
        #expect(d.kdjParamsDecimal == [Decimal(9), Decimal(3), Decimal(3)])
        #expect(d.rsiParamsDecimal == [Decimal(14)])
    }

    @Test("自定义参数后 Decimal 反映新值")
    func customParamsReflectInDecimal() {
        let book = IndicatorParamsBook(
            mainMAPeriods: [7, 33, 99],
            mainBOLLParams: [25, 3],
            macdParams: [10, 22, 8],
            kdjParams: [14, 5, 5],
            rsiPeriod: 9
        )
        #expect(book.mainMAPeriodsDecimal == [[Decimal(7)], [Decimal(33)], [Decimal(99)]])
        #expect(book.macdParamsDecimal == [Decimal(10), Decimal(22), Decimal(8)])
        #expect(book.rsiParamsDecimal == [Decimal(9)])
    }

    @Test("Equatable")
    func equatable() {
        let a = IndicatorParamsBook.default
        let b = IndicatorParamsBook.default
        #expect(a == b)
        var c = a
        c.rsiPeriod = 21
        #expect(a != c)
    }
}

@Suite("IndicatorParamsStore · UserDefaults round-trip")
struct IndicatorParamsStoreTests {

    /// 每个测试用独立 suite 避免污染 .standard · 与 Wp23Tests UserDefaultsStoreTests 同模式
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "IndicatorParamsTest-\(UUID().uuidString)")!
    }

    @Test("save then load · 反序列化等价")
    func saveLoadRoundTrip() {
        let defaults = makeDefaults()
        let book = IndicatorParamsBook(
            mainMAPeriods: [3, 8, 21],
            mainBOLLParams: [14, 2],
            macdParams: [5, 13, 5],
            kdjParams: [7, 3, 3],
            rsiPeriod: 6
        )
        IndicatorParamsStore.save(book, defaults: defaults)
        let loaded = IndicatorParamsStore.load(defaults: defaults)
        #expect(loaded == book)
    }

    @Test("load 空时返回 nil")
    func loadEmptyReturnsNil() {
        let defaults = makeDefaults()
        #expect(IndicatorParamsStore.load(defaults: defaults) == nil)
    }
}

@Suite("SubChartParamsOverridesStore · 副图独立参数持久化")
struct SubChartParamsOverridesStoreTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SubOverridesTest-\(UUID().uuidString)")!
    }

    @Test("空 dict save then load → 空 dict 等价")
    func emptyDict() {
        let defaults = makeDefaults()
        SubChartParamsOverridesStore.save([:], defaults: defaults)
        let loaded = SubChartParamsOverridesStore.load(defaults: defaults)
        #expect(loaded == [:])
    }

    @Test("Int key 持久化 · JSON 中转 String 后能正确解码回 Int")
    func intKeyRoundTrip() {
        let defaults = makeDefaults()
        let custom = IndicatorParamsBook(
            mainMAPeriods: [7, 33, 99],
            mainBOLLParams: [25, 3],
            macdParams: [10, 22, 8],
            kdjParams: [14, 5, 5],
            rsiPeriod: 7
        )
        let overrides: [Int: IndicatorParamsBook] = [0: .default, 2: custom]
        SubChartParamsOverridesStore.save(overrides, defaults: defaults)
        let loaded = SubChartParamsOverridesStore.load(defaults: defaults)
        #expect(loaded == overrides)
        // 关键：Int key 要能 decode 回（不是 String）
        #expect(loaded?[0] == .default)
        #expect(loaded?[2] == custom)
        #expect(loaded?[1] == nil)
    }

    @Test("load 空时返回 nil")
    func loadEmptyReturnsNil() {
        let defaults = makeDefaults()
        #expect(SubChartParamsOverridesStore.load(defaults: defaults) == nil)
    }
}
