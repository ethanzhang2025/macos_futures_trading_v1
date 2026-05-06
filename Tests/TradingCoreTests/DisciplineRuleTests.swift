// WP-54 v15.23 batch1 · 纪律检查规则数据模型测试

import Testing
import Foundation
@testable import TradingCore

@Suite("DisciplineRule · WP-54 v15.23 batch1 数据模型")
struct DisciplineRuleTests {

    @Test("DisciplineRuleKind · 5 种 case · displayName / thresholdUnit 中文 + 单位")
    func kindMetadata() {
        #expect(DisciplineRuleKind.allCases.count == 5)
        #expect(DisciplineRuleKind.stopLossPercent.displayName == "单笔止损百分比")
        #expect(DisciplineRuleKind.stopLossPercent.thresholdUnit == "%")
        #expect(DisciplineRuleKind.maxHoldingMinutes.displayName == "持仓时长上限")
        #expect(DisciplineRuleKind.maxHoldingMinutes.thresholdUnit == "分钟")
        #expect(DisciplineRuleKind.maxAddPositions.thresholdUnit == "次")
        #expect(DisciplineRuleKind.dailyMaxLoss.thresholdUnit == "元")
        #expect(DisciplineRuleKind.maxDailyTrades.thresholdUnit == "笔")
    }

    @Test("DisciplineRuleKind · rawValue 序列化稳定（防未来重命名破坏 JSON）")
    func kindRawValue() {
        #expect(DisciplineRuleKind.stopLossPercent.rawValue == "stopLossPercent")
        #expect(DisciplineRuleKind.maxHoldingMinutes.rawValue == "maxHoldingMinutes")
        #expect(DisciplineRuleKind.maxAddPositions.rawValue == "maxAddPositions")
        #expect(DisciplineRuleKind.dailyMaxLoss.rawValue == "dailyMaxLoss")
        #expect(DisciplineRuleKind.maxDailyTrades.rawValue == "maxDailyTrades")
    }

    @Test("DisciplineRule · 默认 enabled=true / note 空 / id 自动生成")
    func defaultInit() {
        let rule = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        #expect(rule.enabled == true)
        #expect(rule.note.isEmpty)
        #expect(rule.threshold == Decimal(2.0))
        #expect(rule.kind == .stopLossPercent)
    }

    @Test("DisciplineRule · Codable round-trip 保持完整性（含 enabled false / 中文 note）")
    func ruleCodableRoundTrip() throws {
        let original = DisciplineRule(
            kind: .maxHoldingMinutes,
            threshold: 30,
            enabled: false,
            note: "训练阶段先关 · 实盘再开",
            createdAt: Date(timeIntervalSince1970: 1746360000),
            updatedAt: Date(timeIntervalSince1970: 1746360100)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisciplineRule.self, from: data)
        #expect(decoded == original)
    }

    @Test("DisciplineViolation · Severity · warning < error 显示文案")
    func violationSeverity() {
        #expect(DisciplineViolation.Severity.warning.displayName == "警告")
        #expect(DisciplineViolation.Severity.error.displayName == "违规")
        #expect(DisciplineViolation.Severity.allCases.count == 2)
    }

    @Test("DisciplineViolation · 默认 relatedOrderRefs=[] / context=nil")
    func violationDefaults() {
        let v = DisciplineViolation(
            ruleID: UUID(),
            ruleKind: .stopLossPercent,
            occurredAt: Date(),
            severity: .warning,
            message: "测试"
        )
        #expect(v.relatedOrderRefs.isEmpty)
        #expect(v.context == nil)
    }

    @Test("DisciplineViolation · Codable 含完整 context + 多 orderRefs round-trip")
    func violationCodableRoundTrip() throws {
        let original = DisciplineViolation(
            ruleID: UUID(),
            ruleKind: .dailyMaxLoss,
            occurredAt: Date(timeIntervalSince1970: 1746360000),
            severity: .error,
            message: "今日累计亏损 -8000 元（上限 -5000）",
            relatedOrderRefs: ["O-001", "O-002", "O-005"],
            context: "{\"loss\":-8000,\"orders\":3}"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisciplineViolation.self, from: data)
        #expect(decoded == original)
    }

    @Test("DisciplineRule · 不同 id 即使其他字段相同也 != （Identifiable 保证）")
    func ruleIdentityByID() {
        let r1 = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        let r2 = DisciplineRule(kind: .stopLossPercent, threshold: 2.0)
        #expect(r1 != r2)
        #expect(r1.id != r2.id)
    }
}
