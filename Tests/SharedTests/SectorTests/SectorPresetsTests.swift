// SectorPresets 测试（v15.43）

import Testing
import Foundation
@testable import Shared

@Suite("SectorPresets · 板块品种归类")
struct SectorPresetsTests {

    @Test("all · 60+ 品种")
    func testAllCount() {
        #expect(SectorPresets.all.count >= 60)
    }

    @Test("byID · 全部 ID 唯一")
    func testIDUnique() {
        let ids = SectorPresets.all.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("byID · 索引完整")
    func testByIDComplete() {
        for inst in SectorPresets.all {
            #expect(SectorPresets.byID[inst.id] == inst)
        }
    }

    @Test("bySector · 11 板块全有数据")
    func testBySectorAllPopulated() {
        for sec in Sector.allCases {
            let list = SectorPresets.instruments(in: sec)
            #expect(!list.isEmpty, "板块 \(sec) 无品种")
        }
    }

    @Test("bySector · 总和 = all")
    func testBySectorSumEqualsAll() {
        let total = Sector.allCases.reduce(0) { $0 + SectorPresets.instruments(in: $1).count }
        #expect(total == SectorPresets.all.count)
    }

    @Test("黑色系 · 包含 RB0/HC0/I0/J0/JM0")
    func testBlackSector() {
        let ids = Set(SectorPresets.instruments(in: .黑色).map { $0.id })
        #expect(ids.isSuperset(of: ["RB0", "HC0", "I0", "J0", "JM0"]))
    }

    @Test("股指 · 含 IF0/IH0/IC0/IM0")
    func testStockIndex() {
        let ids = Set(SectorPresets.instruments(in: .股指).map { $0.id })
        #expect(ids == ["IF0", "IH0", "IC0", "IM0"])
    }

    @Test("贵金属 · 仅 AU0/AG0")
    func testPrecious() {
        let ids = Set(SectorPresets.instruments(in: .贵金属).map { $0.id })
        #expect(ids == ["AU0", "AG0"])
    }

    @Test("国债 · 4 期限")
    func testBonds() {
        let ids = Set(SectorPresets.instruments(in: .国债).map { $0.id })
        #expect(ids == ["T0", "TF0", "TS0", "TL0"])
    }

    @Test("changePct 范围 [-10, +10]")
    func testChangePctRange() {
        for inst in SectorPresets.all {
            #expect(inst.changePct >= -10 && inst.changePct <= 10,
                   "\(inst.id) 涨跌幅异常 \(inst.changePct)")
        }
    }

    @Test("openInterestK > 0")
    func testOpenInterestPositive() {
        for inst in SectorPresets.all {
            #expect(inst.openInterestK > 0,
                   "\(inst.id) 持仓量非正 \(inst.openInterestK)")
        }
    }
}
