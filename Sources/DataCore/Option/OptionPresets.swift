// 期权品种预设（v15.28 · 期权全量 Phase 1）
//
// 3 个旗舰标的 · 覆盖期货 + 股指期权类目：
//   - 沪深 300 股指期权（IO · 中金所 · 现金交割 · 欧式）
//   - 豆粕期权（m · 大商所 · 商品期权 · 美式）
//   - 白糖期权（SR · 郑商所 · 商品期权 · 美式）
//
// V2 计划：
//   - 扩 Exchange 加 SSE/SZSE → 加 ETF 期权（50ETF/300ETF）
//   - 接 CTP MdApi 拉真实期权 · 替换示例数据
//
// 每个标的下生成示例期权链：
//   - 30 / 60 / 90 天后 3 个到期日（v2 替换为真实月度到期日 · 第 3 周五 / 第 4 周三）
//   - 围绕 ATM ±5 档行权价（共 11 strike）
//   - 每 strike 配 CALL + PUT
//   = 单标的 33 行 × 2 = 66 合约 · 3 标的 = 198 示例合约

import Foundation
import Shared

public enum OptionPresets {

    /// 期权标的描述（生成示例链需要 · 真接行情后从合约目录读）
    public struct UnderlyingMeta: Sendable {
        public let id: String                  // "510050" / "IF0" / "m2509"
        public let name: String                // "50ETF" / "沪深300" / "豆粕"
        public let category: OptionCategory
        public let exchange: Exchange
        public let exerciseStyle: ExerciseStyle
        public let multiplier: Int             // 合约乘数
        public let spotPrice: Decimal          // 当前现价（mock · v2 接真行情）
        public let strikeStep: Decimal         // 行权价档差（不同标的不同 · 50ETF 0.05 / 300ETF 0.1 / 沪深300 50 / 豆粕 50 / 白糖 100）
    }

    /// 3 旗舰标的 meta（v1 不含 ETF 期权 · v2 扩 Exchange 后补）
    public static let underlyings: [UnderlyingMeta] = [
        .init(id: "IO", name: "沪深300", category: .stockIndex, exchange: .CFFEX,
              exerciseStyle: .european, multiplier: 100,
              spotPrice: Decimal(3856), strikeStep: Decimal(50)),
        .init(id: "m", name: "豆粕", category: .commodity, exchange: .DCE,
              exerciseStyle: .american, multiplier: 10,
              spotPrice: Decimal(3180), strikeStep: Decimal(50)),
        .init(id: "SR", name: "白糖", category: .commodity, exchange: .CZCE,
              exerciseStyle: .american, multiplier: 10,
              spotPrice: Decimal(6420), strikeStep: Decimal(100)),
    ]

    /// 按 underlying ID 索引
    public static let byUnderlyingID: [String: UnderlyingMeta] = {
        Dictionary(uniqueKeysWithValues: underlyings.map { ($0.id, $0) })
    }()

    /// 给定标的 + 到期日数组，生成示例期权链（3 到期 · ±5 档 · 每行 CALL+PUT）
    /// - Parameter expirations: 到期日列表（升序）· 默认推 3 个：当月第 4 周三 / 次月 / 下季月
    public static func sampleChain(
        for underlyingID: String,
        expirations: [Date]? = nil,
        from referenceDate: Date = Date(),
        strikesAround: Int = 5
    ) -> OptionChain? {
        guard let meta = byUnderlyingID[underlyingID] else { return nil }
        let dates = expirations ?? defaultExpirations(referenceDate: referenceDate)
        var allContracts: [OptionContract] = []

        // ATM strike = 现价四舍五入到最近的 strikeStep 倍数
        let atmStrike = roundToStep(meta.spotPrice, step: meta.strikeStep)

        for expDate in dates {
            for offset in -strikesAround...strikesAround {
                let strike = atmStrike + Decimal(offset) * meta.strikeStep
                guard strike > 0 else { continue }
                let callID = "\(meta.id)-C-\(strikeShortString(strike))-\(expCode(expDate))"
                let putID  = "\(meta.id)-P-\(strikeShortString(strike))-\(expCode(expDate))"
                allContracts.append(OptionContract(
                    id: callID, underlyingID: meta.id, underlyingName: meta.name,
                    type: .call, strikePrice: strike, expirationDate: expDate,
                    exerciseStyle: meta.exerciseStyle,
                    contractMultiplier: meta.multiplier,
                    category: meta.category, exchange: meta.exchange
                ))
                allContracts.append(OptionContract(
                    id: putID, underlyingID: meta.id, underlyingName: meta.name,
                    type: .put, strikePrice: strike, expirationDate: expDate,
                    exerciseStyle: meta.exerciseStyle,
                    contractMultiplier: meta.multiplier,
                    category: meta.category, exchange: meta.exchange
                ))
            }
        }

        return OptionChainBuilder.build(contracts: allContracts, underlyingName: meta.name)
    }

    // MARK: - private helpers

    /// 默认 3 个到期日（30 / 60 / 90 天后）· 实际应取月度到期日（第 4 周三 / 第 3 周五）· v1 简化
    private static func defaultExpirations(referenceDate: Date) -> [Date] {
        [30, 60, 90].map { referenceDate.addingTimeInterval(TimeInterval($0 * 86400)) }
    }

    /// 把 Decimal 行权价四舍五入到最近的 step 倍数
    private static func roundToStep(_ value: Decimal, step: Decimal) -> Decimal {
        guard step > 0 else { return value }
        var quotient = Decimal()
        var divided = value / step
        NSDecimalRound(&quotient, &divided, 0, .plain)
        return quotient * step
    }

    /// strike 短字符串（"2.85" → "285" / "3500" → "3500"）· ID 生成用
    private static func strikeShortString(_ strike: Decimal) -> String {
        let d = NSDecimalNumber(decimal: strike).doubleValue
        if d < 100 {
            // ETF 期权小数 · 取 2 位小数后乘 100 转整数
            return String(Int(d * 1000))
        }
        return String(Int(d))
    }

    /// 到期日短代码（"YYMMDD"）· ID 用
    private static func expCode(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyMMdd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return f.string(from: date)
    }
}
