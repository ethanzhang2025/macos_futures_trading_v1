// WP-52 v15.19 batch26 · AlertPreset 单测

import Testing
import Foundation
import Shared
@testable import AlertCore

@Suite("AlertPreset · v15.19 batch26")
struct AlertPresetTests {

    @Test("6 类预设全有 displayName + helpText 不空")
    func allLabels() {
        for p in AlertPreset.allCases {
            #expect(!p.displayName.isEmpty)
            #expect(!p.helpText.isEmpty)
        }
    }

    @Test("limitUp · priceCrossAbove(lastPrice * 1.05)")
    func limitUp() {
        let alert = AlertPreset.limitUp.makeAlert(instrumentID: "RB0", lastPrice: 1000)
        if case .priceCrossAbove(let target) = alert.condition {
            // 1000 * 1.05 = 1050
            #expect(target == Decimal(1050))
        } else {
            Issue.record("Expected priceCrossAbove · got \(alert.condition)")
        }
        #expect(alert.name.contains("RB0"))
        #expect(alert.name.contains("涨停"))
    }

    @Test("limitDown · priceCrossBelow(lastPrice * 0.95)")
    func limitDown() {
        let alert = AlertPreset.limitDown.makeAlert(instrumentID: "IF0", lastPrice: 4000)
        if case .priceCrossBelow(let target) = alert.condition {
            #expect(target == Decimal(3800))
        } else {
            Issue.record("Expected priceCrossBelow")
        }
    }

    @Test("breakoutHighDay · priceBreakoutHigh(period=15m, lookback=20)")
    func breakoutHigh() {
        let alert = AlertPreset.breakoutHighDay.makeAlert(instrumentID: "RB0", lastPrice: 3500)
        if case .priceBreakoutHigh(let p, let n) = alert.condition {
            #expect(p == .minute15)
            #expect(n == 20)
        } else {
            Issue.record("Expected priceBreakoutHigh")
        }
    }

    @Test("breakoutLowDay · priceBreakoutLow(period=15m, lookback=20)")
    func breakoutLow() {
        let alert = AlertPreset.breakoutLowDay.makeAlert(instrumentID: "RB0", lastPrice: 3500)
        if case .priceBreakoutLow(let p, let n) = alert.condition {
            #expect(p == .minute15)
            #expect(n == 20)
        } else {
            Issue.record("Expected priceBreakoutLow")
        }
    }

    @Test("priceSpike · priceMoveSpike(1%, 60s)")
    func priceSpike() {
        let alert = AlertPreset.priceSpike.makeAlert(instrumentID: "RB0", lastPrice: 0)
        if case .priceMoveSpike(let pct, let s) = alert.condition {
            #expect(pct == Decimal(string: "0.01"))
            #expect(s == 60)
        } else {
            Issue.record("Expected priceMoveSpike")
        }
    }

    @Test("volumeSpike · volumeSpike(3×, 20)")
    func volumeSpike() {
        let alert = AlertPreset.volumeSpike.makeAlert(instrumentID: "RB0", lastPrice: 0)
        if case .volumeSpike(let m, let n) = alert.condition {
            #expect(m == 3)
            #expect(n == 20)
        } else {
            Issue.record("Expected volumeSpike")
        }
    }

    @Test("makeAlerts 批量 · 6 类一次创建 = 6 条 alert")
    func bulk() {
        let alerts = AlertPreset.makeAlerts(AlertPreset.allCases, instrumentID: "RB0", lastPrice: 3500)
        #expect(alerts.count == 6)
        #expect(Set(alerts.map(\.name)).count == 6)   // 名字唯一
    }

    @Test("默认 channel 包含 inApp + systemNotice · cooldown 60s")
    func defaultChannelsAndCooldown() {
        let alert = AlertPreset.limitUp.makeAlert(instrumentID: "RB0", lastPrice: 1000)
        #expect(alert.channels.contains(.inApp))
        #expect(alert.channels.contains(.systemNotice))
        #expect(alert.cooldownSeconds == 60)
    }
}
