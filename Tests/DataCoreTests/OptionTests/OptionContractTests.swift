// OptionContract 单测（v15.28 · 期权全量 Phase 1）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("OptionContract · 模型字段 + 实/平/虚值判定 + 内在价值")
struct OptionContractTests {

    private func make(
        type: OptionType, strike: Decimal,
        spot: Decimal? = nil, daysToExp: Int = 30
    ) -> OptionContract {
        OptionContract(
            id: "test-\(type.rawValue)-\(strike)",
            underlyingID: "TEST",
            underlyingName: "测试标的",
            type: type,
            strikePrice: strike,
            expirationDate: Date().addingTimeInterval(TimeInterval(daysToExp * 86400)),
            exerciseStyle: .european,
            contractMultiplier: 100,
            category: .stockIndex,
            exchange: .CFFEX
        )
    }

    @Test("CALL 实值 · strike < spot")
    func callITM() {
        let opt = make(type: .call, strike: 3500)
        #expect(opt.relation(to: 3800) == .itm)
    }

    @Test("CALL 虚值 · strike > spot")
    func callOTM() {
        let opt = make(type: .call, strike: 4000)
        #expect(opt.relation(to: 3500) == .otm)
    }

    @Test("CALL 平值 · strike ≈ spot（默认 1% 容差）")
    func callATM() {
        let opt = make(type: .call, strike: 3500)
        // 3500 与 3520 差 0.57% < 1% → ATM
        #expect(opt.relation(to: 3520) == .atm)
    }

    @Test("PUT 实值 · strike > spot")
    func putITM() {
        let opt = make(type: .put, strike: 3800)
        #expect(opt.relation(to: 3500) == .itm)
    }

    @Test("PUT 虚值 · strike < spot")
    func putOTM() {
        let opt = make(type: .put, strike: 3500)
        #expect(opt.relation(to: 3800) == .otm)
    }

    @Test("CALL 内在价值 = max(spot - strike, 0)")
    func callIntrinsic() {
        let opt = make(type: .call, strike: 3500)
        #expect(opt.intrinsicValue(spotPrice: 3800) == 300)
        #expect(opt.intrinsicValue(spotPrice: 3200) == 0)
    }

    @Test("PUT 内在价值 = max(strike - spot, 0)")
    func putIntrinsic() {
        let opt = make(type: .put, strike: 3500)
        #expect(opt.intrinsicValue(spotPrice: 3200) == 300)
        #expect(opt.intrinsicValue(spotPrice: 3800) == 0)
    }

    @Test("到期日剩余天数 · 30 天后到期 = 30")
    func daysToExpirationCorrect() {
        let opt = make(type: .call, strike: 3500, daysToExp: 30)
        let days = opt.daysToExpiration()
        // 时区/时刻精度：允许 ±1 天误差
        #expect(days >= 29 && days <= 31)
    }

    @Test("已到期合约 · isExpired = true")
    func expiredFlag() {
        let opt = make(type: .call, strike: 3500, daysToExp: -10)
        #expect(opt.isExpired)
    }

    @Test("OptionType.displayName 中文")
    func typeDisplayName() {
        #expect(OptionType.call.displayName == "认购")
        #expect(OptionType.put.displayName == "认沽")
    }

    @Test("OptionCategory 全 3 类")
    func categoryAllCases() {
        #expect(OptionCategory.allCases.count == 3)
    }
}
