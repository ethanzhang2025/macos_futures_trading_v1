// VolatilitySurface 单测（v15.30 · 期权 Phase 3）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("VolatilitySurface · 网格化 IV + 构建器")
struct VolatilitySurfaceTests {

    private func makeOption(
        type: OptionType, strike: Decimal, daysFromNow: Int
    ) -> OptionContract {
        let exp = Date().addingTimeInterval(TimeInterval(daysFromNow * 86400))
        return OptionContract(
            id: "TEST-\(type.rawValue)-\(strike)-\(daysFromNow)",
            underlyingID: "TEST", underlyingName: "测试",
            type: type, strikePrice: strike, expirationDate: exp,
            exerciseStyle: .european, contractMultiplier: 100,
            category: .stockIndex, exchange: .CFFEX
        )
    }

    @Test("byExpiration / byStrike / allStrikes / allExpirations")
    func indicesCorrect() {
        let points = [
            VolatilityPoint(strikePrice: 100, timeToExpiration: 0.25,
                           impliedVolatility: 0.20, optionType: .call, marketPrice: 5),
            VolatilityPoint(strikePrice: 110, timeToExpiration: 0.25,
                           impliedVolatility: 0.22, optionType: .call, marketPrice: 3),
            VolatilityPoint(strikePrice: 100, timeToExpiration: 0.50,
                           impliedVolatility: 0.21, optionType: .call, marketPrice: 7),
        ]
        let surface = VolatilitySurface(
            underlyingID: "TEST", underlyingName: "测试",
            spotPrice: 100, riskFreeRate: 0.05, dividendYield: 0,
            points: points
        )
        #expect(surface.allStrikes == [100, 110])
        #expect(surface.allExpirations == [0.25, 0.50])
        #expect(surface.byExpiration[0.25]?.count == 2)
        #expect(surface.byStrike[100]?.count == 2)
    }

    @Test("nearest · 最贴近 (strike, T) 的点")
    func nearestPoint() {
        let points = [
            VolatilityPoint(strikePrice: 100, timeToExpiration: 0.25,
                           impliedVolatility: 0.20, optionType: .call, marketPrice: 5),
            VolatilityPoint(strikePrice: 105, timeToExpiration: 0.25,
                           impliedVolatility: 0.22, optionType: .call, marketPrice: 3),
            VolatilityPoint(strikePrice: 100, timeToExpiration: 0.50,
                           impliedVolatility: 0.21, optionType: .call, marketPrice: 7),
        ]
        let surface = VolatilitySurface(
            underlyingID: "TEST", underlyingName: "测试",
            spotPrice: 100, riskFreeRate: 0.05, dividendYield: 0,
            points: points
        )
        // 查 (102, 0.27) → 最贴近 (100, 0.25) 或 (105, 0.25)
        let p = surface.nearest(strike: 102, time: 0.27)
        #expect(p != nil)
        // 偏好 strike=100（差 2 + 0.02·100 = 4） vs strike=105（差 3 + 0.02·100 = 5）
        #expect(p?.strikePrice == 100)
    }

    @Test("Builder · 圆环测试 · σ=25% 链 → 反推 ≈ 25%")
    func builderRoundTrip() {
        // 1. 构造期权链（3 strikes × 2 到期 = 6 contracts × 2 (CALL+PUT) = 12 合约）
        let strikes: [Decimal] = [95, 100, 105]
        let daysList = [30, 60]
        var contracts: [OptionContract] = []
        for K in strikes {
            for days in daysList {
                contracts.append(makeOption(type: .call, strike: K, daysFromNow: days))
                contracts.append(makeOption(type: .put,  strike: K, daysFromNow: days))
            }
        }
        guard let chain = OptionChainBuilder.build(contracts: contracts) else {
            Issue.record("链构造失败")
            return
        }

        // 2. 用 σ=25% 算理论价 · 构造市价表
        let σ = 0.25
        let r = 0.05
        let S = 100.0
        var prices: [String: Double] = [:]
        for c in contracts {
            let T = Double(c.daysToExpiration()) / 365.0
            let inputs = BlackScholes.Inputs(spotPrice: S,
                                              strikePrice: NSDecimalNumber(decimal: c.strikePrice).doubleValue,
                                              timeToExpirationYears: T,
                                              riskFreeRate: r, volatility: σ)
            prices[c.id] = BlackScholes.price(type: c.type, inputs: inputs)
        }

        // 3. Builder 反推 IV 曲面
        let surface = VolatilitySurfaceBuilder.build(
            chain: chain, prices: prices,
            spotPrice: S, riskFreeRate: r
        )

        // 4. 所有点 IV 都应 ≈ 25%
        #expect(!surface.points.isEmpty)
        for p in surface.points {
            #expect(abs(p.impliedVolatility - σ) < 0.005)   // 0.5% 容差
        }
    }

    @Test("Builder · 缺数据合约跳过 · 不崩")
    func builderHandlesMissingPrices() {
        let chain = OptionChainBuilder.build(contracts: [
            makeOption(type: .call, strike: 100, daysFromNow: 30),
            makeOption(type: .put,  strike: 100, daysFromNow: 30),
        ])!
        // 给空价格 · 应返空 surface · 不崩
        let surface = VolatilitySurfaceBuilder.build(
            chain: chain, prices: [:],
            spotPrice: 100, riskFreeRate: 0.05
        )
        #expect(surface.points.isEmpty)
    }

    @Test("Builder · 已到期 slice 跳过")
    func builderSkipsExpiredSlices() {
        let chain = OptionChainBuilder.build(contracts: [
            makeOption(type: .call, strike: 100, daysFromNow: -10),  // 已过期
            makeOption(type: .call, strike: 100, daysFromNow: 30),
        ])!
        let prices = ["TEST-CALL-100--10": 5.0, "TEST-CALL-100-30": 5.0]
        let surface = VolatilitySurfaceBuilder.build(
            chain: chain, prices: prices,
            spotPrice: 100, riskFreeRate: 0.05
        )
        // 只应该有 1 点（来自 daysFromNow=30 的 slice）
        #expect(surface.points.count <= 1)
    }
}
