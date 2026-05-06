// WP-54 v15.23 batch2 · 纪律规则评估器（持仓相关规则）
//
// 输入：rules + 持仓上下文 [PositionContext]（含 position + openedAt 开仓时间 + currentPrice）+ now
// 输出：[DisciplineViolation]（按规则触发顺序）
//
// 实现规则（batch2）：
// - stopLossPercent  · 浮亏百分比 ≥ threshold% → error
// - maxHoldingMinutes · 持仓时长 > threshold 分钟 → warning（trader 可能锁仓 · 不算硬违规）
//
// batch3 后续：maxAddPositions / dailyMaxLoss / maxDailyTrades（trades 相关）

import Foundation
import Shared

/// 评估持仓规则所需的上下文（调用方组装 · 一个持仓一条）
public struct PositionContext: Sendable, Equatable {
    public let position: Position
    public let openedAt: Date          // 持仓最早开仓时间（首笔开仓）
    public let currentPrice: Decimal   // 当前合约 lastPrice

    public init(position: Position, openedAt: Date, currentPrice: Decimal) {
        self.position = position
        self.openedAt = openedAt
        self.currentPrice = currentPrice
    }
}

/// 纪律规则评估器（纯函数 · 测试友好 · 不持有状态）
public enum DisciplineEvaluator {

    /// 评估持仓相关规则（stopLossPercent + maxHoldingMinutes）
    /// - rules：候选规则集 · 自动跳过 disabled 与不属于持仓类的 kind
    /// - positions：持仓上下文集合
    /// - now：评估时刻（用于持仓时长 / occurredAt 时间戳 · 测试可注入固定时间）
    public static func evaluatePositions(
        rules: [DisciplineRule],
        positions: [PositionContext],
        now: Date
    ) -> [DisciplineViolation] {
        var result: [DisciplineViolation] = []
        for rule in rules where rule.enabled {
            switch rule.kind {
            case .stopLossPercent:
                result.append(contentsOf: evalStopLoss(rule: rule, positions: positions, now: now))
            case .maxHoldingMinutes:
                result.append(contentsOf: evalHoldingTime(rule: rule, positions: positions, now: now))
            case .maxAddPositions, .dailyMaxLoss, .maxDailyTrades:
                continue  // 走 evaluateTrades
            }
        }
        return result
    }

    /// v15.23 batch3 · 评估 trades 相关规则（maxDailyTrades / dailyMaxLoss / maxAddPositions）
    /// - rules：候选规则集 · 自动跳过 disabled 与不属于 trades 类的 kind
    /// - todayTrades：今日成交记录（调用方按 tradeTime 过滤好）
    /// - dailyRealizedPnL：今日已实现盈亏（盈利为正 · 亏损为负 · 调用方算好）
    /// - now：评估时刻
    public static func evaluateTrades(
        rules: [DisciplineRule],
        todayTrades: [TradeRecord],
        dailyRealizedPnL: Decimal,
        now: Date
    ) -> [DisciplineViolation] {
        var result: [DisciplineViolation] = []
        for rule in rules where rule.enabled {
            switch rule.kind {
            case .maxDailyTrades:
                result.append(contentsOf: evalMaxDailyTrades(rule: rule, trades: todayTrades, now: now))
            case .dailyMaxLoss:
                result.append(contentsOf: evalDailyMaxLoss(rule: rule, dailyPnL: dailyRealizedPnL, now: now))
            case .maxAddPositions:
                result.append(contentsOf: evalMaxAddPositions(rule: rule, trades: todayTrades, now: now))
            case .stopLossPercent, .maxHoldingMinutes:
                continue  // 走 evaluatePositions
            }
        }
        return result
    }

    // MARK: - 单规则实现

    private static func evalStopLoss(rule: DisciplineRule,
                                     positions: [PositionContext],
                                     now: Date) -> [DisciplineViolation] {
        var result: [DisciplineViolation] = []
        for ctx in positions {
            let pos = ctx.position
            let pnl = pos.floatingPnL(currentPrice: ctx.currentPrice)
            // principal 用开仓均价×手数×合约乘数（持仓本金 · 不含保证金折扣）
            let principal = pos.openAvgPrice * Decimal(pos.volume) * Decimal(pos.volumeMultiple)
            guard principal > 0 else { continue }
            // 亏损率（盈利时为负数 · 仅亏损时检查阈值）
            let lossPercent = (-pnl) / principal * 100
            guard lossPercent >= rule.threshold else { continue }
            let msg = "\(pos.instrumentID) \(pos.direction.displayName)单 浮亏 \(formatDecimal2(lossPercent))% 超过止损线 \(formatDecimal2(rule.threshold))%"
            result.append(DisciplineViolation(
                ruleID: rule.id,
                ruleKind: rule.kind,
                occurredAt: now,
                severity: .error,
                message: msg
            ))
        }
        return result
    }

