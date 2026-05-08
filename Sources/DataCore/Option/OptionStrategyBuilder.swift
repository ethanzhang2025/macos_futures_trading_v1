// 期权策略构造器（v15.31 · 期权 Phase 4 · WP-期权 策略层）
//
// 4 大经典策略一键构造：
//   - 牛市看涨价差（Bull Call Spread）：Long Call(K1) + Short Call(K2) · K1 < K2
//   - 熊市看跌价差（Bear Put Spread）：Long Put(K2) + Short Put(K1) · K1 < K2
//   - 长跨式（Long Straddle）：Long Call(K) + Long Put(K)
//   - 长宽跨式（Long Strangle）：Long Call(K_high) + Long Put(K_low)
//   - 蝶式（Long Butterfly）：Long Call(K1) + 2 Short Call(K2) + Long Call(K3) · K1 < K2 < K3 等距
//   - 铁鹰（Iron Condor）：Bear Call Spread (K3, K4) + Bull Put Spread (K1, K2) · K1<K2<K3<K4
//
// 调用方传入：标的标识 + 期权链 + 现价 + 选 strike
// 返回：构造好的 OptionStrategy（leg 完整 · entryPremium 用 BS 理论价代替 v1）
//
// V2 计划：entryPremium 接真盘口

import Foundation

public enum OptionStrategyBuilder {

    /// 构造时的辅助参数
    public struct Context {
        public let chain: OptionChain
        public let spotPrice: Double
        public let riskFreeRate: Double
        public let volatility: Double      // 用于估算 entryPremium（v1 简化）
        public let dividendYield: Double

        public init(chain: OptionChain, spotPrice: Double, riskFreeRate: Double,
                    volatility: Double = 0.25, dividendYield: Double = 0) {
            self.chain = chain
            self.spotPrice = spotPrice
            self.riskFreeRate = riskFreeRate
            self.volatility = volatility
            self.dividendYield = dividendYield
        }
    }

    // MARK: - 牛市看涨价差

