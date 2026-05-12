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

    // MARK: - v17.111 · 4 新设置

    @Test("v17.111 · 默认值（字号 medium · HUD normal · 网格 medium · 副图 normal）")
    func v17111Defaults() {
        let d = makeDefaults()
        #expect(ChartSettingsStore.loadChartFontSize(defaults: d) == .medium)
        #expect(ChartSettingsStore.loadHUDOpacityMode(defaults: d) == .normal)
        #expect(ChartSettingsStore.loadGridDensity(defaults: d) == .medium)
        #expect(ChartSettingsStore.loadSubChartDefaultRatio(defaults: d) == .normal)
    }

    @Test("v17.111 · save → load round-trip 全 4 项 × 全 case")
    func v17111RoundTrip() {
        for mode in ChartFontSize.allCases {
            let d = makeDefaults()
            ChartSettingsStore.saveChartFontSize(mode, defaults: d)
            #expect(ChartSettingsStore.loadChartFontSize(defaults: d) == mode)
        }
        for mode in HUDOpacityMode.allCases {
            let d = makeDefaults()
            ChartSettingsStore.saveHUDOpacityMode(mode, defaults: d)
            #expect(ChartSettingsStore.loadHUDOpacityMode(defaults: d) == mode)
        }
        for mode in GridDensity.allCases {
            let d = makeDefaults()
            ChartSettingsStore.saveGridDensity(mode, defaults: d)
            #expect(ChartSettingsStore.loadGridDensity(defaults: d) == mode)
        }
        for mode in SubChartDefaultRatio.allCases {
            let d = makeDefaults()
            ChartSettingsStore.saveSubChartDefaultRatio(mode, defaults: d)
            #expect(ChartSettingsStore.loadSubChartDefaultRatio(defaults: d) == mode)
        }
    }

    @Test("v17.111 · ChartFontSize sizeDelta 数值（small=-1 / medium=0 / large=+1）")
    func chartFontSizeSizeDelta() {
        #expect(ChartFontSize.small.sizeDelta == -1)
        #expect(ChartFontSize.medium.sizeDelta == 0)
        #expect(ChartFontSize.large.sizeDelta == +1)
    }

    @Test("v17.111 · HUDOpacityMode alpha（subtle 0.40 / normal 0.60 / strong 0.80）· light 一档高")
    func hudOpacityModeAlpha() {
        #expect(HUDOpacityMode.subtle.darkAlpha == 0.40)
        #expect(HUDOpacityMode.normal.darkAlpha == 0.60)
        #expect(HUDOpacityMode.strong.darkAlpha == 0.80)
        #expect(HUDOpacityMode.subtle.lightAlpha == 0.65)
        #expect(HUDOpacityMode.normal.lightAlpha == 0.85)
        #expect(HUDOpacityMode.strong.lightAlpha == 0.95)
    }

    @Test("v17.111 · GridDensity 倍率（sparse 1.5 / medium 1.0 / dense 0.7）")
    func gridDensityStrideMultiplier() {
        #expect(GridDensity.sparse.strideMultiplier == 1.5)
        #expect(GridDensity.medium.strideMultiplier == 1.0)
        #expect(GridDensity.dense.strideMultiplier == 0.7)
    }

    @Test("v17.111 · SubChartDefaultRatio ratio（slim 0.20 / normal 0.30 / tall 0.40）")
    func subChartDefaultRatioValue() {
        #expect(SubChartDefaultRatio.slim.ratio == 0.20)
        #expect(SubChartDefaultRatio.normal.ratio == 0.30)
        #expect(SubChartDefaultRatio.tall.ratio == 0.40)
    }

    @Test("v17.111 · resetAll 清空 6 个 key 全部回默认")
    func resetAllClearsV17111Keys() {
        let d = makeDefaults()
        ChartSettingsStore.saveChartFontSize(.large, defaults: d)
        ChartSettingsStore.saveHUDOpacityMode(.strong, defaults: d)
        ChartSettingsStore.saveGridDensity(.dense, defaults: d)
        ChartSettingsStore.saveSubChartDefaultRatio(.tall, defaults: d)
        ChartSettingsStore.resetAll(defaults: d)
        #expect(ChartSettingsStore.loadChartFontSize(defaults: d) == .medium)
        #expect(ChartSettingsStore.loadHUDOpacityMode(defaults: d) == .normal)
        #expect(ChartSettingsStore.loadGridDensity(defaults: d) == .medium)
        #expect(ChartSettingsStore.loadSubChartDefaultRatio(defaults: d) == .normal)
    }
}
