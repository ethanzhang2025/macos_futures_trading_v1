// MainApp v15.2 · IndicatorParamsBook 数据契约 + Codable 测试

import Testing
import Foundation
@testable import Shared

@Suite("IndicatorParamsBook · 数据契约 + Codable")
struct IndicatorParamsBookTests {

    @Test("default 出厂值 · v15.13 全字段")
    func defaults() {
        let d = IndicatorParamsBook.default
        #expect(d.mainMAPeriods == [5, 20, 60])
        #expect(d.mainBOLLParams == [20, 2])
        #expect(d.macdParams == [12, 26, 9])
        #expect(d.kdjParams == [9, 3, 3])
        #expect(d.rsiPeriod == 14)
        #expect(d.cciPeriod == 14)        // v15.11
        #expect(d.wrPeriod == 14)         // v15.11
        #expect(d.dmiPeriod == 14)        // v15.13
        #expect(d.stochParams == [14, 3]) // v15.13
        #expect(d.rocPeriod == 12)        // v15.13
        #expect(d.biasPeriod == 6)        // v15.13
    }

    @Test("v15.13 DMI/Stoch/ROC/BIAS Decimal helper")
    func v1513IndicatorsDecimal() {
        let d = IndicatorParamsBook.default
        #expect(d.dmiParamsDecimal == [Decimal(14)])
        #expect(d.stochParamsDecimal == [Decimal(14), Decimal(3)])
        #expect(d.rocParamsDecimal == [Decimal(12)])
        #expect(d.biasParamsDecimal == [Decimal(6)])
    }

    @Test("v15.13 兼容旧 JSON · 缺 dmi/stoch/roc/bias 字段时各 fallback 默认")
    func decodeLegacyJSONWithoutV1513Fields() throws {
        // 模拟 v15.12 之前持久化的 JSON（含 v15.11 cci/wr · 缺 v15.13 4 字段）
        let legacyJSON = """
        {
          "mainMAPeriods": [5, 20, 60],
          "mainBOLLParams": [20, 2],
          "macdParams": [12, 26, 9],
          "kdjParams": [9, 3, 3],
          "rsiPeriod": 14,
          "cciPeriod": 20,
          "wrPeriod": 9
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(IndicatorParamsBook.self, from: data)
        // v15.13 fallback
        #expect(decoded.dmiPeriod == 14)
        #expect(decoded.stochParams == [14, 3])
        #expect(decoded.rocPeriod == 12)
        #expect(decoded.biasPeriod == 6)
        // v15.11 字段保留用户值（不被覆盖）
        #expect(decoded.cciPeriod == 20)
        #expect(decoded.wrPeriod == 9)
    }

    @Test("v15.11 CCI/WR Decimal helper")
    func cciWrDecimal() {
        let d = IndicatorParamsBook.default
        #expect(d.cciParamsDecimal == [Decimal(14)])
        #expect(d.wrParamsDecimal == [Decimal(14)])
        var custom = d
        custom.cciPeriod = 20
        custom.wrPeriod = 9
        #expect(custom.cciParamsDecimal == [Decimal(20)])
        #expect(custom.wrParamsDecimal == [Decimal(9)])
    }

    @Test("v15.11 兼容旧 JSON · 缺 cciPeriod/wrPeriod 字段时 fallback 14/14")
    func decodeLegacyJSONWithoutCCIWR() throws {
        // 模拟 v15.10 之前持久化的 JSON（无 cciPeriod / wrPeriod 字段）· 用户启动 v15.11 应无感
        let legacyJSON = """
        {
          "mainMAPeriods": [5, 20, 60],
          "mainBOLLParams": [20, 2],
          "macdParams": [12, 26, 9],
          "kdjParams": [9, 3, 3],
          "rsiPeriod": 14
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(IndicatorParamsBook.self, from: data)
        #expect(decoded.cciPeriod == 14)  // fallback
        #expect(decoded.wrPeriod == 14)   // fallback
        // 旧字段不能丢
        #expect(decoded.mainMAPeriods == [5, 20, 60])
        #expect(decoded.rsiPeriod == 14)
    }

    @Test("Codable JSON 往返（含 v15.11 CCI/WR 字段）")
    func codableRoundTrip() throws {
        let book = IndicatorParamsBook(
            mainMAPeriods: [7, 33, 99],
            mainBOLLParams: [25, 3],
            macdParams: [10, 22, 8],
            kdjParams: [14, 5, 5],
            rsiPeriod: 9,
            cciPeriod: 20,
            wrPeriod: 7
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(IndicatorParamsBook.self, from: data)
        #expect(decoded == book)
        #expect(decoded.cciPeriod == 20)
        #expect(decoded.wrPeriod == 7)
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
