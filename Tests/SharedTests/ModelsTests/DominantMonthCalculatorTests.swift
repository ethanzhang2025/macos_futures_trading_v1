// DominantMonthCalculator unit tests · v12.16
//
// 验证主力月推断规则与实测吻合（2026-04-29 SinaMonthlyContractDemo · oi 排序）

import Testing
import Foundation
@testable import Shared

@Suite("DominantMonthCalculator · 主力月动态推断")
struct DominantMonthCalculatorTests {

    /// 构造 Asia/Shanghai 的指定日期（避免 UTC 偏移影响月份判断）
    private static func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("2026-04-29 主力月与 SinaMonthlyContractDemo 实测吻合")
    func dominantOn20260429() {
        let d = Self.date(year: 2026, month: 4, day: 29)
        #expect(DominantMonthCalculator.dominantContract(prefix: "rb", on: d) == "rb2609")
        #expect(DominantMonthCalculator.dominantContract(prefix: "i",  on: d) == "i2609")
        #expect(DominantMonthCalculator.dominantContract(prefix: "au", on: d) == "au2606")
        #expect(DominantMonthCalculator.dominantContract(prefix: "IF", on: d) == "IF2605")
    }

    @Test("黑色系 [1,5,9] 跳近 1 月规则")
    func blackSeriesRule() {
        // 1 月 · cutoff 2 · 取 5 月
        let jan = Self.date(year: 2026, month: 1, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "rb", on: jan) == "rb2605")
        // 6 月 · cutoff 7 · 取 9 月
        let jun = Self.date(year: 2026, month: 6, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "rb", on: jun) == "rb2609")
        // 10 月 · cutoff 11 · 当年无 · 取下年 1 月
        let oct = Self.date(year: 2026, month: 10, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "rb", on: oct) == "rb2701")
    }

    @Test("贵金属双月 [2,4,6,8,10,12] 跳近 1 月规则")
    func preciousMetalRule() {
        // 4 月 · cutoff 5 · 取 6 月
        let apr = Self.date(year: 2026, month: 4, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "au", on: apr) == "au2606")
        // 11 月 · cutoff 12 · 当年无 → 取下年 2 月
        let nov = Self.date(year: 2026, month: 11, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "au", on: nov) == "au2702")
    }

    @Test("金融期货月月有 · 不跳近 · 取下月")
    func financialFuturesRule() {
        // 4 月 · cutoff 4 · 取 5 月
        let apr = Self.date(year: 2026, month: 4, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "IF", on: apr) == "IF2605")
        // 12 月 · cutoff 12 · 当年无 → 跨年 1 月
        let dec = Self.date(year: 2026, month: 12, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "IF", on: dec) == "IF2701")
    }

    @Test("有色月月有 · 跳近 1 月")
    func nonferrousRule() {
        // 4 月 · cutoff 5 · 取 6 月
        let apr = Self.date(year: 2026, month: 4, day: 15)
        #expect(DominantMonthCalculator.dominantContract(prefix: "cu", on: apr) == "cu2606")
    }

    @Test("未知品种前缀返 nil")
    func unknownPrefix() {
        let d = Self.date(year: 2026, month: 4, day: 29)
        #expect(DominantMonthCalculator.dominantContract(prefix: "xyz", on: d) == nil)
    }

    @Test("supportedPrefixes 含主流品种")
    func supportedPrefixes() {
        let prefixes = DominantMonthCalculator.supportedPrefixes
        #expect(prefixes.contains("rb"))
        #expect(prefixes.contains("i"))
        #expect(prefixes.contains("au"))
        #expect(prefixes.contains("if"))
        #expect(prefixes.contains("cu"))
    }
}
