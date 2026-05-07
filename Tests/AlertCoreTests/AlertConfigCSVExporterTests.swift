// v15.23 batch198 · AlertConfig CSV 导出测试
// 覆盖：空 / 单条 / 多条 / 状态 / channels / cooldown / 时间格式 / RFC 4180 转义

import Testing
import Foundation
import Shared
@testable import AlertCore

@Suite("AlertConfigCSVExporter · v15.23 batch198")
struct AlertConfigCSVExporterTests {

    private let createdAt = Date(timeIntervalSince1970: 1_730_000_000)

    private func sample(name: String = "测试",
                        instrumentID: String = "rb0",
                        condition: AlertCondition = .priceAbove(3500),
                        status: AlertStatus = .active,
                        channels: Set<NotificationChannelKind> = [.inApp],
                        cooldown: TimeInterval = 60,
                        last: Date? = nil) -> Alert {
        Alert(
            name: name, instrumentID: instrumentID, condition: condition,
            status: status, channels: channels, cooldownSeconds: cooldown,
            createdAt: createdAt, lastTriggeredAt: last
        )
    }

    @Test("空输入 · 仅表头 + BOM + CRLF")
    func empty() {
        let csv = AlertConfigCSVExporter.export([])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.contains("合约,预警名,状态,条件,通知渠道,冷却(秒),创建时间,最近触发"))
        #expect(csv.hasSuffix("\r\n"))
    }

    @Test("单条 · 8 字段对齐")
    func singleRow() {
        let a = sample()
        let csv = AlertConfigCSVExporter.export([a])
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\r\n", omittingEmptySubsequences: false)
            .map(String.init)
        #expect(lines.count >= 2)
        let cols = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(cols.count == 8)
        #expect(cols[0] == "rb0")
        #expect(cols[1] == "测试")
        #expect(cols[2] == "活跃")
    }

    @Test("status 4 类中文化")
    func statusLabels() {
        let alerts: [Alert] = [
            sample(status: .active),
            sample(status: .triggered),
            sample(status: .paused),
            sample(status: .cancelled),
        ]
        let csv = AlertConfigCSVExporter.export(alerts)
        #expect(csv.contains("活跃"))
        #expect(csv.contains("已触发"))
        #expect(csv.contains("已暂停"))
        #expect(csv.contains("已取消"))
    }

    @Test("channels 多值用分号分隔 · 排序稳定")
    func channelsLabel() {
        let a = sample(channels: [.inApp, .systemNotice, .sound])
        let csv = AlertConfigCSVExporter.export([a])
        #expect(csv.contains("App内;声音;系统通知") || csv.contains("App内") && csv.contains("声音") && csv.contains("系统通知"))
    }

    @Test("conditionLabel 各类显示")
    func conditions() {
        let alerts: [Alert] = [
            sample(condition: .priceAbove(3500)),
            sample(condition: .priceBelow(3400)),
            sample(condition: .priceCrossAbove(3500)),
            sample(condition: .volumeSpike(multiple: 3, windowBars: 20)),
        ]
        let csv = AlertConfigCSVExporter.export(alerts)
        #expect(csv.contains("价格 ≥ 3500"))
        #expect(csv.contains("价格 ≤ 3400"))
        #expect(csv.contains("上穿 3500"))
        #expect(csv.contains("成交量 ≥ 3× / 20期"))
    }

    @Test("cooldown 转 Int 字符串")
    func cooldownInt() {
        let csv = AlertConfigCSVExporter.export([sample(cooldown: 120.5)])
        #expect(csv.contains("120,"))
    }

    @Test("lastTriggeredAt nil → 空字段")
    func lastNil() {
        let csv = AlertConfigCSVExporter.export([sample(last: nil)])
        let lines = csv.replacingOccurrences(of: "\u{FEFF}", with: "")
            .split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        let cols = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        #expect(cols[7] == "")  // 最后一列空
    }

    @Test("RFC 4180 转义：含逗号 / 引号的字段")
    func rfcEscape() {
        let a = sample(name: "螺纹,日内", instrumentID: "rb0")
        let csv = AlertConfigCSVExporter.export([a])
        #expect(csv.contains("\"螺纹,日内\""))
    }

    @Test("BOM + CRLF 行结尾")
    func bomCrlf() {
        let csv = AlertConfigCSVExporter.export([sample()])
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(csv.contains("\r\n"))
    }
}
