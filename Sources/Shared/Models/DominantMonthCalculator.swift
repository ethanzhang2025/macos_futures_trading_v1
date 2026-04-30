// DominantMonthCalculator · 主力月合约动态推断（v12.16 · 解决 v12.2 active 月份硬编码半年交割失效问题）
//
// 实测验证（2026-04-29 SinaMonthlyContractDemo · oi 排序）：
//   rb 主力 = rb2609（[1,5,9] 跳近 1 月 → 9 月）✓
//   i  主力 = i2609（[1,5,9] 跳近 1 月 → 9 月 · oi=591977）✓
//   au 主力 = au2606（[2,4,6,8,10,12] 跳近 1 月 → 6 月）✓
//   IF 主力 = IF2605（金融期货取最近月 · 4 月 → 5 月）✓
//
// 规则按品种维护 · 半年自动续期（rb2609 在 2026-09 交割后自动切 rb2701 等）
// 中国期货真实主力月规则非完全月份模板 · 真值看 oi · 此规则是经验近似（90%+ 场景准确）

import Foundation

public enum DominantMonthCalculator {

    /// 推断当前主力月合约代码（小写前缀通常 · IF/IC/IM/IH 大写）
    /// - prefix: 合约前缀（"rb" / "i" / "au" / "IF" 等）
    /// - date: 推断基准日（默认今天）
    /// - returns: 主力月合约代码（如 "rb2609" / "IF2605"）· 未知前缀返 nil
    public static func dominantContract(prefix: String, on date: Date = Date()) -> String? {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }

        let key = prefix.lowercased()
        guard let rule = MonthlyRule.rules[key] else { return nil }

        let dominant = rule.findNext(year: year, currentMonth: month)
        let yy = dominant.year % 100
        return String(format: "%@%02d%02d", prefix, yy, dominant.month)
    }

    /// 已知支持品种前缀清单（按主力月规则维护范围）
    public static var supportedPrefixes: [String] {
        Array(MonthlyRule.rules.keys).sorted()
    }
}

/// 主力月规则（按品种区分）
private struct MonthlyRule {
    let allowedMonths: [Int]   // 该品种允许挂牌的月份（如 [1,5,9]）
    let skipNearMonths: Int    // 跳过近 N 个月（避开即将交割合约 · 取流动性远月）

    /// 找当前年 (currentMonth + skip) 之后的第一个 allowed 月 · 跨年时取下年第一个 allowed 月
    func findNext(year: Int, currentMonth: Int) -> (year: Int, month: Int) {
        let cutoff = currentMonth + skipNearMonths
        if let next = allowedMonths.first(where: { $0 > cutoff }) {
            return (year, next)
        }
        return (year + 1, allowedMonths.first ?? 1)
    }

    static let rules: [String: MonthlyRule] = [
        // 黑色系（[1,5,9] 主力月 · 跳近 1 月避开交割）
        "rb": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "hc": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "i":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "j":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "jm": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),

        // 农产品 · 化工
        "m":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "y":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "p":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "c":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "a":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "sr": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "cf": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "ta": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "ma": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "eg": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "v":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "pp": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "eb": .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),
        "l":  .init(allowedMonths: [1, 5, 9], skipNearMonths: 1),

        // 贵金属（双月 [2,4,6,8,10,12] 主力 · 跳近 1 月）
        "au": .init(allowedMonths: [2, 4, 6, 8, 10, 12], skipNearMonths: 1),
        "ag": .init(allowedMonths: [2, 4, 6, 8, 10, 12], skipNearMonths: 1),

        // 有色（月月有合约 · 主力通常下月或近月 · 跳近 1 月避开交割）
        "cu": .init(allowedMonths: Array(1...12), skipNearMonths: 1),
        "al": .init(allowedMonths: Array(1...12), skipNearMonths: 1),
        "zn": .init(allowedMonths: Array(1...12), skipNearMonths: 1),
        "pb": .init(allowedMonths: Array(1...12), skipNearMonths: 1),
        "sn": .init(allowedMonths: Array(1...12), skipNearMonths: 1),
        "ni": .init(allowedMonths: Array(1...12), skipNearMonths: 1),

        // 原油（双月 + 跳近）
        "sc": .init(allowedMonths: [2, 4, 6, 8, 10, 12], skipNearMonths: 1),

        // 金融期货（月月有 · 主力为最近月 · 不跳近）
        "if": .init(allowedMonths: Array(1...12), skipNearMonths: 0),
        "ic": .init(allowedMonths: Array(1...12), skipNearMonths: 0),
        "im": .init(allowedMonths: Array(1...12), skipNearMonths: 0),
        "ih": .init(allowedMonths: Array(1...12), skipNearMonths: 0),
    ]
}
