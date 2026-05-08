// OptionChain 单测（v15.28 · 期权全量 Phase 1）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("OptionChain · 期权链组装 + ATM 行查找 + 排序")
struct OptionChainTests {

    private func contract(
        type: OptionType, strike: Decimal, exp: Date
    ) -> OptionContract {
        OptionContract(
            id: "TEST-\(type.rawValue)-\(strike)-\(exp.timeIntervalSince1970)",
            underlyingID: "TEST", underlyingName: "测试",
            type: type, strikePrice: strike, expirationDate: exp,
            exerciseStyle: .european, contractMultiplier: 100,
            category: .stockIndex, exchange: .CFFEX
        )
    }

    private func date(_ daysFromNow: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(daysFromNow * 86400))
    }

    @Test("空合约列表 → nil")
    func emptyContractsReturnsNil() {
        #expect(OptionChainBuilder.build(contracts: []) == nil)
    }

    @Test("单到期日 + 3 strike + 配对 CALL/PUT")
    func singleExpirationPairs() {
        let exp = date(30)
        let contracts = [
            contract(type: .call, strike: 3500, exp: exp),
            contract(type: .call, strike: 3550, exp: exp),
            contract(type: .call, strike: 3600, exp: exp),
            contract(type: .put,  strike: 3500, exp: exp),
            contract(type: .put,  strike: 3550, exp: exp),
            contract(type: .put,  strike: 3600, exp: exp),
        ]
        let chain = OptionChainBuilder.build(contracts: contracts)
        #expect(chain != nil)
        #expect(chain?.slices.count == 1)
        #expect(chain?.slices[0].rows.count == 3)
        // 每行配对完整
        for row in chain?.slices[0].rows ?? [] {
            #expect(row.call != nil)
            #expect(row.put != nil)
        }
    }

    @Test("Strike 升序")
    func strikesSortedAscending() {
        let exp = date(30)
        let contracts = [
            contract(type: .call, strike: 3600, exp: exp),
            contract(type: .call, strike: 3500, exp: exp),
            contract(type: .call, strike: 3700, exp: exp),
        ]
        let chain = OptionChainBuilder.build(contracts: contracts)
        let strikes = chain?.slices[0].rows.map { $0.strikePrice }
        #expect(strikes == [3500, 3600, 3700])
    }

    @Test("多到期日 · slices 按时间升序")
    func multipleExpirationsSorted() {
        let near = date(30)
        let mid = date(60)
        let far = date(90)
        let contracts = [
            contract(type: .call, strike: 3500, exp: far),
            contract(type: .call, strike: 3500, exp: near),
            contract(type: .call, strike: 3500, exp: mid),
        ]
        let chain = OptionChainBuilder.build(contracts: contracts)
        let dates = chain?.slices.map { $0.expirationDate.timeIntervalSince1970 }
        #expect(dates?.count == 3)
        for i in 1..<(dates?.count ?? 0) {
            #expect(dates![i] > dates![i - 1])
        }
    }

    @Test("ATM 行 · 选最贴近现价的 strike")
    func atmRowFinder() {
        let exp = date(30)
        let strikes: [Decimal] = [3400, 3500, 3600, 3700, 3800]
        let contracts = strikes.map { contract(type: .call, strike: $0, exp: exp) }
                     + strikes.map { contract(type: .put, strike: $0, exp: exp) }
        let chain = OptionChainBuilder.build(contracts: contracts)
        let slice = chain?.slices.first
        // spot=3580 → 最贴近 strike=3600
        let atm = slice?.atmRow(spotPrice: 3580)
        #expect(atm?.strikePrice == 3600)
    }

    @Test("缺一边（仅 CALL · 无 PUT）→ row.put = nil 不崩")
    func missingPutLeg() {
        let exp = date(30)
        let chain = OptionChainBuilder.build(contracts: [
            contract(type: .call, strike: 3500, exp: exp),
        ])
        let row = chain?.slices.first?.rows.first
        #expect(row?.call != nil)
        #expect(row?.put == nil)
    }

    @Test("nearestExpiration · 取第 1 个 slice")
    func nearestExpirationCorrect() {
        let near = date(15)
        let far = date(60)
        let chain = OptionChainBuilder.build(contracts: [
            contract(type: .call, strike: 3500, exp: far),
            contract(type: .call, strike: 3500, exp: near),
        ])
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.startOfDay(for: chain?.nearestExpiration?.expirationDate ?? Date())
                == cal.startOfDay(for: near))
    }
}
