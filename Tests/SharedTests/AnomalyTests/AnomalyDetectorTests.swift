// AnomalyDetector 测试（v15.54 · ⌘⌥A）
//
// 覆盖：
// - 5 维度各自基本触发 / 不触发
// - severity 边界 [0, 100]
// - countByKind / countBySector 聚合
// - thresholds.enabledKinds 关闭某类时不出该类事件
// - 排序：按 severity 降序

import XCTest
@testable import Shared

final class AnomalyDetectorTests: XCTestCase {

    // MARK: - 基础数据 fixture

    /// 构造测试品种 · 简化构造器
    private func make(
        id: String,
        name: String = "测试",
        sector: Sector = .黑色,
        price: Decimal = 1000,
        pct: Double = 0,
        oiK: Double = 100
    ) -> SectorInstrument {
        SectorInstrument(id: id, name: name, sector: sector, lastPrice: price, changePct: pct, openInterestK: oiK)
    }

    // MARK: - 价格异动

    func testPriceSpike_triggersAtThreshold() {
        let insts = [
            make(id: "A", pct: 2.5),  // 触发（≥ 2%）
            make(id: "B", pct: -3.0), // 触发
            make(id: "C", pct: 1.0)   // 不触发
        ]
        let evts = AnomalyDetector.detectPriceSpike(instruments: insts, threshold: 2.0)
        XCTAssertEqual(evts.count, 2)
        XCTAssertEqual(Set(evts.map(\.instrumentID)), ["A", "B"])
    }

    func testPriceSpike_severityBounds() {
        // 阈值 2% · 4% 命中 → severity = 4/2*50 = 100
        // 10% 命中 → 也只 100（clamp）
        let insts = [
            make(id: "A", pct: 4.0),
            make(id: "B", pct: 10.0),
            make(id: "C", pct: 2.0)  // 边界 → 50
        ]
        let evts = AnomalyDetector.detectPriceSpike(instruments: insts, threshold: 2.0)
        XCTAssertEqual(evts.count, 3)
        let byID = Dictionary(uniqueKeysWithValues: evts.map { ($0.instrumentID, $0.severity) })
        XCTAssertEqual(byID["A"] ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(byID["B"] ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(byID["C"] ?? -1, 50, accuracy: 0.001)
    }

    // MARK: - 持仓异动

    func testOISpike_triggersByLocalSectorAvg() {
        // 黑色板块：A=300K · B=100K · C=100K → avg=166.67 · A/avg=1.8 ≥ 1.5 命中
        let insts = [
            make(id: "A", sector: .黑色, oiK: 300),
            make(id: "B", sector: .黑色, oiK: 100),
            make(id: "C", sector: .黑色, oiK: 100),
            // 有色板块：D=500 · E=400（D/avg=1.11 不命中）
            make(id: "D", sector: .有色, oiK: 500),
            make(id: "E", sector: .有色, oiK: 400)
        ]
        let evts = AnomalyDetector.detectOISpike(instruments: insts, multiple: 1.5)
        XCTAssertEqual(evts.count, 1)
        XCTAssertEqual(evts.first?.instrumentID, "A")
    }

    func testOISpike_skipsSingletonSectors() {
        // 板块只 1 个品种 → 跳过（list.count >= 2 条件）
        let insts = [make(id: "X", sector: .贵金属, oiK: 1000)]
        let evts = AnomalyDetector.detectOISpike(instruments: insts, multiple: 1.5)
        XCTAssertEqual(evts.count, 0)
    }

    // MARK: - 资金异动

    func testFundSurge_inflowAndOutflow() {
        // netInflow = oiK × changePct × 0.5（changePct 量纲已是百分比 · 不再 /100）
        // A: 10K × +5 × 0.5 = +25  (不触发 50 阈值)
        // B: 20K × +5 × 0.5 = +50  (触发)
        // C: 40K × -4 × 0.5 = -80  (触发)
        let insts = [
            make(id: "A", pct: 5.0, oiK: 10),
            make(id: "B", pct: 5.0, oiK: 20),
            make(id: "C", pct: -4.0, oiK: 40)
        ]
        let evts = AnomalyDetector.detectFundSurge(instruments: insts, thresholdMillion: 50.0)
        XCTAssertEqual(evts.count, 2)
        XCTAssertEqual(Set(evts.map(\.instrumentID)), ["B", "C"])
    }

    // MARK: - 量价背离

    func testPriceOIDivergence_isStable() {
        // 同一 instruments 多次扫描结果一致（hash 稳定）
        let insts = SectorPresets.all
        let r1 = AnomalyDetector.detectPriceOIDivergence(instruments: insts)
        let r2 = AnomalyDetector.detectPriceOIDivergence(instruments: insts)
        XCTAssertEqual(r1.map(\.instrumentID).sorted(), r2.map(\.instrumentID).sorted())
        // 应有部分命中（~14% · 60+ 品种 → ~7-12 个）
        XCTAssertGreaterThan(r1.count, 0)
        XCTAssertLessThan(r1.count, insts.count / 3)
    }

    // MARK: - 板块离群

    func testSectorOutlier_majorityUpOneDown() {
        // 板块 5 品种：4 涨 1 跌（80% 共识）→ 跌的为离群
        let insts = [
            make(id: "A", sector: .化工, pct: +1.5),
            make(id: "B", sector: .化工, pct: +0.8),
            make(id: "C", sector: .化工, pct: +1.2),
            make(id: "D", sector: .化工, pct: +0.5),
            make(id: "E", sector: .化工, pct: -1.0)  // 离群
        ]
        let evts = AnomalyDetector.detectSectorOutlier(instruments: insts)
        XCTAssertEqual(evts.count, 1)
        XCTAssertEqual(evts.first?.instrumentID, "E")
    }

    func testSectorOutlier_noConsensusNoEvent() {
        // 板块 4 品种：2 涨 2 跌 → 无共识（< 60%）→ 不出离群
        let insts = [
            make(id: "A", sector: .股指, pct: +1.5),
            make(id: "B", sector: .股指, pct: +0.8),
            make(id: "C", sector: .股指, pct: -0.8),
            make(id: "D", sector: .股指, pct: -1.5)
        ]
        let evts = AnomalyDetector.detectSectorOutlier(instruments: insts)
        XCTAssertEqual(evts.count, 0)
    }

    // MARK: - scan 整合

    func testScan_sortedBySeverityDescending() {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        XCTAssertGreaterThan(result.events.count, 0)
        for i in 1..<result.events.count {
            XCTAssertGreaterThanOrEqual(result.events[i - 1].severity, result.events[i].severity)
        }
    }

    func testScan_countByKindMatchesEvents() {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        var rebuilt: [AnomalyKind: Int] = [:]
        for e in result.events { rebuilt[e.kind, default: 0] += 1 }
        XCTAssertEqual(rebuilt, result.countByKind)
    }

    func testScan_disabledKindNotEmitted() {
        var th = AnomalyThresholds.default
        th.enabledKinds = [.priceSpike]  // 仅价格
        let result = AnomalyDetector.scan(instruments: SectorPresets.all, thresholds: th)
        XCTAssertTrue(result.events.allSatisfy { $0.kind == .priceSpike })
        XCTAssertEqual(result.countByKind[.oiSpike] ?? 0, 0)
        XCTAssertEqual(result.countByKind[.fundSurge] ?? 0, 0)
    }

    func testScan_severityClampedToHundred() {
        let result = AnomalyDetector.scan(instruments: SectorPresets.all)
        XCTAssertTrue(result.events.allSatisfy { $0.severity >= 0 && $0.severity <= 100 })
    }
}
