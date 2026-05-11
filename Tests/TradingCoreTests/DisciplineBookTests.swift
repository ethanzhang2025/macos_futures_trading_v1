// WP-54 v15.23 batch4 · DisciplineBook 聚合根测试

import Testing
import Foundation
@testable import TradingCore

@Suite("DisciplineBook · WP-54 v15.23 batch4 聚合根 CRUD")
struct DisciplineBookTests {

    private let now0 = Date(timeIntervalSince1970: 1746360000)
    private let now1 = Date(timeIntervalSince1970: 1746360100)

    @Test("初始化空 book · rules 空 / enabledRules 空")
    func emptyInit() {
        let book = DisciplineBook()
        #expect(book.rules.isEmpty)
        #expect(book.enabledRules.isEmpty)
    }

    @Test("addRule · 添加 2 条 · count == 2 · 顺序保留")
    func addBasic() {
        var book = DisciplineBook()
        let r1 = DisciplineRule(kind: .stopLossPercent, threshold: 2)
        let r2 = DisciplineRule(kind: .maxHoldingMinutes, threshold: 30)
        book.addRule(r1)
        book.addRule(r2)
        #expect(book.rules.count == 2)
        #expect(book.rules[0].id == r1.id)
        #expect(book.rules[1].id == r2.id)
    }

    @Test("addRule · 同 id 重复添加 → 后者覆盖（不重复）")
    func addDuplicateIDOverwrite() {
        var book = DisciplineBook()
        let r1 = DisciplineRule(kind: .stopLossPercent, threshold: 2)
        let r1Updated = DisciplineRule(id: r1.id, kind: .stopLossPercent, threshold: 3)
        book.addRule(r1)
        book.addRule(r1Updated)
        #expect(book.rules.count == 1)
        #expect(book.rules[0].threshold == Decimal(3))
    }

    @Test("removeRule · id 存在 → 移除 · 不存在 → 无变化")
    func removeRule() {
        var book = DisciplineBook()
        let r1 = DisciplineRule(kind: .stopLossPercent, threshold: 2)
        book.addRule(r1)
        book.removeRule(id: UUID())  // 不存在
        #expect(book.rules.count == 1)
        book.removeRule(id: r1.id)
        #expect(book.rules.isEmpty)
    }

    @Test("updateRule · 保留原 createdAt · 刷新 updatedAt · 返回 true")
    func updateRulePreservesCreatedAt() {
        var book = DisciplineBook()
        let original = DisciplineRule(
            kind: .stopLossPercent, threshold: 2, note: "old",
            createdAt: now0, updatedAt: now0
        )
        book.addRule(original)
        let updated = DisciplineRule(
            id: original.id, kind: .stopLossPercent, threshold: 3, note: "new",
            createdAt: now1, updatedAt: now1   // 这俩应被忽略
        )
        let ok = book.updateRule(updated, now: now1)
        #expect(ok)
        let r = book.rule(id: original.id)!
        #expect(r.createdAt == now0)   // 原值保留
        #expect(r.updatedAt == now1)   // 用注入的 now
        #expect(r.threshold == Decimal(3))
        #expect(r.note == "new")
    }

    @Test("updateRule · 不存在 id → 返回 false · 无变化")
    func updateRuleMissing() {
        var book = DisciplineBook()
        let phantom = DisciplineRule(kind: .stopLossPercent, threshold: 2)
        let ok = book.updateRule(phantom)
        #expect(!ok)
        #expect(book.rules.isEmpty)
    }

    @Test("setEnabled · 切换启用 · 自动刷新 updatedAt")
    func setEnabledToggles() {
        var book = DisciplineBook()
        let r = DisciplineRule(kind: .stopLossPercent, threshold: 2, enabled: true,
                               createdAt: now0, updatedAt: now0)
        book.addRule(r)
        let ok = book.setEnabled(id: r.id, enabled: false, now: now1)
        #expect(ok)
        let updated = book.rule(id: r.id)!
        #expect(!updated.enabled)
        #expect(updated.updatedAt == now1)
    }

