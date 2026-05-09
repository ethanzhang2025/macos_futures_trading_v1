// SectorStatistics 测试（v15.43）

import Testing
import Foundation
@testable import Shared

@Suite("SectorStatistics · 板块聚合统计")
struct SectorStatisticsTests {

    private func mockInst(id: String, change: Double, oi: Double = 100) -> SectorInstrument {
        SectorInstrument(id: id, name: id, sector: .黑色,
                         lastPrice: 1000, changePct: change, openInterestK: oi)
    }

    @Test("空数组 · totalCount 0")
    func testEmpty() {
        let stats = SectorStatisticsCalculator.compute([], sector: .黑色)
        #expect(stats.totalCount == 0)
        #expect(stats.gainers == 0 && stats.losers == 0)
        #expect(stats.bullBias == 0)
        #expect(stats.strongest == nil)
        #expect(stats.weakest == nil)
    }

    @Test("单品种涨 · gainers=1 / bullBias=+1")
    func testSingleGain() {
        let stats = SectorStatisticsCalculator.compute(
            [mockInst(id: "RB0", change: +2.5)], sector: .黑色
        )
        #expect(stats.totalCount == 1)
        #expect(stats.gainers == 1 && stats.losers == 0)
        #expect(stats.bullBias == 1.0)
        #expect(stats.avgChangePct == 2.5)
    }

    @Test("3 涨 1 跌 · bullBias = +0.5")
    func testMixed() {
        let stats = SectorStatisticsCalculator.compute([
            mockInst(id: "A", change: +1),
            mockInst(id: "B", change: +2),
            mockInst(id: "C", change: +3),
            mockInst(id: "D", change: -1)
        ], sector: .黑色)
        #expect(stats.totalCount == 4)
        #expect(stats.gainers == 3)
        #expect(stats.losers == 1)
        #expect(stats.bullBias == 0.5)
        #expect(abs(stats.avgChangePct - 1.25) < 0.01)
    }

    @Test("strongest = 涨幅最大")
    func testStrongest() {
        let stats = SectorStatisticsCalculator.compute([
            mockInst(id: "A", change: +1.0),
            mockInst(id: "B", change: +5.5),
            mockInst(id: "C", change: -2.0),
            mockInst(id: "D", change: +3.0)
        ], sector: .黑色)
        #expect(stats.strongest?.id == "B")
        #expect(stats.weakest?.id == "C")
    }

    @Test("unchanged · changePct=0 算 unchanged")
    func testUnchanged() {
        let stats = SectorStatisticsCalculator.compute([
            mockInst(id: "A", change: 0),
            mockInst(id: "B", change: 0),
            mockInst(id: "C", change: +1)
        ], sector: .黑色)
        #expect(stats.unchanged == 2)
        #expect(stats.gainers == 1)
        #expect(stats.losers == 0)
    }

    @Test("totalOpenInterestK 累加")
    func testTotalOI() {
        let stats = SectorStatisticsCalculator.compute([
            mockInst(id: "A", change: +1, oi: 100),
            mockInst(id: "B", change: -1, oi: 250.5),
            mockInst(id: "C", change: 0, oi: 50)
        ], sector: .黑色)
        #expect(abs(stats.totalOpenInterestK - 400.5) < 0.001)
    }

    @Test("computeAll · 11 板块全 covered")
    func testComputeAll() {
        let stats = SectorStatisticsCalculator.computeAll(SectorPresets.all)
        #expect(stats.count == Sector.allCases.count)
        // 黑色板块至少有 7 品种
        let black = stats.first { $0.sector == .黑色 }
        #expect(black?.totalCount ?? 0 >= 7)
    }

    @Test("真实数据 · 黑色 7 品种 / strongest 来自 7 个之一")
    func testRealBlackSector() {
        let black = SectorPresets.instruments(in: .黑色)
        let stats = SectorStatisticsCalculator.compute(black, sector: .黑色)
        #expect(stats.totalCount == black.count)
        #expect(stats.strongest != nil)
        #expect(black.contains { $0.id == stats.strongest!.id })
    }

    @Test("bullBias 范围 [-1, +1]")
    func testBullBiasRange() {
        let allStats = SectorStatisticsCalculator.computeAll(SectorPresets.all)
        for s in allStats {
            #expect(s.bullBias >= -1 && s.bullBias <= 1)
        }
    }
}
