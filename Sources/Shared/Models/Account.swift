import Foundation

/// 账户资金信息
public struct Account: Sendable {
    /// 静态权益（上日结算后）
    public var preBalance: Decimal
    /// 当日入金
    public var deposit: Decimal
    /// 当日出金
    public var withdraw: Decimal
    /// 平仓盈亏
    public var closePnL: Decimal
    /// 持仓盈亏
    public var positionPnL: Decimal
    /// 手续费
    public var commission: Decimal
    /// 保证金占用
    public var margin: Decimal

    public init(
        preBalance: Decimal,
        deposit: Decimal,
        withdraw: Decimal,
        closePnL: Decimal,
        positionPnL: Decimal,
        commission: Decimal,
        margin: Decimal
    ) {
        self.preBalance = preBalance
        self.deposit = deposit
        self.withdraw = withdraw
        self.closePnL = closePnL
        self.positionPnL = positionPnL
        self.commission = commission
        self.margin = margin
    }

    /// 动态权益 = 静态权益 + 入金 - 出金 + 平仓盈亏 + 持仓盈亏 - 手续费
    public var balance: Decimal {
        preBalance + deposit - withdraw + closePnL + positionPnL - commission
    }

    /// 可用资金 = 动态权益 - 保证金占用
    public var available: Decimal {
        balance - margin
    }

    /// 风险度 = 保证金占用 / 动态权益 × 100%
    public var riskRatio: Decimal {
        guard balance > 0 else { return 0 }
        return margin / balance * 100
    }
}
