// 期权合约模型（v15.28 · 期权全量 Phase 1 · WP-期权 数据层）
//
// 范围：中国期货 + ETF 期权（沪深商品 + 中金股指 + 上证 ETF）
// Phase 1：纯模型 · 不含 Greeks / IV / 策略组合（Phase 2-4）
//
// 设计：
//   - OptionContract = 单合约元数据（CALL/PUT + 行权价 + 到期 + 标的）
//   - OptionType（看涨/看跌）· ExerciseStyle（美式/欧式）
//   - OptionCategory（标的分类 · ETF / 股指 / 商品）
//   - StrikeRelation（实值 ITM / 平值 ATM / 虚值 OTM）· 与现价比较 · 计算属性

import Foundation
import Shared

/// 期权类型
public enum OptionType: String, Sendable, Codable, CaseIterable {
    case call = "CALL"   // 看涨
    case put  = "PUT"    // 看跌

    public var displayName: String {
        switch self {
        case .call: return "认购"
        case .put:  return "认沽"
        }
    }
}

/// 行权方式
public enum ExerciseStyle: String, Sendable, Codable, CaseIterable {
    case american = "AMERICAN"   // 美式（任意时点行权）
    case european = "EUROPEAN"   // 欧式（仅到期日行权）

    public var displayName: String {
        switch self {
        case .american: return "美式"
        case .european: return "欧式"
        }
    }
}

/// 标的分类
public enum OptionCategory: String, Sendable, Codable, CaseIterable {
    case etf       = "ETF期权"          // 50ETF / 300ETF / 500ETF
    case stockIndex = "股指期权"        // 沪深300 / 中证1000
    case commodity = "商品期权"          // 豆粕 / 白糖 / 铜 / 黄金 / 原油 等

    public var displayName: String { rawValue }
}

/// 行权价 vs 现价 关系
public enum StrikeRelation: String, Sendable, Codable, CaseIterable {
    case itm = "ITM"   // In The Money 实值
    case atm = "ATM"   // At The Money 平值
    case otm = "OTM"   // Out of The Money 虚值

    public var displayName: String {
        switch self {
        case .itm: return "实值"
        case .atm: return "平值"
        case .otm: return "虚值"
        }
    }
}

/// 期权合约（v1 不要 Codable · 因 Exchange enum 不 conform · v2 接 CTP 持久化时再扩）
public struct OptionContract: Sendable, Equatable, Identifiable, Hashable {
    /// 合约 ID（如 "510050C2509M03000" 50ETF 9月 3000 认购 / "m2509-C-3500" 豆粕期权）
    public let id: String
    /// 标的合约 ID（如 "510050" / "IF2509" / "m2509"）
    public let underlyingID: String
    /// 标的名称（"50ETF" / "沪深300" / "豆粕"）
    public let underlyingName: String
    /// 期权类型
    public let type: OptionType
    /// 行权价（Decimal 精度 · 与现价同量纲）
    public let strikePrice: Decimal
    /// 到期日（YYYY-MM-DD · 行权日通常是当月第 4 个周三 ETF / 第 3 个周五股指）
    public let expirationDate: Date
    /// 行权方式
    public let exerciseStyle: ExerciseStyle
    /// 合约乘数（每张合约对应标的数量 · ETF 期权一般 10000 / 股指 100 / 豆粕 10）
    public let contractMultiplier: Int
    /// 标的分类
    public let category: OptionCategory
    /// 交易所（继承自 Exchange）
    public let exchange: Exchange
    /// 是否在交易（已摘牌 = false）
    public let isTrading: Bool

    public init(
        id: String, underlyingID: String, underlyingName: String,
        type: OptionType, strikePrice: Decimal, expirationDate: Date,
        exerciseStyle: ExerciseStyle, contractMultiplier: Int,
        category: OptionCategory, exchange: Exchange,
        isTrading: Bool = true
    ) {
        self.id = id
        self.underlyingID = underlyingID
        self.underlyingName = underlyingName
        self.type = type
        self.strikePrice = strikePrice
        self.expirationDate = expirationDate
        self.exerciseStyle = exerciseStyle
        self.contractMultiplier = contractMultiplier
        self.category = category
        self.exchange = exchange
        self.isTrading = isTrading
    }

    /// 距到期日剩余天数（自然日）
    public func daysToExpiration(from now: Date = Date()) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                            to: calendar.startOfDay(for: expirationDate))
        return comps.day ?? 0
    }

    /// 是否已到期
    public var isExpired: Bool { daysToExpiration() <= 0 }

    /// 与现价比较 · 返回实/平/虚值标签
    /// 平值阈值（pivotTolerance）：行权价 ± 1% 现价区间内视作 ATM · 套用券商常见约定
    public func relation(to spotPrice: Decimal, atmTolerance: Double = 0.01) -> StrikeRelation {
        guard spotPrice > 0 else { return .atm }
        let spot = NSDecimalNumber(decimal: spotPrice).doubleValue
        let strike = NSDecimalNumber(decimal: strikePrice).doubleValue
        let diff = abs(strike - spot) / spot
        if diff <= atmTolerance { return .atm }
        switch type {
        case .call: return strike < spot ? .itm : .otm
        case .put:  return strike > spot ? .itm : .otm
        }
    }

    /// 内在价值（intrinsic value · 不考虑时间价值）
    /// CALL: max(spot - strike, 0)
    /// PUT:  max(strike - spot, 0)
    public func intrinsicValue(spotPrice: Decimal) -> Decimal {
        switch type {
        case .call: return Swift.max(spotPrice - strikePrice, 0)
        case .put:  return Swift.max(strikePrice - spotPrice, 0)
        }
    }
}
