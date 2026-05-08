// 行情列表 V2 单测（v15.38 · WatchlistFilter + WatchlistStatistics + Sorter 新字段）

import Foundation
import Testing
@testable import Shared

@Suite("Watchlist V2 · Filter + Statistics + 扩展 Sorter")
struct WatchlistV2Tests {

    // MARK: - 测试辅助

    /// 模拟 quote 表：id → (changePct, volume)
    private func mockData() -> [(id: String, pct: Double, vol: Double)] {
        [
            ("RB0",  +1.5,  500_000),
            ("HC0",  +2.5,  300_000),
            ("CU0",  +9.8,  150_000),    // 涨停
            ("AU0",  -0.3,  200_000),
            ("AG0",  -2.5,   80_000),
            ("M0",   -9.7,  120_000),    // 跌停
            ("Y0",   +5.2,   50_000),
            ("P0",    0.0,   90_000),    // 平盘
            ("IF0",  +0.8,  600_000),    // 高活跃
            ("IH0",  -1.2,   30_000),
        ]
    }

    private func pctClosure(from data: [(id: String, pct: Double, vol: Double)]) -> (String) -> Double? {
        let map = Dictionary(uniqueKeysWithValues: data.map { ($0.id, $0.pct) })
        return { map[$0] }
    }

    private func volClosure(from data: [(id: String, pct: Double, vol: Double)]) -> (String) -> Double? {
        let map = Dictionary(uniqueKeysWithValues: data.map { ($0.id, $0.vol) })
        return { map[$0] }
    }

    // MARK: - WatchlistFilter

    @Test("filter · all preset · 不过滤")
    func filterAll() {
        let data = mockData()
        let ids = data.map { $0.id }
        let result = WatchlistFilter.filter(ids: ids, preset: .all,
                                             changePctForID: pctClosure(from: data))
        #expect(result == ids)
    }

    @Test("filter · gainers2pct · 仅 ≥+2%")
    func filterGainers2() {
        let data = mockData()
        let ids = data.map { $0.id }
        let result = WatchlistFilter.filter(ids: ids, preset: .gainers2pct,
                                             changePctForID: pctClosure(from: data))
        // HC0(+2.5) / CU0(+9.8) / Y0(+5.2)
        #expect(Set(result) == ["HC0", "CU0", "Y0"])
    }

    @Test("filter · losers5pct · 仅 ≤-5%")
    func filterLosers5() {
        let data = mockData()
        let result = WatchlistFilter.filter(ids: data.map(\.id), preset: .losers5pct,
                                             changePctForID: pctClosure(from: data))
        // M0(-9.7) only
        #expect(result == ["M0"])
    }

    @Test("filter · limitUp · 仅 ≥+9.5%")
    func filterLimitUp() {
        let data = mockData()
        let result = WatchlistFilter.filter(ids: data.map(\.id), preset: .limitUp,
                                             changePctForID: pctClosure(from: data))
        #expect(result == ["CU0"])
    }

    @Test("filter · limitDown · 仅 ≤-9.5%")
    func filterLimitDown() {
        let data = mockData()
        let result = WatchlistFilter.filter(ids: data.map(\.id), preset: .limitDown,
                                             changePctForID: pctClosure(from: data))
        #expect(result == ["M0"])
    }

    @Test("filter · extreme · |pct| ≥ 5%")
    func filterExtreme() {
        let data = mockData()
        let result = WatchlistFilter.filter(ids: data.map(\.id), preset: .extreme,
                                             changePctForID: pctClosure(from: data))
        #expect(Set(result) == ["CU0", "M0", "Y0"])
    }

    @Test("filter · active · volume ≥ 阈值")
    func filterActive() {
        let data = mockData()
        let result = WatchlistFilter.filter(
            ids: data.map(\.id), preset: .active,
            volumeForID: volClosure(from: data),
            activeVolumeThreshold: 200_000
        )
        // RB0(500k) / HC0(300k) / AU0(200k = 阈值) / IF0(600k)
        #expect(Set(result) == ["RB0", "HC0", "AU0", "IF0"])
    }

    @Test("filter · 关键词模糊匹配（lowercase contains）")
    func filterKeyword() {
        let data = mockData()
        let result = WatchlistFilter.filter(ids: data.map(\.id), keyword: "if",
                                             changePctForID: pctClosure(from: data))
        #expect(result == ["IF0"])
        // 不区分大小写
        let result2 = WatchlistFilter.filter(ids: data.map(\.id), keyword: "AU",
                                              changePctForID: pctClosure(from: data))
        #expect(result2.contains("AU0"))
    }

