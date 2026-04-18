import Foundation
import Shared

/// Alpha 样机用假撮合引擎：下单 300ms 回成交、持仓按合约+方向聚合、账户资金联动
@MainActor
final class MockTradingService: ObservableObject {
    @Published var orders: [OrderRecord] = []
    @Published var positions: [Position] = []
    @Published var account: Account = Account(
        preBalance: 1_000_000,
        deposit: 0,
        withdraw: 0,
        closePnL: 0,
        positionPnL: 0,
        commission: 0,
        margin: 0
    )

    private let volumeMultiple = 10
    private let marginRate: Decimal = 0.10
    private let commissionPerLot: Decimal = 5
    private var orderSeq: Int = 0

    // MARK: - 下单

    func placeOrder(symbol: String, direction: Direction, offsetFlag: OffsetFlag, price: Decimal, volume: Int) {
        orderSeq += 1
        let ref = String(format: "%06d", orderSeq)
        let time = Self.timeNow()
        let record = OrderRecord(
            orderRef: ref,
            instrumentID: symbol,
            direction: direction,
            offsetFlag: offsetFlag,
            price: price,
            totalVolume: volume,
            filledVolume: 0,
            status: .submitted,
            insertTime: time,
            statusMessage: "已报"
        )
        orders.insert(record, at: 0)

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            self.fillOrder(ref: ref)
        }
    }

    private func fillOrder(ref: String) {
        guard let idx = orders.firstIndex(where: { $0.orderRef == ref }) else { return }
        var order = orders[idx]
        order.filledVolume = order.totalVolume
        order.status = .filled
        order.statusMessage = "全部成交"
        orders[idx] = order

        applyTrade(
            symbol: order.instrumentID,
            direction: order.direction,
            offsetFlag: order.offsetFlag,
            price: order.price,
            volume: order.totalVolume
        )
    }

    // MARK: - 持仓&账户变更

    private func applyTrade(symbol: String, direction: Direction, offsetFlag: OffsetFlag, price: Decimal, volume: Int) {
        let posDirection: PositionDirection = direction == .buy ? .long : .short
        let fee = commissionPerLot * Decimal(volume)
        account.commission += fee

        if offsetFlag == .open {
            openPosition(symbol: symbol, direction: posDirection, price: price, volume: volume)
        } else {
            closePosition(symbol: symbol, closeDirection: posDirection, price: price, volume: volume)
        }
        recalcMargin()
    }

    private func openPosition(symbol: String, direction: PositionDirection, price: Decimal, volume: Int) {
        if let idx = positions.firstIndex(where: { $0.instrumentID == symbol && $0.direction == direction }) {
            var p = positions[idx]
            let totalCost = p.avgPrice * Decimal(p.volume) + price * Decimal(volume)
            let newVolume = p.volume + volume
            p.avgPrice = totalCost / Decimal(newVolume)
            p.openAvgPrice = p.avgPrice
            p.volume = newVolume
            p.todayVolume += volume
            positions[idx] = p
        } else {
            positions.append(Position(
                instrumentID: symbol,
                direction: direction,
                volume: volume,
                todayVolume: volume,
                avgPrice: price,
                openAvgPrice: price,
                preSettlementPrice: price,
                margin: 0,
                volumeMultiple: volumeMultiple
            ))
        }
    }

    /// 平仓：closeDirection 表示"本次下单的方向"（买平空/卖平多），所以要反向找持仓
    private func closePosition(symbol: String, closeDirection: PositionDirection, price: Decimal, volume: Int) {
        let targetDirection: PositionDirection = closeDirection == .long ? .short : .long
        guard let idx = positions.firstIndex(where: { $0.instrumentID == symbol && $0.direction == targetDirection }) else { return }
        var p = positions[idx]
        let closeVolume = min(p.volume, volume)
        let diff: Decimal = targetDirection == .long ? (price - p.openAvgPrice) : (p.openAvgPrice - price)
        let pnl = diff * Decimal(closeVolume) * Decimal(volumeMultiple)
        account.closePnL += pnl
        p.volume -= closeVolume
        p.todayVolume = max(0, p.todayVolume - closeVolume)
        if p.volume == 0 {
            positions.remove(at: idx)
        } else {
            positions[idx] = p
        }
    }

    // MARK: - 快捷操作

    /// 一键平仓
    func flatten(_ position: Position, currentPrice: Decimal) {
        let direction: Direction = position.direction == .long ? .sell : .buy
        placeOrder(
            symbol: position.instrumentID,
            direction: direction,
            offsetFlag: .close,
            price: currentPrice,
            volume: position.volume
        )
    }

    /// 一键反手：先平仓再反向开同手数
    func reverse(_ position: Position, currentPrice: Decimal) {
        let closeDir: Direction = position.direction == .long ? .sell : .buy
        let openDir: Direction = position.direction == .long ? .sell : .buy
        let volume = position.volume
        placeOrder(
            symbol: position.instrumentID,
            direction: closeDir,
            offsetFlag: .close,
            price: currentPrice,
            volume: volume
        )
        placeOrder(
            symbol: position.instrumentID,
            direction: openDir,
            offsetFlag: .open,
            price: currentPrice,
            volume: volume
        )
    }

    // MARK: - 盯市&风控

    /// 按最新行情刷新持仓浮盈和保证金占用
    func refreshPnL(quotes: [String: Decimal]) {
        var total: Decimal = 0
        for i in positions.indices {
            let price = quotes[positions[i].instrumentID] ?? positions[i].openAvgPrice
            total += positions[i].floatingPnL(currentPrice: price)
        }
        account.positionPnL = total
        recalcMargin(currentPrices: quotes)
    }

    private func recalcMargin(currentPrices: [String: Decimal] = [:]) {
        var total: Decimal = 0
        for i in positions.indices {
            let price = currentPrices[positions[i].instrumentID] ?? positions[i].openAvgPrice
            let m = price * Decimal(positions[i].volume) * Decimal(volumeMultiple) * marginRate
            positions[i].margin = m
            total += m
        }
        account.margin = total
    }

    // MARK: - helpers

    private static func timeNow() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: Date())
    }
}
