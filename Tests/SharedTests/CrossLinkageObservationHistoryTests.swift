// v17.187 · CrossLinkageObservationHistory 单测

import Testing
import Foundation
@testable import Shared

@Suite("v17.187 · CrossLinkageObservationHistory 持久化历史")
struct CrossLinkageObservationHistoryTests {

    @Test("append · 单条 · 时间倒序首位")
    func appendSingle() {
        var h = CrossLinkageObservationHistory.empty
        h.append(makeEntry(ruleID: "R1", verdict: "matched"))
        #expect(h.entries.count == 1)
        #expect(h.entries[0].ruleID == "R1")
    }

    @Test("append · 多条 · 后来居前（时间倒序）")
    func appendNewestFirst() {
        var h = CrossLinkageObservationHistory.empty
        h.append(makeEntry(ruleID: "R1", verdict: "matched"))
        h.append(makeEntry(ruleID: "R2", verdict: "mismatched"))
        h.append(makeEntry(ruleID: "R3", verdict: "matched"))
        #expect(h.entries.map(\.ruleID) == ["R3", "R2", "R1"])
    }

    @Test("append · 超过 maxEntries · 自动 drop oldest")
    func capacityLimit() {
        var h = CrossLinkageObservationHistory.empty
        for i in 0..<10 {
            h.append(makeEntry(ruleID: "R\(i)", verdict: "matched"), maxEntries: 5)
        }
        #expect(h.entries.count == 5)
        // 最新 5 条 = R9..R5
        #expect(h.entries.first?.ruleID == "R9")
        #expect(h.entries.last?.ruleID == "R5")
    }

    @Test("appendBatch · 默认跳过 notTriggered")
    func batchSkipsNotTriggered() {
        let rules = [
            CrossInstrumentLinkageRule(ruleID: "R1", triggerInstrument: "RB",
                triggerKind: .riseAtLeast, triggerThresholdPct: 3,
                watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1),
            CrossInstrumentLinkageRule(ruleID: "R2", triggerInstrument: "I",
                triggerKind: .riseAtLeast, triggerThresholdPct: 3,
                watchInstrument: "J", expectation: .followUp, watchThresholdPct: 1)
        ]
        let observations = [
            CrossLinkageObservation(ruleID: "R1", verdict: .matched,
                triggerChangePct: 4, watchChangePct: 1.5, message: "ok"),
            CrossLinkageObservation(ruleID: "R2", verdict: .notTriggered,
                triggerChangePct: 1, watchChangePct: 0, message: "未触发")
        ]
        var h = CrossLinkageObservationHistory.empty
        h.appendBatch(observations: observations, rules: rules)
        #expect(h.entries.count == 1)
        #expect(h.entries[0].verdict == "matched")
    }

    @Test("appendBatch · includeNotTriggered=true · 全收")
    func batchIncludesNotTriggered() {
        let rules = [
            CrossInstrumentLinkageRule(ruleID: "R1", triggerInstrument: "RB",
                triggerKind: .riseAtLeast, triggerThresholdPct: 3,
                watchInstrument: "HC", expectation: .followUp, watchThresholdPct: 1)
        ]
        let observations = [
            CrossLinkageObservation(ruleID: "R1", verdict: .notTriggered,
                triggerChangePct: 0, watchChangePct: 0, message: "未触发")
        ]
        var h = CrossLinkageObservationHistory.empty
        h.appendBatch(observations: observations, rules: rules, includeNotTriggered: true)
        #expect(h.entries.count == 1)
    }

    @Test("clear · 清空所有 entries")
    func clear() {
        var h = CrossLinkageObservationHistory.empty
        h.append(makeEntry(ruleID: "R1", verdict: "matched"))
        h.clear()
        #expect(h.entries.isEmpty)
    }

    @Test("Store · 写入 / 读回 round-trip")
    func storeRoundTrip() {
        let suite = UserDefaults(suiteName: "test.crossLinkageHist.\(UUID())")!
        var h = CrossLinkageObservationHistory.empty
        h.append(makeEntry(ruleID: "R1", verdict: "matched"))
        h.append(makeEntry(ruleID: "R2", verdict: "mismatched"))
        CrossLinkageObservationHistoryStore.save(h, defaults: suite)
        let loaded = CrossLinkageObservationHistoryStore.load(defaults: suite)
        #expect(loaded?.entries.count == 2)
        #expect(loaded?.entries[0].ruleID == "R2")  // 最新在首
    }

    @Test("Store · 缺 key 返回 nil")
    func storeMissingReturnsNil() {
        let suite = UserDefaults(suiteName: "test.crossLinkageHist.missing.\(UUID())")!
        #expect(CrossLinkageObservationHistoryStore.load(defaults: suite) == nil)
    }
}

fileprivate func makeEntry(ruleID: String, verdict: String) -> CrossLinkageHistoryEntry {
    CrossLinkageHistoryEntry(
        timestamp: Date(),
        ruleID: ruleID, verdict: verdict,
        triggerInstrument: "RB", watchInstrument: "HC",
        triggerChangePct: 3.5, watchChangePct: 1.2,
        message: "test"
    )
}
