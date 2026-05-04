// WP-41 v15.18 · IndicatorRegistry 单测

import Testing
import Foundation
@testable import IndicatorCore

@Suite("IndicatorRegistry · 指标元数据")
struct IndicatorRegistryTests {

    @Test("totalCount > 50（v15.18 末已注册 50+ 指标）")
    func totalCountReasonable() {
        #expect(IndicatorRegistry.totalCount > 50)
    }

    @Test("所有 6 类别都有指标（无空类别）")
    func allCategoriesPresent() {
        let grouped = IndicatorRegistry.entriesByCategory()
        for category in IndicatorCategory.allCases {
            #expect((grouped[category]?.count ?? 0) > 0, "类别 \(category) 应有至少 1 个指标")
        }
    }

    @Test("entry(for:) 查询 · 命中 / 不命中")
    func entryLookup() {
        #expect(IndicatorRegistry.entry(for: "MACD")?.category == .oscillator)
        #expect(IndicatorRegistry.entry(for: "AROON")?.category == .trend)
        #expect(IndicatorRegistry.entry(for: "BBW")?.category == .volatility)
        #expect(IndicatorRegistry.entry(for: "STC")?.category == .trend)
        #expect(IndicatorRegistry.entry(for: "FI")?.category == .volume)
        #expect(IndicatorRegistry.entry(for: "NotExist") == nil)
    }

    @Test("v15.18 新增 5 指标 + ATRP + BBW · 全部 entry 在册")
    func v1518NewIndicatorsRegistered() {
        let newIds = ["AROON", "STC", "ELDER", "CHOPPINESS", "FI", "BBW", "ATRP"]
        for id in newIds {
            #expect(IndicatorRegistry.entry(for: id) != nil, "v15.18 新指标 \(id) 应在 registry")
        }
    }

    @Test("identifier 全部唯一（防 typo / 重复注册）")
    func identifiersUnique() {
        let ids = IndicatorRegistry.allEntries.map(\.identifier)
        let unique = Set(ids)
        #expect(ids.count == unique.count)
    }

    @Test("displayName 全部非空（防 UI 显示空白）")
    func displayNamesNonEmpty() {
        for entry in IndicatorRegistry.allEntries {
            #expect(!entry.displayName.isEmpty, "\(entry.identifier) displayName 不应为空")
        }
    }
}
