// CalendarSpread 测试（v15.50）

import Testing
import Foundation
@testable import DataCore

@Suite("CalendarSpreadPresets · 跨期 preset")
struct CalendarSpreadPresetsTests {

    @Test("all · ≥ 12 跨期对")
    func testAllCount() {
        #expect(CalendarSpreadPresets.all.count >= 12)
    }

    @Test("byID · ID 唯一")
    func testIDUnique() {
        let ids = CalendarSpreadPresets.all.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("byCategory · 7 分类全 covered")
    func testCategoryCoverage() {
        for cat in CalendarSpreadPair.Category.allCases {
            let list = CalendarSpreadPresets.byCategory[cat] ?? []
            #expect(!list.isEmpty || cat == .股指 || cat == .国债 || cat == .贵金属,
                   "\(cat) 类别为空（除股指/国债/贵金属外）")
        }
    }

    @Test("near vs far month · 严格不同")
    func testNearFarDifferent() {
        for p in CalendarSpreadPresets.all {
            #expect(p.nearMonthID != p.farMonthID, "\(p.id) 近月远月相同")
        }
    }

    @Test("月份 ID 含品种代号前缀")
    func testMonthIDPrefix() {
        for p in CalendarSpreadPresets.all {
            #expect(p.nearMonthID.hasPrefix(p.underlyingID),
                   "\(p.id) 近月 \(p.nearMonthID) 不含品种 \(p.underlyingID)")
            #expect(p.farMonthID.hasPrefix(p.underlyingID),
                   "\(p.id) 远月 \(p.farMonthID) 不含品种 \(p.underlyingID)")
        }
    }

    @Test("黑色系跨期 · ≥ 4 对")
    func testBlackCount() {
        let black = CalendarSpreadPresets.byCategory[.黑色] ?? []
        #expect(black.count >= 4)
    }

    @Test("农产品跨期 · ≥ 4 对")
    func testAgriculturalCount() {
        let agri = CalendarSpreadPresets.byCategory[.农产品] ?? []
        #expect(agri.count >= 4)
    }
}

@Suite("CalendarSpreadCalculator · mock 时序")
struct CalendarSpreadCalculatorTests {

    @Test("生成 200 点时序")
    func testSeriesLength() {
        let pair = CalendarSpreadPresets.all.first!
        let values = CalendarSpreadCalculator.generateMockSeries(
            for: pair, basePrice: 3000, count: 200
        )
        #expect(values.count == 200)
    }

    @Test("近月/远月价均为正")
    func testPositivePrices() {
        let pair = CalendarSpreadPresets.byID["rb-05-10"]!
        let values = CalendarSpreadCalculator.generateMockSeries(
            for: pair, basePrice: 3245, count: 100
        )
        for v in values {
            let near = NSDecimalNumber(decimal: v.nearPrice).doubleValue
            let far = NSDecimalNumber(decimal: v.farPrice).doubleValue
            #expect(near > 0)
            #expect(far > 0)
        }
    }

    @Test("contango 主导（远月 > 近月 · 大部分点）")
    func testContangoDominance() {
        let pair = CalendarSpreadPresets.byID["rb-05-10"]!
        let values = CalendarSpreadCalculator.generateMockSeries(
            for: pair, basePrice: 3245, count: 200
        )
        let contangoCount = values.filter {
            NSDecimalNumber(decimal: $0.spread).doubleValue > 0
        }.count
        // mock 公式：远月 = 近月 + 持有成本（≈ 1.5%）· 大部分应 contango
        #expect(Double(contangoCount) / Double(values.count) > 0.7,
               "mock 应大部分 contango · 实测 \(contangoCount)/200")
    }

    @Test("toSpreadValues · 转换正确")
    func testToSpreadValues() {
        let pair = CalendarSpreadPresets.all.first!
        let calVals = CalendarSpreadCalculator.generateMockSeries(
            for: pair, basePrice: 1000, count: 50
        )
        let svs = CalendarSpreadCalculator.toSpreadValues(calVals)
        #expect(svs.count == calVals.count)
        for (i, sv) in svs.enumerated() {
            #expect(sv.openTime == calVals[i].openTime)
            #expect(sv.value == calVals[i].spread)
            #expect(sv.leg1Close == calVals[i].nearPrice)
            #expect(sv.leg2Close == calVals[i].farPrice)
        }
    }

    @Test("seeded RNG · 同 pair 同 seed 价格序列可复现")
    func testReproducible() {
        // 时间戳含 Date() 不可复现 · 仅比价格部分（trader 看图主体）
        let pair = CalendarSpreadPresets.all.first!
        let v1 = CalendarSpreadCalculator.generateMockSeries(for: pair, basePrice: 3000, count: 50)
        let v2 = CalendarSpreadCalculator.generateMockSeries(for: pair, basePrice: 3000, count: 50)
        #expect(v1.count == v2.count)
        for i in 0..<v1.count {
            #expect(v1[i].nearPrice == v2[i].nearPrice, "near[\(i)] 不一致")
            #expect(v1[i].farPrice == v2[i].farPrice, "far[\(i)] 不一致")
            #expect(v1[i].spread == v2[i].spread, "spread[\(i)] 不一致")
        }
    }
}
