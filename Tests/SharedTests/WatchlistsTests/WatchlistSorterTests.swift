// v15.20 batch59 · WatchlistSorter 单测

import Testing
@testable import Shared

@Suite("WatchlistSorter · 自选合约排序")
struct WatchlistSorterTests {

    private let ids = ["RB0", "IF0", "AU0", "CU0"]
    private let prices: [String: Double] = ["RB0": 3850, "IF0": 4250, "AU0": 480, "CU0": 72500]
    private let pcts:   [String: Double] = ["RB0": 1.5, "IF0": -0.8, "AU0": 2.3, "CU0": -1.1]

    private func priceKey(_ id: String) -> Double? { prices[id] }
    private func pctKey(_ id: String) -> Double? { pcts[id] }

    @Test(".manual 保持原序")
    func manual() {
        let result = WatchlistSorter.sort(ids: ids, field: .manual, ascending: true, keyForID: priceKey)
        #expect(result == ids)
        let result2 = WatchlistSorter.sort(ids: ids, field: .manual, ascending: false, keyForID: priceKey)
        #expect(result2 == ids)
    }

    @Test(".instrumentID 字典序升降")
    func instrumentID() {
        let asc = WatchlistSorter.sort(ids: ids, field: .instrumentID, ascending: true, keyForID: priceKey)
        #expect(asc == ["AU0", "CU0", "IF0", "RB0"])
        let desc = WatchlistSorter.sort(ids: ids, field: .instrumentID, ascending: false, keyForID: priceKey)
        #expect(desc == ["RB0", "IF0", "CU0", "AU0"])
    }

    @Test(".lastPrice 升序 / 降序")
    func lastPrice() {
        let asc = WatchlistSorter.sort(ids: ids, field: .lastPrice, ascending: true, keyForID: priceKey)
        #expect(asc == ["AU0", "RB0", "IF0", "CU0"])    // 480 / 3850 / 4250 / 72500
        let desc = WatchlistSorter.sort(ids: ids, field: .lastPrice, ascending: false, keyForID: priceKey)
        #expect(desc == ["CU0", "IF0", "RB0", "AU0"])
    }

    @Test(".changePct 升序（跌幅榜）/ 降序（涨幅榜）")
    func changePct() {
        let asc = WatchlistSorter.sort(ids: ids, field: .changePct, ascending: true, keyForID: pctKey)
        #expect(asc == ["CU0", "IF0", "RB0", "AU0"])    // -1.1 / -0.8 / 1.5 / 2.3
        let desc = WatchlistSorter.sort(ids: ids, field: .changePct, ascending: false, keyForID: pctKey)
        #expect(desc == ["AU0", "RB0", "IF0", "CU0"])
    }

    @Test("nil key 始终排末尾（无关升降序）")
    func nilKey() {
        let partial: [String: Double] = ["RB0": 3850, "IF0": 4250]   // AU0/CU0 → nil
        let asc = WatchlistSorter.sort(ids: ids, field: .lastPrice, ascending: true, keyForID: { partial[$0] })
        #expect(asc == ["RB0", "IF0", "AU0", "CU0"])      // 数值在前 · nil 在后
        let desc = WatchlistSorter.sort(ids: ids, field: .lastPrice, ascending: false, keyForID: { partial[$0] })
        #expect(desc == ["IF0", "RB0", "AU0", "CU0"])     // 数值在前 · nil 在后
    }

    @Test("同 key tiebreak 用 instrumentID 字典序")
    func tiebreak() {
        let same: [String: Double] = ["RB0": 100, "IF0": 100, "AU0": 100, "CU0": 100]
        let asc = WatchlistSorter.sort(ids: ids, field: .lastPrice, ascending: true, keyForID: { same[$0] })
        #expect(asc == ["AU0", "CU0", "IF0", "RB0"])
    }

    @Test("空数组 / 单元素安全")
    func edgeCases() {
        #expect(WatchlistSorter.sort(ids: [], field: .lastPrice, ascending: true, keyForID: priceKey) == [])
        #expect(WatchlistSorter.sort(ids: ["RB0"], field: .changePct, ascending: false, keyForID: pctKey) == ["RB0"])
    }

    @Test("displayName 中文化")
    func displayNames() {
        #expect(WatchlistSortField.manual.displayName == "手动")
        #expect(WatchlistSortField.instrumentID.displayName == "合约")
        #expect(WatchlistSortField.lastPrice.displayName == "最新价")
        #expect(WatchlistSortField.changePct.displayName == "涨跌幅")
        #expect(WatchlistSortField.openInterest.displayName == "持仓量")
        // v17.33 C4
        #expect(WatchlistSortField.spread.displayName == "买卖价差")
    }

    // v17.33 C4 · spread 字段升降序
    @Test(".spread 升序（窄价差优先）/ 降序（宽价差优先）")
    func spreadOrdering() {
        // 模拟价差%：A=0.05 B=0.20 C=0.10 → 升序 A→C→B
        let spreads: [String: Double] = ["A": 0.05, "B": 0.20, "C": 0.10]
        let ids = ["A", "B", "C"]
        let asc = WatchlistSorter.sort(ids: ids, field: .spread, ascending: true, keyForID: { spreads[$0] })
        #expect(asc == ["A", "C", "B"])
        let desc = WatchlistSorter.sort(ids: ids, field: .spread, ascending: false, keyForID: { spreads[$0] })
        #expect(desc == ["B", "C", "A"])
    }

    @Test(".spread nil key（无 Bid/Ask 数据合约）排末尾")
    func spreadNilFallsToEnd() {
        let spreads: [String: Double?] = ["A": 0.05, "B": nil, "C": 0.10]
        let asc = WatchlistSorter.sort(ids: ["A", "B", "C"], field: .spread, ascending: true, keyForID: { spreads[$0] ?? nil })
        #expect(asc == ["A", "C", "B"])
    }
}
