// OptionPresets 单测（v15.28 · 期权全量 Phase 1）

import Foundation
import Testing
@testable import DataCore

@Suite("OptionPresets · 3 旗舰标的 + 示例链")
struct OptionPresetsTests {

    @Test("3 旗舰标的 · IO/m/SR")
    func threeUnderlyings() {
        #expect(OptionPresets.underlyings.count == 3)
        #expect(OptionPresets.byUnderlyingID["IO"] != nil)
        #expect(OptionPresets.byUnderlyingID["m"]  != nil)
        #expect(OptionPresets.byUnderlyingID["SR"] != nil)
    }

    @Test("IO 沪深300 股指期权 · 欧式 · 中金所")
    func IOMeta() {
        let io = OptionPresets.byUnderlyingID["IO"]
        #expect(io?.exerciseStyle == .european)
        #expect(io?.category == .stockIndex)
        #expect(io?.multiplier == 100)
    }

    @Test("豆粕期权 · 美式 · 大商所 · 商品")
    func mMeta() {
        let m = OptionPresets.byUnderlyingID["m"]
        #expect(m?.exerciseStyle == .american)
        #expect(m?.category == .commodity)
        #expect(m?.multiplier == 10)
    }

    @Test("sampleChain · 3 到期 × 11 strike × 2 = 66 合约")
    func sampleChainSize() {
        let chain = OptionPresets.sampleChain(for: "IO")
        #expect(chain != nil)
        #expect(chain?.slices.count == 3)
        for slice in chain?.slices ?? [] {
            #expect(slice.rows.count == 11)   // ±5 ATM = 11 strike
            for row in slice.rows {
                #expect(row.call != nil)
                #expect(row.put != nil)
            }
        }
    }

    @Test("sampleChain · ATM 行 strike 与现价偏差 ≤ 1 个 step")
    func sampleChainATMAroundSpot() {
        guard let chain = OptionPresets.sampleChain(for: "m") else {
            Issue.record("豆粕期权链构造失败")
            return
        }
        let m = OptionPresets.byUnderlyingID["m"]!
        let spot = NSDecimalNumber(decimal: m.spotPrice).doubleValue   // 3180
        let step = NSDecimalNumber(decimal: m.strikeStep).doubleValue  // 50
        // 取近月 ATM 行
        let atm = chain.nearestExpiration?.atmRow(spotPrice: m.spotPrice)
        #expect(atm != nil)
        let atmStrike = NSDecimalNumber(decimal: atm!.strikePrice).doubleValue
        // |atmStrike - spot| ≤ step
        #expect(abs(atmStrike - spot) <= step)
    }

    @Test("未知标的 ID → nil 不崩")
    func unknownIDReturnsNil() {
        #expect(OptionPresets.sampleChain(for: "UNKNOWN") == nil)
    }

    @Test("strike step 各标的合理 · 50ETF 视角去掉 · 期货视角 m 50 / SR 100 / IO 50")
    func stepCorrect() {
        #expect(OptionPresets.byUnderlyingID["IO"]?.strikeStep == 50)
        #expect(OptionPresets.byUnderlyingID["m"]?.strikeStep == 50)
        #expect(OptionPresets.byUnderlyingID["SR"]?.strikeStep == 100)
    }
}
