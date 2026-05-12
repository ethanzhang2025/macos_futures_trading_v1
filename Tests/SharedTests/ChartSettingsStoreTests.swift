// v17.92 · ChartSettingsStore 单测（K 线配色 + 价格精度 持久化）

import Testing
import Foundation
@testable import Shared

@Suite("ChartSettingsStore · v17.92 K 线配色 + 价格精度")
struct ChartSettingsStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.chartSettings.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    @Test("默认 candle color = redUpGreenDown（中国习惯）")
    func defaultCandleColor() {
        let d = makeDefaults()
        #expect(ChartSettingsStore.loadCandleColorMode(defaults: d) == .redUpGreenDown)
    }

    @Test("默认 price precision = auto（跟随合约）")
    func defaultPricePrecision() {
        let d = makeDefaults()
        #expect(ChartSettingsStore.loadPricePrecision(defaults: d) == .auto)
    }

    @Test("save → load round-trip · candle color")
    func candleColorRoundTrip() {
        let d = makeDefaults()
        ChartSettingsStore.saveCandleColorMode(.greenUpRedDown, defaults: d)
        #expect(ChartSettingsStore.loadCandleColorMode(defaults: d) == .greenUpRedDown)
    }

    @Test("save → load round-trip · price precision 全 4 选项")
    func pricePrecisionRoundTrip() {
        for mode in PricePrecisionMode.allCases {
            let d = makeDefaults()
            ChartSettingsStore.savePricePrecision(mode, defaults: d)
            #expect(ChartSettingsStore.loadPricePrecision(defaults: d) == mode)
        }
    }

    @Test("PricePrecisionMode.digits · auto = nil / fixed = 2/3/4")
    func pricePrecisionDigits() {
        #expect(PricePrecisionMode.auto.digits == nil)
        #expect(PricePrecisionMode.fixed2.digits == 2)
        #expect(PricePrecisionMode.fixed3.digits == 3)
        #expect(PricePrecisionMode.fixed4.digits == 4)
    }

    @Test("非法 rawValue 回退默认")
    func invalidRawFallsBackToDefault() {
        let d = makeDefaults()
        d.set("invalid_mode_xxx", forKey: ChartSettingsStore.candleColorKey)
        d.set("not_a_precision", forKey: ChartSettingsStore.pricePrecisionKey)
        #expect(ChartSettingsStore.loadCandleColorMode(defaults: d) == .redUpGreenDown)
        #expect(ChartSettingsStore.loadPricePrecision(defaults: d) == .auto)
    }

    @Test("resetAll 清空两 key · load 回到默认")
    func resetAllRestoresDefaults() {
        let d = makeDefaults()
        ChartSettingsStore.saveCandleColorMode(.greenUpRedDown, defaults: d)
        ChartSettingsStore.savePricePrecision(.fixed4, defaults: d)
        ChartSettingsStore.resetAll(defaults: d)
        #expect(ChartSettingsStore.loadCandleColorMode(defaults: d) == .redUpGreenDown)
        #expect(ChartSettingsStore.loadPricePrecision(defaults: d) == .auto)
    }
}
