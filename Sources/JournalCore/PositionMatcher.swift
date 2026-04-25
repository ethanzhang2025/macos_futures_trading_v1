// WP-50 模块 1 · 开平仓 FIFO 配对算法
// 目的：把 [Trade] 按 (instrumentID, side) 维度的 FIFO 队列配对成 [ClosedPosition]
//
// 算法：
// 1. 按 timestamp 升序遍历 trades
// 2. 按 (instrumentID, 推导 side) 维护 FIFO 开仓队列
// 3. 平仓 trade 来时，从对应 (合约, 反向) 队列头部取开仓，按手数配对
// 4. 多余手数（部分平仓）→ 拆 ClosedPosition + 队首开仓剩余手数累减
//
// side 推导：
// - buy-open / sell-close → long position
// - sell-open / buy-close → short position
//
// 部分配对：单 trade 可能被拆成多个 ClosedPosition（与多个开仓配对）
// 未平仓部分：队列尾留剩余 OpenLot，不进 ClosedPosition

import Foundation
import Shared

public enum PositionMatcher {

    /// 把 trades 按 FIFO 配对成 ClosedPosition
    /// - Parameters:
    ///   - trades: 全量 trades（无需预排序）
    ///   - multipliers: instrumentID → volumeMultiple 字典；缺失则 PnL 用 1 倍计算（fallback）
    /// - Returns: 闭合持仓列表（按 closeTime 升序）+ 未平仓手数（按 (instrumentID, side) 聚合）
    public static func match(
        trades: [Trade],
        multipliers: [String: Int] = [:]
    ) -> (closed: [ClosedPosition], openRemaining: [OpenRemaining]) {
        let sorted = trades.sorted { $0.timestamp < $1.timestamp }
        var queues: [QueueKey: [OpenLot]] = [:]
        var closed: [ClosedPosition] = []

        for trade in sorted {
            let openSide = openSide(for: trade)
            let closeSide = closeSide(for: trade)

            if let openSide = openSide {
                // 开仓 → 入队
                let key = QueueKey(instrumentID: trade.instrumentID, side: openSide)
                queues[key, default: []].append(OpenLot(trade: trade, remainingVolume: trade.volume))
            } else if let closeSide = closeSide {
                // 平仓 → 配对队首
                let key = QueueKey(instrumentID: trade.instrumentID, side: closeSide)
                var remainingClose = trade.volume
                let multiplier = multipliers[trade.instrumentID] ?? 1
                while remainingClose > 0, var head = queues[key]?.first {
                    let matchVolume = min(head.remainingVolume, remainingClose)
                    let position = makePosition(
                        openLot: head,
                        closeTrade: trade,
                        matchVolume: matchVolume,
                        side: closeSide,
                        multiplier: multiplier
                    )
                    closed.append(position)

                    head.remainingVolume -= matchVolume
                    remainingClose -= matchVolume
                    if head.remainingVolume == 0 {
                        queues[key]?.removeFirst()
                    } else {
                        queues[key]?[0] = head
                    }
                }
                // 多余 close（无对应开仓）静默丢弃；caller 想知可看 closed.totalVolume vs trade.volume
            }
        }

        let openRemaining = queues
            .flatMap { key, lots in
                lots.map { OpenRemaining(instrumentID: key.instrumentID, side: key.side, openTradeID: $0.trade.id, remainingVolume: $0.remainingVolume) }
            }
            .sorted { ($0.instrumentID, $0.openTradeID.uuidString) < ($1.instrumentID, $1.openTradeID.uuidString) }

        return (closed.sorted { $0.closeTime < $1.closeTime }, openRemaining)
    }

    // MARK: - 私有

    private struct QueueKey: Hashable {
        let instrumentID: String
        let side: PositionSide
    }

    private struct OpenLot {
        let trade: Trade
        var remainingVolume: Int
    }

    /// 开仓方向：buy-open → long / sell-open → short / 否则 nil
    private static func openSide(for trade: Trade) -> PositionSide? {
        guard trade.offsetFlag == .open else { return nil }
        return trade.direction == .buy ? .long : .short
    }

    /// 平仓方向：sell-close → long / buy-close → short / 否则 nil
    private static func closeSide(for trade: Trade) -> PositionSide? {
        switch trade.offsetFlag {
        case .close, .closeToday, .closeYesterday, .forceClose:
            return trade.direction == .sell ? .long : .short
        case .open:
            return nil
        }
    }

    private static func makePosition(
        openLot: OpenLot,
        closeTrade: Trade,
        matchVolume: Int,
        side: PositionSide,
        multiplier: Int
    ) -> ClosedPosition {
        let openTrade = openLot.trade
        // 手续费按比例分摊（开 trade 总手续费 × matchVolume / openTrade.volume）
        let openCommissionShare = openTrade.commission * Decimal(matchVolume) / Decimal(openTrade.volume)
        let closeCommissionShare = closeTrade.commission * Decimal(matchVolume) / Decimal(closeTrade.volume)
        let totalCommission = openCommissionShare + closeCommissionShare

        let pricedVolume = Decimal(matchVolume) * Decimal(multiplier)
        let pnlBeforeFees: Decimal
        switch side {
        case .long:  pnlBeforeFees = (closeTrade.price - openTrade.price) * pricedVolume
        case .short: pnlBeforeFees = (openTrade.price - closeTrade.price) * pricedVolume
        }
        let realizedPnL = pnlBeforeFees - totalCommission

        return ClosedPosition(
            instrumentID: openTrade.instrumentID,
            side: side,
            openTradeID: openTrade.id,
            closeTradeID: closeTrade.id,
            openTime: openTrade.timestamp,
            closeTime: closeTrade.timestamp,
            openPrice: openTrade.price,
            closePrice: closeTrade.price,
            volume: matchVolume,
            realizedPnL: realizedPnL,
            totalCommission: totalCommission
        )
    }
}

/// 未平仓剩余（FIFO 队列尾）
public struct OpenRemaining: Sendable, Equatable, Hashable {
    public let instrumentID: String
    public let side: PositionSide
    public let openTradeID: UUID
    public let remainingVolume: Int

    public init(instrumentID: String, side: PositionSide, openTradeID: UUID, remainingVolume: Int) {
        self.instrumentID = instrumentID
        self.side = side
        self.openTradeID = openTradeID
        self.remainingVolume = remainingVolume
    }
}
