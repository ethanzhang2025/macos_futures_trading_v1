// v15.20 batch69 · AlertSorter 单测

import Testing
import Foundation
@testable import AlertCore

@Suite("AlertSorter · 预警列表排序")
struct AlertSorterTests {

    private func make(name: String, instrumentID: String = "RB0", status: AlertStatus = .active,
                      createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
                      lastTriggeredAt: Date? = nil) -> Alert {
        Alert(
            name: name,
            instrumentID: instrumentID,
            condition: .priceAbove(Decimal(100)),
            status: status,
            createdAt: createdAt,
            lastTriggeredAt: lastTriggeredAt
        )
    }

    @Test(".manual 保持原序")
    func manual() {
        let alerts = [make(name: "c"), make(name: "a"), make(name: "b")]
        let result = AlertSorter.sort(alerts, field: .manual, ascending: true)
        #expect(result.map(\.name) == ["c", "a", "b"])
    }

    @Test(".name 字典序升降")
    func nameOrder() {
        let alerts = [make(name: "c"), make(name: "a"), make(name: "b")]
        #expect(AlertSorter.sort(alerts, field: .name, ascending: true).map(\.name) == ["a", "b", "c"])
        #expect(AlertSorter.sort(alerts, field: .name, ascending: false).map(\.name) == ["c", "b", "a"])
    }

    @Test(".instrumentID 同合约 tiebreak 按 name")
    func instrumentTiebreak() {
        let a = make(name: "z", instrumentID: "RB0")
        let b = make(name: "a", instrumentID: "RB0")
        let c = make(name: "m", instrumentID: "IF0")
        let result = AlertSorter.sort([a, b, c], field: .instrumentID, ascending: true)
        #expect(result.map(\.name) == ["m", "a", "z"])  // IF0 first, RB0 内按 name
    }

    @Test(".status 业务序：active < triggered < paused < cancelled")
    func statusOrder() {
        let alerts = [
            make(name: "p", status: .paused),
            make(name: "c", status: .cancelled),
            make(name: "a", status: .active),
            make(name: "t", status: .triggered),
        ]
        let asc = AlertSorter.sort(alerts, field: .status, ascending: true)
        #expect(asc.map(\.status) == [.active, .triggered, .paused, .cancelled])
        let desc = AlertSorter.sort(alerts, field: .status, ascending: false)
        #expect(desc.map(\.status) == [.cancelled, .paused, .triggered, .active])
    }

    @Test(".createdAt 时间序")
    func createdAt() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let t3 = Date(timeIntervalSince1970: 1_700_002_000)
        let alerts = [
            make(name: "b", createdAt: t2),
            make(name: "a", createdAt: t1),
            make(name: "c", createdAt: t3),
        ]
        #expect(AlertSorter.sort(alerts, field: .createdAt, ascending: true).map(\.name) == ["a", "b", "c"])
        #expect(AlertSorter.sort(alerts, field: .createdAt, ascending: false).map(\.name) == ["c", "b", "a"])
    }

    @Test(".lastTriggeredAt nil 始终排末尾")
    func lastTriggeredNil() {
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_001_000)
        let alerts = [
            make(name: "nilA", lastTriggeredAt: nil),
            make(name: "old", lastTriggeredAt: t1),
            make(name: "nilB", lastTriggeredAt: nil),
            make(name: "new", lastTriggeredAt: t2),
        ]
        let asc = AlertSorter.sort(alerts, field: .lastTriggeredAt, ascending: true).map(\.name)
        #expect(asc == ["old", "new", "nilA", "nilB"])  // 数值在前 升序 · nil 末尾 字典序
        let desc = AlertSorter.sort(alerts, field: .lastTriggeredAt, ascending: false).map(\.name)
        #expect(desc == ["new", "old", "nilA", "nilB"])  // nil 仍排末尾
    }

    @Test("displayName 全 6 类中文化")
    func displayNames() {
        #expect(AlertSortField.manual.displayName == "默认")
        #expect(AlertSortField.name.displayName == "名称")
        #expect(AlertSortField.instrumentID.displayName == "合约")
        #expect(AlertSortField.status.displayName == "状态")
        #expect(AlertSortField.createdAt.displayName == "创建时间")
        #expect(AlertSortField.lastTriggeredAt.displayName == "最近触发")
    }

    @Test("statusRank 公开 helper")
    func statusRank() {
        #expect(AlertSorter.statusRank(.active) == 0)
        #expect(AlertSorter.statusRank(.triggered) == 1)
        #expect(AlertSorter.statusRank(.paused) == 2)
        #expect(AlertSorter.statusRank(.cancelled) == 3)
    }
}