    private static func evalHoldingTime(rule: DisciplineRule,
                                        positions: [PositionContext],
                                        now: Date) -> [DisciplineViolation] {
        var result: [DisciplineViolation] = []
        let thresholdMinutes = (rule.threshold as NSDecimalNumber).doubleValue
        for ctx in positions {
            let elapsedMinutes = now.timeIntervalSince(ctx.openedAt) / 60
            guard elapsedMinutes > thresholdMinutes else { continue }
            let pos = ctx.position
            let msg = "\(pos.instrumentID) \(pos.direction.displayName)单 持仓 \(Int(elapsedMinutes)) 分钟 超过 \(Int(thresholdMinutes)) 分钟上限"
            result.append(DisciplineViolation(
                ruleID: rule.id,
                ruleKind: rule.kind,
                occurredAt: now,
                severity: .warning,
                message: msg
            ))
        }
        return result
    }

    // MARK: - trades 类规则（batch3）

    private static func evalMaxDailyTrades(rule: DisciplineRule,
                                           trades: [TradeRecord],
                                           now: Date) -> [DisciplineViolation] {
        let count = trades.count
        let threshold = (rule.threshold as NSDecimalNumber).intValue
        guard count > threshold else { return [] }
        return [DisciplineViolation(
            ruleID: rule.id,
            ruleKind: rule.kind,
            occurredAt: now,
            severity: .warning,
            message: "今日已交易 \(count) 笔 超过上限 \(threshold) 笔",
            relatedOrderRefs: trades.map { $0.orderRef }
        )]
    }

    private static func evalDailyMaxLoss(rule: DisciplineRule,
                                         dailyPnL: Decimal,
                                         now: Date) -> [DisciplineViolation] {
        let lossAmount = -dailyPnL  // 盈利为负 · 亏损为正
        guard lossAmount >= rule.threshold else { return [] }
        return [DisciplineViolation(
            ruleID: rule.id,
            ruleKind: rule.kind,
            occurredAt: now,
            severity: .error,
            message: "今日累计亏损 \(formatDecimal2(lossAmount)) 元 超过上限 \(formatDecimal2(rule.threshold)) 元"
        )]
    }

    /// 同合约同方向连续开仓累计 · 平仓清零（避免开-平-开-平也算"加仓"）
    private static func evalMaxAddPositions(rule: DisciplineRule,
                                            trades: [TradeRecord],
                                            now: Date) -> [DisciplineViolation] {
        var counts: [String: Int] = [:]   // key = "instrumentID:directionRaw"
        for trade in trades {
            let key = "\(trade.instrumentID):\(trade.direction.rawValue)"
            if trade.offsetFlag == .open {
                counts[key, default: 0] += 1
            } else {
                counts[key] = 0   // 平仓清零（含 close/closeToday/closeYesterday/forceClose）
            }
        }
        let threshold = (rule.threshold as NSDecimalNumber).intValue
        var result: [DisciplineViolation] = []
        for (key, count) in counts where count > threshold {
            let parts = key.split(separator: ":")
            let instrumentID = parts.first.map(String.init) ?? "unknown"
            let dirRaw = parts.count > 1 ? String(parts[1]) : ""
            let dirText = Direction(rawValue: dirRaw)?.displayName ?? dirRaw
            result.append(DisciplineViolation(
                ruleID: rule.id,
                ruleKind: rule.kind,
                occurredAt: now,
                severity: .warning,
                message: "\(instrumentID) \(dirText) 当日加仓 \(count) 次 超过上限 \(threshold) 次"
            ))
        }
        return result
    }

    /// 格式化 Decimal 保留 2 位小数（用于消息文案）
    private static func formatDecimal2(_ d: Decimal) -> String {
        String(format: "%.2f", (d as NSDecimalNumber).doubleValue)
    }
}
