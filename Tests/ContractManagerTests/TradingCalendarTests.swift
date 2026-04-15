import Foundation
import Testing
@testable import ContractManager
import Shared

@Suite("交易日历测试")
struct TradingCalendarTests {
    @Test("黄金有夜盘到02:30")
    func testGoldNightSession() {
        let type = TradingCalendar.nightSessionType(for: "AU")
        #expect(type == .until0230)
    }

    @Test("螺纹钢有夜盘到23:30")
    func testRBNightSession() {
        let type = TradingCalendar.nightSessionType(for: "RB")
        #expect(type == .until2330)
    }

    @Test("豆粕有夜盘到23:00")
    func testMNightSession() {
        let type = TradingCalendar.nightSessionType(for: "M")
        #expect(type == .until2300)
    }

    @Test("股指期货无夜盘")
    func testIFNoNight() {
        let type = TradingCalendar.nightSessionType(for: "IF")
        #expect(type == .none)
    }

    @Test("交易时段查询 - 日盘内")
    func testDaySession() {
        let inSession = TradingCalendar.isInTradingHours(10, 0, productID: "RB", exchange: .SHFE)
        #expect(inSession == true)
    }

    @Test("交易时段查询 - 日盘外")
    func testOutOfDaySession() {
        let inSession = TradingCalendar.isInTradingHours(12, 0, productID: "RB", exchange: .SHFE)
        #expect(inSession == false)
    }

    @Test("交易时段查询 - 夜盘内")
    func testNightSession() {
        let inSession = TradingCalendar.isInTradingHours(22, 0, productID: "AU", exchange: .SHFE)
        #expect(inSession == true)
    }

    @Test("中金所交易时段")
    func testCFFEXSession() {
        let hours = TradingCalendar.tradingHours(for: "IF", exchange: .CFFEX)
        #expect(hours.hasNightSession == false)
        // 中金所日盘 9:30-11:30, 13:00-15:00
        let inSession = TradingCalendar.isInTradingHours(9, 30, productID: "IF", exchange: .CFFEX)
        #expect(inSession == true)
        let outSession = TradingCalendar.isInTradingHours(9, 0, productID: "IF", exchange: .CFFEX)
        #expect(outSession == false)
    }
}
