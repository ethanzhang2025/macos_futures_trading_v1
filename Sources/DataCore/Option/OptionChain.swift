// 期权链数据结构（v15.28 · 期权全量 Phase 1 · WP-期权 数据层）
//
// 期权链 = 同一标的下所有期权合约的组织视图
//   - 按到期日 (expirationDate) 分组
//   - 同一到期日内按行权价排序
//   - 每行权价配 (CALL, PUT) 双合约 · 形成 T 型表格
//
// 视觉布局：
//   ┌─────────  CALL  ─────────┬──────  STRIKE  ──────┬─────────  PUT  ─────────┐
//   │ ITM ITM ITM ATM OTM OTM │  低 ──→ 高（升序）   │ OTM OTM OTM ATM ITM ITM │
//   └─────────────────────────┴──────────────────────┴─────────────────────────┘
//
// 设计：
//   - OptionChainRow = 单行（strike + call + put + ATM 标记）
//   - OptionChainSlice = 单到期日的完整链
//   - OptionChain = 一个标的的所有到期日链

import Foundation
import Shared

/// 期权链单行（一个 strike + 对应的 call & put · 任一可能为 nil 表示该 strike 未挂）
public struct OptionChainRow: Sendable, Equatable {
    public let strikePrice: Decimal
    public let call: OptionContract?
    public let put: OptionContract?

    /// 该行 strike 距标的现价的相对位置（基于第 1 个非空合约的 relation）
    public func relation(spotPrice: Decimal, atmTolerance: Double = 0.01) -> StrikeRelation {
        // 用 CALL 视角判定（PUT 反之 · 但 strike vs spot 关系一致）
        if let call = call {
            return call.relation(to: spotPrice, atmTolerance: atmTolerance)
        }
        if let put = put {
            // PUT 的 ITM/OTM 与 strike vs spot 反向 · 但 ATM 一致
            switch put.relation(to: spotPrice, atmTolerance: atmTolerance) {
            case .atm: return .atm
            case .itm: return .otm   // PUT.ITM = strike > spot = CALL 视角 OTM
            case .otm: return .itm
            }
        }
        return .atm
    }

    public init(strikePrice: Decimal, call: OptionContract?, put: OptionContract?) {
        self.strikePrice = strikePrice
        self.call = call
        self.put = put
    }
}

/// 单一到期日的期权链（多行 · 按 strike 升序）
public struct OptionChainSlice: Sendable, Equatable {
    public let expirationDate: Date
    public let underlyingID: String
    public let rows: [OptionChainRow]

    /// 距到期天数
    public func daysToExpiration(from now: Date = Date()) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                       to: cal.startOfDay(for: expirationDate))
        return comps.day ?? 0
    }

    /// ATM 行（最贴近现价 · 没有则 nil）
    public func atmRow(spotPrice: Decimal) -> OptionChainRow? {
        guard !rows.isEmpty else { return nil }
        let spot = NSDecimalNumber(decimal: spotPrice).doubleValue
        return rows.min { a, b in
            let da = abs(NSDecimalNumber(decimal: a.strikePrice).doubleValue - spot)
            let db = abs(NSDecimalNumber(decimal: b.strikePrice).doubleValue - spot)
            return da < db
        }
    }

    public init(expirationDate: Date, underlyingID: String, rows: [OptionChainRow]) {
        self.expirationDate = expirationDate
        self.underlyingID = underlyingID
        self.rows = rows
    }
}

/// 完整期权链（一个标的 · 多个到期日 · 按到期日升序）
public struct OptionChain: Sendable, Equatable {
    public let underlyingID: String
    public let underlyingName: String
    public let category: OptionCategory
    public let slices: [OptionChainSlice]   // 按 expirationDate 升序

    public init(
        underlyingID: String, underlyingName: String,
        category: OptionCategory, slices: [OptionChainSlice]
    ) {
        self.underlyingID = underlyingID
        self.underlyingName = underlyingName
        self.category = category
        self.slices = slices
    }

    /// 主力合约月（最近到期日）
    public var nearestExpiration: OptionChainSlice? { slices.first }

    /// 找指定到期日（精确日期匹配）
    public func slice(for expiration: Date) -> OptionChainSlice? {
        let cal = Calendar(identifier: .gregorian)
        let target = cal.startOfDay(for: expiration)
        return slices.first { cal.startOfDay(for: $0.expirationDate) == target }
    }
}

// MARK: - Builder · 从合约列表构建期权链

public enum OptionChainBuilder {

    /// 从扁平合约列表构建期权链
    /// - Parameters:
    ///   - contracts: 单一标的的所有期权合约（多到期日 + CALL + PUT 混合）
    ///   - underlyingName: 标的显示名（构建时附加 · 用于 UI）
    /// - Returns: 期权链 · slices 按到期升序 · rows 按 strike 升序
    public static func build(
        contracts: [OptionContract],
        underlyingName: String? = nil
    ) -> OptionChain? {
        guard let first = contracts.first else { return nil }
        let underlyingID = first.underlyingID
        let category = first.category
        let name = underlyingName ?? first.underlyingName

        // 按到期日分组
        let cal = Calendar(identifier: .gregorian)
        let byExpiration = Dictionary(grouping: contracts, by: { cal.startOfDay(for: $0.expirationDate) })

        let slices: [OptionChainSlice] = byExpiration
            .sorted { $0.key < $1.key }
            .map { (expDay, group) in
                // 同 strike 上 group 出 (call?, put?)
                let byStrike = Dictionary(grouping: group, by: { $0.strikePrice })
                let rows: [OptionChainRow] = byStrike
                    .sorted { $0.key < $1.key }
                    .map { (strike, contracts) in
                        let call = contracts.first { $0.type == .call }
                        let put = contracts.first { $0.type == .put }
                        return OptionChainRow(strikePrice: strike, call: call, put: put)
                    }
                return OptionChainSlice(expirationDate: expDay, underlyingID: underlyingID, rows: rows)
            }

        return OptionChain(
            underlyingID: underlyingID,
            underlyingName: name,
            category: category,
            slices: slices
        )
    }
}