    /// Long Call(lowStrike) + Short Call(highStrike)
    /// 用法：你认为标的会涨 · 但只涨到一定区间 · 限定上涨利润换低权利金
    /// - Parameters:
    ///   - quantity: 张数
    public static func bullCallSpread(
        context: Context,
        lowStrike: Double, highStrike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard lowStrike < highStrike,
              let slice = context.chain.slice(for: expiration),
              let longCall = findContract(slice: slice, type: .call, strike: lowStrike),
              let shortCall = findContract(slice: slice, type: .call, strike: highStrike)
        else { return nil }

        let longPremium = theoreticalPrice(contract: longCall, context: context)
        let shortPremium = theoreticalPrice(contract: shortCall, context: context)

        return OptionStrategy(
            id: "bull-call-\(context.chain.underlyingID)-\(Int(lowStrike))-\(Int(highStrike))",
            name: "牛市看涨价差 \(Int(lowStrike))/\(Int(highStrike))",
            strategyType: .bullCallSpread,
            legs: [
                OptionStrategyLeg(contract: longCall, direction: .long, quantity: quantity, entryPremium: longPremium),
                OptionStrategyLeg(contract: shortCall, direction: .short, quantity: quantity, entryPremium: shortPremium),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 熊市看跌价差

    /// Long Put(highStrike) + Short Put(lowStrike) · 你看跌但只跌到区间
    public static func bearPutSpread(
        context: Context,
        lowStrike: Double, highStrike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard lowStrike < highStrike,
              let slice = context.chain.slice(for: expiration),
              let longPut = findContract(slice: slice, type: .put, strike: highStrike),
              let shortPut = findContract(slice: slice, type: .put, strike: lowStrike)
        else { return nil }

        let longPremium = theoreticalPrice(contract: longPut, context: context)
        let shortPremium = theoreticalPrice(contract: shortPut, context: context)

        return OptionStrategy(
            id: "bear-put-\(context.chain.underlyingID)-\(Int(lowStrike))-\(Int(highStrike))",
            name: "熊市看跌价差 \(Int(highStrike))/\(Int(lowStrike))",
            strategyType: .bearPutSpread,
            legs: [
                OptionStrategyLeg(contract: longPut, direction: .long, quantity: quantity, entryPremium: longPremium),
                OptionStrategyLeg(contract: shortPut, direction: .short, quantity: quantity, entryPremium: shortPremium),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 长跨式

    /// Long Call(K) + Long Put(K) · 你预期大波动但不知方向
    public static func longStraddle(
        context: Context,
        strike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard let slice = context.chain.slice(for: expiration),
              let call = findContract(slice: slice, type: .call, strike: strike),
              let put = findContract(slice: slice, type: .put, strike: strike)
        else { return nil }

        let callPremium = theoreticalPrice(contract: call, context: context)
        let putPremium = theoreticalPrice(contract: put, context: context)

        return OptionStrategy(
            id: "long-straddle-\(context.chain.underlyingID)-\(Int(strike))",
            name: "长跨式 \(Int(strike))",
            strategyType: .longStraddle,
            legs: [
                OptionStrategyLeg(contract: call, direction: .long, quantity: quantity, entryPremium: callPremium),
                OptionStrategyLeg(contract: put, direction: .long, quantity: quantity, entryPremium: putPremium),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 长宽跨式

    /// Long Call(highStrike) + Long Put(lowStrike) · 大波动但腿权利金更便宜
    public static func longStrangle(
        context: Context,
        lowStrike: Double, highStrike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard lowStrike < highStrike,
              let slice = context.chain.slice(for: expiration),
              let put = findContract(slice: slice, type: .put, strike: lowStrike),
              let call = findContract(slice: slice, type: .call, strike: highStrike)
        else { return nil }

        let putPremium = theoreticalPrice(contract: put, context: context)
        let callPremium = theoreticalPrice(contract: call, context: context)

        return OptionStrategy(
            id: "long-strangle-\(context.chain.underlyingID)-\(Int(lowStrike))-\(Int(highStrike))",
            name: "长宽跨式 \(Int(lowStrike))/\(Int(highStrike))",
            strategyType: .longStrangle,
            legs: [
                OptionStrategyLeg(contract: put, direction: .long, quantity: quantity, entryPremium: putPremium),
                OptionStrategyLeg(contract: call, direction: .long, quantity: quantity, entryPremium: callPremium),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 蝶式

    /// Long Call(K1) + 2 Short Call(K2) + Long Call(K3) · K1 < K2 < K3 等距
    /// 你认为标的会停留在 K2 附近 · 高 PnL 当 S=K2 · 远端有限
    public static func longButterfly(
        context: Context,
        lowStrike: Double, midStrike: Double, highStrike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard lowStrike < midStrike, midStrike < highStrike,
              let slice = context.chain.slice(for: expiration),
              let call1 = findContract(slice: slice, type: .call, strike: lowStrike),
              let call2 = findContract(slice: slice, type: .call, strike: midStrike),
              let call3 = findContract(slice: slice, type: .call, strike: highStrike)
        else { return nil }

        let p1 = theoreticalPrice(contract: call1, context: context)
        let p2 = theoreticalPrice(contract: call2, context: context)
        let p3 = theoreticalPrice(contract: call3, context: context)

        return OptionStrategy(
            id: "long-butterfly-\(context.chain.underlyingID)-\(Int(lowStrike))-\(Int(midStrike))-\(Int(highStrike))",
            name: "蝶式 \(Int(lowStrike))/\(Int(midStrike))/\(Int(highStrike))",
            strategyType: .longButterfly,
            legs: [
                OptionStrategyLeg(contract: call1, direction: .long, quantity: quantity, entryPremium: p1),
                OptionStrategyLeg(contract: call2, direction: .short, quantity: quantity * 2, entryPremium: p2),
                OptionStrategyLeg(contract: call3, direction: .long, quantity: quantity, entryPremium: p3),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 铁鹰

    /// Bull Put Spread (K1, K2) + Bear Call Spread (K3, K4) · K1<K2<K3<K4
    /// 4 leg：Long Put(K1) + Short Put(K2) + Short Call(K3) + Long Call(K4)
    /// 用法：你认为标的会在 [K2, K3] 区间窄幅震荡 · 收净权利金 · 上下两侧风险有限
    public static func ironCondor(
        context: Context,
        putLowStrike: Double, putHighStrike: Double,
        callLowStrike: Double, callHighStrike: Double,
        expiration: Date,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard putLowStrike < putHighStrike,
              putHighStrike < callLowStrike,
              callLowStrike < callHighStrike,
              let slice = context.chain.slice(for: expiration),
              let longPut   = findContract(slice: slice, type: .put,  strike: putLowStrike),
              let shortPut  = findContract(slice: slice, type: .put,  strike: putHighStrike),
              let shortCall = findContract(slice: slice, type: .call, strike: callLowStrike),
              let longCall  = findContract(slice: slice, type: .call, strike: callHighStrike)
        else { return nil }

        let lpP = theoreticalPrice(contract: longPut,   context: context)
        let spP = theoreticalPrice(contract: shortPut,  context: context)
        let scP = theoreticalPrice(contract: shortCall, context: context)
        let lcP = theoreticalPrice(contract: longCall,  context: context)

        return OptionStrategy(
            id: "iron-condor-\(context.chain.underlyingID)-\(Int(putLowStrike))-\(Int(putHighStrike))-\(Int(callLowStrike))-\(Int(callHighStrike))",
            name: "铁鹰 \(Int(putLowStrike))/\(Int(putHighStrike))/\(Int(callLowStrike))/\(Int(callHighStrike))",
            strategyType: .ironCondor,
            legs: [
                OptionStrategyLeg(contract: longPut,   direction: .long,  quantity: quantity, entryPremium: lpP),
                OptionStrategyLeg(contract: shortPut,  direction: .short, quantity: quantity, entryPremium: spP),
                OptionStrategyLeg(contract: shortCall, direction: .short, quantity: quantity, entryPremium: scP),
                OptionStrategyLeg(contract: longCall,  direction: .long,  quantity: quantity, entryPremium: lcP),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName
        )
    }

    // MARK: - 备兑开仓

    /// Long Underlying + Short Call(callStrike) · 你长期持有标的 · 卖 Call 收权利金增厚收益
    /// 用法：温和看涨 / 中性 · 上方利润有限（被行权）· 下方有标的下跌风险（不是无限 · 但权利金缓冲）
    /// - Parameters:
    ///   - underlyingEntryPrice: 标的持仓均价（默认 = 当前现价 · 即按现价新建仓）
    public static func coveredCall(
        context: Context,
        callStrike: Double,
        expiration: Date,
        underlyingEntryPrice: Double? = nil,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard let slice = context.chain.slice(for: expiration),
              let shortCall = findContract(slice: slice, type: .call, strike: callStrike)
        else { return nil }

        let scP = theoreticalPrice(contract: shortCall, context: context)
        let entry = underlyingEntryPrice ?? context.spotPrice
        // 单股语义对齐 leg.payoffAtExpiration（leg 也是按"每股"算 · 不乘 contractMultiplier）
        // 1 张备兑 = -1 期权 + +1 单位标的 · 实际美元 PnL 整体再乘 contractMultiplier
        let positionSize = quantity

        return OptionStrategy(
            id: "covered-call-\(context.chain.underlyingID)-\(Int(callStrike))",
            name: "备兑开仓 \(Int(callStrike))",
            strategyType: .coveredCall,
            legs: [
                OptionStrategyLeg(contract: shortCall, direction: .short, quantity: quantity, entryPremium: scP),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName,
            underlyingPositionSize: positionSize,
            underlyingEntryPrice: entry
        )
    }

    // MARK: - 保护性看跌

    /// Long Underlying + Long Put(putStrike) · 持有标的 · 买 Put 当保险锁定下跌风险
    /// 用法：长期看好但担忧短期回撤 · 下方亏损被锁在 (entryPrice - putStrike + putPremium)
    public static func protectivePut(
        context: Context,
        putStrike: Double,
        expiration: Date,
        underlyingEntryPrice: Double? = nil,
        quantity: Int = 1
    ) -> OptionStrategy? {
        guard let slice = context.chain.slice(for: expiration),
              let longPut = findContract(slice: slice, type: .put, strike: putStrike)
        else { return nil }

        let lpP = theoreticalPrice(contract: longPut, context: context)
        let entry = underlyingEntryPrice ?? context.spotPrice
        let positionSize = quantity     // 单股语义 · 同 coveredCall

        return OptionStrategy(
            id: "protective-put-\(context.chain.underlyingID)-\(Int(putStrike))",
            name: "保护性看跌 \(Int(putStrike))",
            strategyType: .protectivePut,
            legs: [
                OptionStrategyLeg(contract: longPut, direction: .long, quantity: quantity, entryPremium: lpP),
            ],
            underlyingID: context.chain.underlyingID,
            underlyingName: context.chain.underlyingName,
            underlyingPositionSize: positionSize,
            underlyingEntryPrice: entry
        )
    }

    // MARK: - private helpers

    /// 查找指定 (type, strike) 的合约 · strike 容差 0.01
    private static func findContract(
        slice: OptionChainSlice, type: OptionType, strike: Double
    ) -> OptionContract? {
        slice.rows.compactMap { row -> OptionContract? in
            let s = NSDecimalNumber(decimal: row.strikePrice).doubleValue
            guard abs(s - strike) < 0.01 else { return nil }
            switch type {
            case .call: return row.call
            case .put:  return row.put
            }
        }.first
    }

    /// 用 BS 理论价代替市价（v1 · v2 接盘口）
    private static func theoreticalPrice(
        contract: OptionContract, context: Context
    ) -> Double {
        let T = Double(contract.daysToExpiration()) / 365.0
        let inputs = BlackScholes.Inputs(
            spotPrice: context.spotPrice,
            strikePrice: NSDecimalNumber(decimal: contract.strikePrice).doubleValue,
            timeToExpirationYears: max(T, 1e-6),
            riskFreeRate: context.riskFreeRate,
            volatility: context.volatility,
            dividendYield: context.dividendYield
        )
        return BlackScholes.price(type: contract.type, inputs: inputs)
    }
}
