// v17.154 · IndicatorPreset 一键指标套装单测

import Testing
import Foundation
@testable import Shared

@Suite("IndicatorPreset · 一键指标套装")
struct IndicatorPresetTests {

    @Test("allCases 6 类完整 · 顺序固定 classic/international/priceVolume/turtle/scalper/minimal")
    func allCases() {
        let cases = IndicatorPreset.allCases
        #expect(cases.count == 6)
        #expect(cases == [.classic, .international, .priceVolume, .turtle, .scalper, .minimal])
    }

    @Test("displayName / subtitle 6 类均非空 · 中文化 trader 友好")
    func displayMetadata() {
        for p in IndicatorPreset.allCases {
            #expect(!p.displayName.isEmpty)
            #expect(!p.subtitle.isEmpty)
        }
        #expect(IndicatorPreset.classic.displayName.contains("经典"))
        #expect(IndicatorPreset.international.displayName.contains("国际派"))
        #expect(IndicatorPreset.priceVolume.displayName.contains("价量派"))
        #expect(IndicatorPreset.turtle.displayName.contains("海龟"))
        #expect(IndicatorPreset.scalper.displayName.contains("短线"))
        #expect(IndicatorPreset.minimal.displayName.contains("裸 K"))
    }

    @Test("classic 含 MACD/KDJ/RSI/Volume 副图 + 0 overlay")
    func classicComposition() {
        let p = IndicatorPreset.classic
        #expect(p.subIndicatorRaws == ["macd", "kdj", "rsi", "volume"])
        #expect(p.overlayRaws.isEmpty)
    }

    @Test("international 含 Ichimoku overlay + MFI/ADX/CMF/ATRP 副图")
    func internationalComposition() {
        let p = IndicatorPreset.international
        #expect(p.subIndicatorRaws == ["mfi", "adx", "cmf", "atrp"])
        #expect(p.overlayRaws == ["ichimoku"])
    }

    @Test("priceVolume 含 VWAP overlay + OBV/PVT/CMF/Volume 副图（资金流核心）")
    func priceVolumeComposition() {
        let p = IndicatorPreset.priceVolume
        #expect(p.subIndicatorRaws.contains("obv"))
        #expect(p.subIndicatorRaws.contains("pvt"))
        #expect(p.subIndicatorRaws.contains("cmf"))
        #expect(p.overlayRaws == ["vwap"])
    }

    @Test("turtle 含 Donchian overlay（海龟法核心）+ ATRP/BBW 副图")
    func turtleComposition() {
        let p = IndicatorPreset.turtle
        #expect(p.overlayRaws == ["donchian"])
        #expect(p.subIndicatorRaws.contains("atrp"))
    }

    @Test("scalper 含 VWAP/Pivot/SuperTrend 3 overlay + Stoch/ROC/Volume 副图")
    func scalperComposition() {
        let p = IndicatorPreset.scalper
        #expect(Set(p.overlayRaws) == ["vwap", "pivot", "superTrend"])
        #expect(p.subIndicatorRaws.contains("stoch"))
        #expect(p.subIndicatorRaws.contains("roc"))
    }

    @Test("minimal 全空（裸 K · 看 K 线本身 · 调用方加 macd 占位防 UI 空白）")
    func minimalEmpty() {
        let p = IndicatorPreset.minimal
        #expect(p.subIndicatorRaws.isEmpty)
        #expect(p.overlayRaws.isEmpty)
    }

    @Test("所有 preset subIndicator/overlay raw 字符串非空 + 无重复")
    func rawIntegrity() {
        for p in IndicatorPreset.allCases {
            for raw in p.subIndicatorRaws {
                #expect(!raw.isEmpty, "preset \(p.rawValue) 含空 sub raw")
            }
            for raw in p.overlayRaws {
                #expect(!raw.isEmpty, "preset \(p.rawValue) 含空 overlay raw")
            }
            #expect(p.subIndicatorRaws.count == Set(p.subIndicatorRaws).count, "preset \(p.rawValue) sub 含重复")
            #expect(p.overlayRaws.count == Set(p.overlayRaws).count, "preset \(p.rawValue) overlay 含重复")
        }
    }
}