    @Test("filter · 关键词 + preset 组合")
    func filterCombined() {
        let data = mockData()
        let result = WatchlistFilter.filter(
            ids: data.map(\.id), preset: .gainers2pct, keyword: "0",
            changePctForID: pctClosure(from: data)
        )
        // 所有合约都包含 "0" · 但只有 +2% 以上 = HC0/CU0/Y0
        #expect(Set(result) == ["HC0", "CU0", "Y0"])
    }

    @Test("filter · 数据缺失（pct=nil）按 preset 决定")
    func filterMissingData() {
        let ids = ["RB0", "UNKNOWN", "CU0"]
        let pctMap: [String: Double] = ["RB0": 3.0, "CU0": 5.0]
        // gainers2pct：UNKNOWN 没数据 → 不过的
        let result = WatchlistFilter.filter(
            ids: ids, preset: .gainers2pct,
            changePctForID: { pctMap[$0] }
        )
        #expect(result == ["RB0", "CU0"])
    }

    // MARK: - WatchlistStatistics

    @Test("stats · 空 ids → empty")
    func statsEmpty() {
        let s = WatchlistStatsCalculator.compute(ids: [], changePctForID: { _ in nil })
        #expect(s == .empty)
    }

    @Test("stats · 全有数据 · 涨跌家数 / 平均")
    func statsFull() {
        let data = mockData()
        let s = WatchlistStatsCalculator.compute(
            ids: data.map(\.id), changePctForID: pctClosure(from: data)
        )
        #expect(s.total == 10)
        // gainers: RB/HC/CU/Y/IF = 5
        #expect(s.gainers == 5)
        // losers: AU/AG/M/IH = 4
        #expect(s.losers == 4)
        // unchanged: P0 = 1
        #expect(s.unchanged == 1)
        // 涨停 CU0
        #expect(s.limitUpCount == 1)
        // 跌停 M0
        #expect(s.limitDownCount == 1)
    }

    @Test("stats · 极值合约 ID 正确")
    func statsExtremes() {
        let data = mockData()
        let s = WatchlistStatsCalculator.compute(
            ids: data.map(\.id), changePctForID: pctClosure(from: data)
        )
        #expect(s.topGainerID == "CU0")
        #expect(s.topGainerPct == 9.8)
        #expect(s.topLoserID == "M0")
        #expect(s.topLoserPct == -9.7)
    }

    @Test("stats · 平均涨跌幅")
    func statsAvg() {
        // [+1, +2, +3] → avg = 2
        let s = WatchlistStatsCalculator.compute(
            ids: ["A", "B", "C"],
            changePctForID: { id in
                ["A": 1.0, "B": 2.0, "C": 3.0][id]
            }
        )
        #expect(s.avgChangePct == 2.0)
    }

    @Test("stats · bullBias 偏向计算")
    func statsBullBias() {
        let data = mockData()
        let s = WatchlistStatsCalculator.compute(
            ids: data.map(\.id), changePctForID: pctClosure(from: data)
        )
        // (5 涨 - 4 跌) / 10 = +0.1
        #expect(abs(s.bullBias - 0.1) < 1e-9)
    }

    @Test("stats · 数据缺失合约不计入 total")
    func statsMissingData() {
        let ids = ["A", "B", "MISSING"]
        let s = WatchlistStatsCalculator.compute(
            ids: ids,
            changePctForID: { ["A": 1.0, "B": 2.0][$0] }
        )
        #expect(s.total == 2)
    }

    // MARK: - WatchlistSorter 新字段

    @Test("sorter · volume 字段（活跃度）排序")
    func sortByVolume() {
        let data = mockData()
        let result = WatchlistSorter.sort(
            ids: data.map(\.id), field: .volume, ascending: false,
            keyForID: { id in volClosure(from: data)(id) }
        )
        // IF0(600k) → RB0(500k) → HC0(300k) → AU0(200k) → CU0(150k)
        #expect(result.first == "IF0")
        #expect(result[1] == "RB0")
    }

    @Test("sorter · change（绝对涨跌）字段")
    func sortByChange() {
        let ids = ["A", "B", "C"]
        let result = WatchlistSorter.sort(
            ids: ids, field: .change, ascending: false,
            keyForID: { id in
                ["A": 5.0, "B": -3.0, "C": 10.0][id]
            }
        )
        #expect(result == ["C", "A", "B"])
    }

    @Test("sorter · amplitude 字段")
    func sortByAmplitude() {
        let ids = ["A", "B"]
        let result = WatchlistSorter.sort(
            ids: ids, field: .amplitude, ascending: false,
            keyForID: { id in
                ["A": 0.05, "B": 0.10][id]   // amplitude 用比例
            }
        )
        #expect(result == ["B", "A"])
    }
}