    @Test("rules(of:) 按 kind 过滤")
    func filterByKind() {
        var book = DisciplineBook()
        book.addRule(DisciplineRule(kind: .stopLossPercent, threshold: 2))
        book.addRule(DisciplineRule(kind: .stopLossPercent, threshold: 3))
        book.addRule(DisciplineRule(kind: .maxHoldingMinutes, threshold: 30))
        #expect(book.rules(of: .stopLossPercent).count == 2)
        #expect(book.rules(of: .maxHoldingMinutes).count == 1)
        #expect(book.rules(of: .dailyMaxLoss).isEmpty)
    }

    @Test("enabledRules · 仅返回 enabled=true 的规则")
    func enabledRulesFilter() {
        var book = DisciplineBook()
        let r1 = DisciplineRule(kind: .stopLossPercent, threshold: 2, enabled: true)
        let r2 = DisciplineRule(kind: .maxHoldingMinutes, threshold: 30, enabled: false)
        book.addRule(r1)
        book.addRule(r2)
        #expect(book.enabledRules.count == 1)
        #expect(book.enabledRules[0].id == r1.id)
    }

    @Test("Codable round-trip · 多规则 + Decimal threshold + 中文 note")
    func codableRoundTrip() throws {
        var book = DisciplineBook()
        book.addRule(DisciplineRule(kind: .stopLossPercent, threshold: 2.5, note: "止损"))
        book.addRule(DisciplineRule(kind: .dailyMaxLoss, threshold: 5000, enabled: false, note: "亏损上限"))
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(DisciplineBook.self, from: data)
        #expect(decoded == book)
    }

    @Test("defaultRecommended · 5 条推荐规则 · 全部 enabled")
    func defaultRecommendedShape() {
        let book = DisciplineBook.defaultRecommended
        #expect(book.rules.count == 5)
        #expect(book.enabledRules.count == 5)
        // 5 种 kind 全覆盖
        let kinds = Set(book.rules.map { $0.kind })
        #expect(kinds == Set(DisciplineRuleKind.allCases))
    }

    // MARK: - v16.43 · 4 套规则模板预设值校验（防意外修改）

    @Test("v16.43 · aggressiveIntraday · 高频参数（止损宽 / 持仓短 / 加仓多）")
    func aggressiveIntradayShape() {
        let book = DisciplineBook.aggressiveIntraday
        #expect(book.rules.count == 5)
        #expect(book.enabledRules.count == 5)
        let kinds = Set(book.rules.map { $0.kind })
        #expect(kinds == Set(DisciplineRuleKind.allCases))
        // 关键参数（trader 切换后应识别为激进风格）
        #expect(book.rules(of: .stopLossPercent).first?.threshold == 3.0)
        #expect(book.rules(of: .maxHoldingMinutes).first?.threshold == 30)
        #expect(book.rules(of: .maxDailyTrades).first?.threshold == 50)
    }

    @Test("v16.43 · swingHolding · 波段参数（止损宽 / 持仓长 / 单日少笔数）")
    func swingHoldingShape() {
        let book = DisciplineBook.swingHolding
        #expect(book.rules.count == 5)
        #expect(book.rules(of: .stopLossPercent).first?.threshold == 5.0)
        #expect(book.rules(of: .maxHoldingMinutes).first?.threshold == 4320)  // 3 天
        #expect(book.rules(of: .maxDailyTrades).first?.threshold == 5)
    }

    @Test("v16.43 · minimal · 仅 2 条核心（不被规则淹没）")
    func minimalShape() {
        let book = DisciplineBook.minimal
        #expect(book.rules.count == 2)
        #expect(book.enabledRules.count == 2)
        let kinds = Set(book.rules.map { $0.kind })
        #expect(kinds == Set([.stopLossPercent, .dailyMaxLoss]))
    }

    @Test("v16.43 · 4 套模板互不相同（各 Equatable 不重复）")
    func templatesAreDistinct() {
        let templates = [
            DisciplineBook.defaultRecommended,
            DisciplineBook.aggressiveIntraday,
            DisciplineBook.swingHolding,
            DisciplineBook.minimal,
        ]
        for i in 0..<templates.count {
            for j in (i+1)..<templates.count {
                #expect(templates[i] != templates[j], "模板 \(i) 和 \(j) 内容相同")
            }
        }
    }
}
