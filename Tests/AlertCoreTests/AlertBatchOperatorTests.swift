// v15.20 batch57 · AlertBatchOperator 单测
// 覆盖 pause / resume / delete / duplicate 四类批量操作

import Testing
import Foundation
@testable import AlertCore

@Suite("AlertBatchOperator · 批量操作")
struct AlertBatchOperatorTests {

    private func make(name: String = "test", status: AlertStatus = .active) -> Alert {
        Alert(
            name: name,
            instrumentID: "RB0",
            condition: .priceAbove(Decimal(3850)),
            status: status,
            channels: [.inApp],
            cooldownSeconds: 60
        )
    }

    @Test("pause · active/triggered → paused · 已 paused/cancelled 跳过")
    func pauseStatus() {
        let a = make(name: "a", status: .active)
        let b = make(name: "b", status: .triggered)
        let c = make(name: "c", status: .paused)
        let d = make(name: "d", status: .cancelled)
        let result = AlertBatchOperator.pause(ids: [a.id, b.id, c.id, d.id], in: [a, b, c, d])
        #expect(result[0].status == .paused)
        #expect(result[1].status == .paused)
        #expect(result[2].status == .paused) // 已 paused 不变
        #expect(result[3].status == .cancelled) // cancelled 跳过
    }

    @Test("resume · paused → active · 其他状态跳过")
    func resumeStatus() {
        let a = make(name: "a", status: .paused)
        let b = make(name: "b", status: .active)
        let c = make(name: "c", status: .cancelled)
        let result = AlertBatchOperator.resume(ids: [a.id, b.id, c.id], in: [a, b, c])
        #expect(result[0].status == .active)
        #expect(result[1].status == .active)  // 已 active 不变
        #expect(result[2].status == .cancelled)
    }

    @Test("非选中 ID 不受影响")
    func unselectedUntouched() {
        let a = make(name: "a", status: .active)
        let b = make(name: "b", status: .active)
        let result = AlertBatchOperator.pause(ids: [a.id], in: [a, b])
        #expect(result[0].status == .paused)
        #expect(result[1].status == .active)  // b 不在 ids 中 → 不动
    }

    @Test("delete · 保序 · 仅删除选中")
    func delete() {
        let a = make(name: "a")
        let b = make(name: "b")
        let c = make(name: "c")
        let result = AlertBatchOperator.delete(ids: [a.id, c.id], in: [a, b, c])
        #expect(result.count == 1)
        #expect(result[0].id == b.id)
    }

    @Test("delete · 不存在的 ID silent skip")
    func deleteNonExistent() {
        let a = make(name: "a")
        let bogus = UUID()
        let result = AlertBatchOperator.delete(ids: [bogus], in: [a])
        #expect(result.count == 1)
        #expect(result[0].id == a.id)
    }

    @Test("duplicate · 新 UUID · 名加（副本）· 默认 paused · lastTriggeredAt=nil")
    func duplicate() {
        let a = make(name: "涨停", status: .active)
        var copy = a
        copy.lastTriggeredAt = Date()
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let result = AlertBatchOperator.duplicate(ids: [copy.id], in: [copy], now: now)
        #expect(result.alerts.count == 2)
        #expect(result.newIDs.count == 1)

        let dup = result.alerts.last!
        #expect(dup.id != copy.id)
        #expect(dup.name == "涨停（副本）")
        #expect(dup.instrumentID == "RB0")
        #expect(dup.status == .paused)             // 防触发风暴
        #expect(dup.lastTriggeredAt == nil)        // 不继承
        #expect(dup.cooldownSeconds == 60)
        #expect(dup.channels == [.inApp])
        #expect(dup.createdAt == now)
        #expect(result.newIDs.contains(dup.id))
    }

    @Test("duplicate · 多个选中 · 全部生成新副本")
    func duplicateMultiple() {
        let a = make(name: "a")
        let b = make(name: "b")
        let result = AlertBatchOperator.duplicate(ids: [a.id, b.id], in: [a, b])
        #expect(result.alerts.count == 4)
        #expect(result.newIDs.count == 2)
    }

    @Test("v15.20 batch72 · resetCooldown · 清 lastTriggeredAt · triggered 回 active")
    func resetCooldown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var a = make(name: "a", status: .active)
        a.lastTriggeredAt = now
        var b = make(name: "b", status: .triggered)
        b.lastTriggeredAt = now
        let c = make(name: "c", status: .paused)   // lastTriggeredAt nil
        let d = make(name: "d", status: .active)   // 不在选中

        let result = AlertBatchOperator.resetCooldown(ids: [a.id, b.id, c.id], in: [a, b, c, d])
        #expect(result[0].lastTriggeredAt == nil)        // a · 清掉
        #expect(result[0].status == .active)              // 不变
        #expect(result[1].lastTriggeredAt == nil)        // b · 清掉
        #expect(result[1].status == .active)              // triggered → active
        #expect(result[2].lastTriggeredAt == nil)        // c · 本来就是 nil
        #expect(result[2].status == .paused)              // 不变（不只 triggered 才回 active）
        #expect(result[3].lastTriggeredAt == nil)        // d · 不在选中 · 但本来就是 nil
        #expect(result[3].status == .active)
    }

    @Test("空选择 · 全部为 no-op")
    func emptySelection() {
        let a = make(name: "a", status: .active)
        let pauseR = AlertBatchOperator.pause(ids: [], in: [a])
        let resumeR = AlertBatchOperator.resume(ids: [], in: [a])
        let deleteR = AlertBatchOperator.delete(ids: [], in: [a])
        let dupR = AlertBatchOperator.duplicate(ids: [], in: [a])
        #expect(pauseR == [a])
        #expect(resumeR == [a])
        #expect(deleteR == [a])
        #expect(dupR.alerts == [a])
        #expect(dupR.newIDs.isEmpty)
    }
}
