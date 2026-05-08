// SpreadPresets 单测（v15.27 · WP-套利分析 V1）

import Foundation
import Testing
@testable import DataCore

@Suite("SpreadPresets · 12 经典对预设")
struct SpreadPresetsTests {

    @Test("预设数 ≥ 10 · 覆盖 4 大类")
    func sufficientPresets() {
        #expect(SpreadPresets.all.count >= 10)
    }

    @Test("ID 全局唯一")
    func idsUnique() {
        let ids = SpreadPresets.all.map { $0.id }
        #expect(Set(ids).count == ids.count)
    }

    @Test("byID 索引完整")
    func byIDComplete() {
        #expect(SpreadPresets.byID.count == SpreadPresets.all.count)
    }

    @Test("byCategory 至少覆盖 4 类")
    func categoryCoverage() {
        let cats = Set(SpreadPresets.all.map { $0.category })
        #expect(cats.count >= 4)
    }

    @Test("核心预设存在 · rb-hc / au-80ag / IF-IH / T-TF")
    func corePresetsPresent() {
        #expect(SpreadPresets.byID["rb-hc"]   != nil)
        #expect(SpreadPresets.byID["au-80ag"] != nil)
        #expect(SpreadPresets.byID["IF-IH"]   != nil)
        #expect(SpreadPresets.byID["T-TF"]    != nil)
    }

    @Test("ratio 一正一负 · 双腿对冲结构")
    func legRatiosOpposite() {
        for pair in SpreadPresets.all {
            let r1 = pair.leg1.ratio
            let r2 = pair.leg2.ratio
            // 一正一负（典型对冲）· 不允许都是 0 / 同号
            let opposite = (r1 > 0 && r2 < 0) || (r1 < 0 && r2 > 0)
            #expect(opposite, "预设 \(pair.id) 双腿 ratio 应一正一负: \(r1)/\(r2)")
        }
    }

    @Test("name / description 非空")
    func namesAndDescriptionsPresent() {
        for pair in SpreadPresets.all {
            #expect(!pair.name.isEmpty)
            #expect(!pair.description.isEmpty)
            #expect(!pair.unitLabel.isEmpty)
        }
    }
}
