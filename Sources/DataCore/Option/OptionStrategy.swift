// 期权策略组合（v15.31 · 期权 Phase 4 · WP-期权 策略层）
//
// 设计：
//   - OptionStrategyLeg = (合约 + Long/Short + 数量 + 入场权利金)
//   - OptionStrategy = 多 leg 组合 + 名称 + 分类
//   - 经典策略由 OptionStrategyBuilder 一键构造（牛熊价差 / 宽跨式 / 蝶式）

import Foundation

/// 头寸方向
public enum StrategyDirection: String, Sendable, Codable, CaseIterable {
    case long  = "LONG"   // 买方（付权利金）
    case short = "SHORT"  // 卖方（收权利金）

    public var displayName: String {
        switch self {
        case .long: return "买入"
        case .short: return "卖出"
        }
    }

    public var sign: Double {
        switch self {
        case .long: return 1
        case .short: return -1
        }
    }
}

/// 单 leg
public struct OptionStrategyLeg: Sendable, Equatable {
    public let contract: OptionContract
    public let direction: StrategyDirection
    public let quantity: Int                 // 张数（始终正值 · 方向由 direction 决定）
    public let entryPremium: Double          // 入场权利金（每张 · 不含手续费）

    public init(contract: OptionContract, direction: StrategyDirection,
                quantity: Int, entryPremium: Double) {
        self.contract = contract
        self.direction = direction
        self.quantity = quantity
        self.entryPremium = entryPremium
    }

    /// 到期 PnL（按单股 · 不计乘数 · 用单价比较）
    public func payoffAtExpiration(spotPrice: Double) -> Double {
        let strike = NSDecimalNumber(decimal: contract.strikePrice).doubleValue
        let intrinsic: Double
        switch contract.type {
        case .call: intrinsic = max(spotPrice - strike, 0)
        case .put:  intrinsic = max(strike - spotPrice, 0)
        }
        // long: 收 intrinsic - 付 premium
        // short: 收 premium - 付 intrinsic
        return direction.sign * (intrinsic - entryPremium) * Double(quantity)
    }
}

/// 完整策略
public struct OptionStrategy: Sendable, Equatable {
    public let id: String                    // "bull-spread-IO-3500-3600" 等
    public let name: String                  // "牛市看涨价差"
    public let strategyType: StrategyType
    public let legs: [OptionStrategyLeg]
    public let underlyingID: String
    public let underlyingName: String

    public init(id: String, name: String, strategyType: StrategyType,
                legs: [OptionStrategyLeg], underlyingID: String, underlyingName: String) {
        self.id = id
        self.name = name
        self.strategyType = strategyType
        self.legs = legs
        self.underlyingID = underlyingID
        self.underlyingName = underlyingName
    }

    /// 净权利金（多腿 - 空腿 · 正 = 净付出 · 负 = 净收入）
    public var netPremium: Double {
        legs.reduce(0) { acc, leg in
            acc + leg.direction.sign * leg.entryPremium * Double(leg.quantity)
        }
    }

    /// 到期 PnL · 在指定标的价 S 下的总损益
    public func payoffAtExpiration(spotPrice: Double) -> Double {
        legs.reduce(0) { $0 + $1.payoffAtExpiration(spotPrice: spotPrice) }
    }

    /// 涉及到的所有 strike（去重 · 升序）
    public var distinctStrikes: [Double] {
        let strikes = legs.map { NSDecimalNumber(decimal: $0.contract.strikePrice).doubleValue }
        return Array(Set(strikes)).sorted()
    }
}

/// 策略类型
public enum StrategyType: String, Sendable, Codable, CaseIterable {
    case bullCallSpread  = "BULL_CALL_SPREAD"   // 牛市看涨价差
    case bearPutSpread   = "BEAR_PUT_SPREAD"    // 熊市看跌价差
    case longStraddle    = "LONG_STRADDLE"      // 长跨式（同 strike）
    case longStrangle    = "LONG_STRANGLE"      // 长宽跨式（不同 strike）
    case longButterfly   = "LONG_BUTTERFLY"     // 蝶式（3 strike）
    case ironCondor      = "IRON_CONDOR"        // 铁鹰（4 strike · 4 leg）
    case custom          = "CUSTOM"             // 自定义

    public var displayName: String {
        switch self {
        case .bullCallSpread: return "牛市看涨价差"
        case .bearPutSpread:  return "熊市看跌价差"
        case .longStraddle:   return "长跨式"
        case .longStrangle:   return "长宽跨式"
        case .longButterfly:  return "蝶式"
        case .ironCondor:     return "铁鹰"
        case .custom:         return "自定义"
        }
    }
}
