// v17.175 · CrossLinkageRulesStore 单测

import Testing
import Foundation
@testable import Shared

@Suite("v17.175 · CrossLinkageRulesStore 持久化")
struct CrossLinkageRulesStoreTests {

    @Test("CrossLinkageRules · add / update / remove 流程")
    func crudFlow() {
        var rules = CrossLinkageRules.empty
        #expect(rules.rules.isEmpty)
        let r1 = makeRule(id: "R1", trigger: "RB", watch: "HC")
        rules.add(r1)
        #expect(rules.rules.count == 1)

        var updated = r1
        updated.triggerThresholdPct = 5
        rules.update(updated)
        #expect(rules.rules[0].triggerThresholdPct == 5)

        rules.remove(ruleID: "R1")
        #expect(rules.rules.isEmpty)
    }

    @Test("nextID · CL- 前缀 + 6 位时间戳 · 同毫秒重复调用不必唯一（v1 接受）")
    func nextIDFormat() {
        let id = CrossLinkageRules.empty.nextID()
        #expect(id.hasPrefix("CL-"))
        #expect(id.count == "CL-".count + 6)
    }

    @Test("CrossLinkageRulesStore · 写入 / 读回 round-trip · 失败返回 nil")
    func saveAndLoadRoundTrip() {
        let suite = UserDefaults(suiteName: "test.crossLinkage.\(UUID())")!
        let r1 = makeRule(id: "R1", trigger: "RB", watch: "HC")
        let r2 = makeRule(id: "R2", trigger: "I", watch: "J")
        var rules = CrossLinkageRules.empty
        rules.add(r1)
        rules.add(r2)
        CrossLinkageRulesStore.save(rules, defaults: suite)

        guard let loaded = CrossLinkageRulesStore.load(defaults: suite) else {
            Issue.record("加载失败")
            return
        }
        #expect(loaded.rules.count == 2)
        #expect(loaded.rules[0].ruleID == "R1")
        #expect(loaded.rules[1].watchInstrument == "J")
    }

    @Test("CrossLinkageRulesStore · 没有 key · 返回 nil")
    func loadMissingReturnsNil() {
        let suite = UserDefaults(suiteName: "test.crossLinkage.missing.\(UUID())")!
        #expect(CrossLinkageRulesStore.load(defaults: suite) == nil)
    }
}

fileprivate func makeRule(id: String, trigger: String, watch: String) -> CrossInstrumentLinkageRule {
    CrossInstrumentLinkageRule(
        ruleID: id,
        triggerInstrument: trigger, triggerKind: .riseAtLeast, triggerThresholdPct: 3,
        watchInstrument: watch, expectation: .followUp, watchThresholdPct: 1
    )
}
