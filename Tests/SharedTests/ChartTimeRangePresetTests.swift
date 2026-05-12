// v17.138 · ChartTimeRangePreset 单测

import Testing
import Foundation
@testable import Shared

@Suite("ChartTimeRangePreset · v17.138 时间范围预设")
struct ChartTimeRangePresetTests {

    @Test("displayName 国际惯例 1D/1W/1M/3M/6M/1Y")
    func displayNames() {
        #expect(ChartTimeRangePreset.oneDay.displayName == "1D")
        #expect(ChartTimeRangePreset.oneWeek.displayName == "1W")
        #expect(ChartTimeRangePreset.oneMonth.displayName == "1M")
        #expect(ChartTimeRangePreset.threeMonths.displayName == "3M")
        #expect(ChartTimeRangePreset.sixMonths.displayName == "6M")
        #expect(ChartTimeRangePreset.oneYear.displayName == "1Y")
    }

    @Test("各 case 单调递增 · 1D < 1W < 1M < 3M < 6M < 1Y")
    func secondsMonotonic() {
        let cases = ChartTimeRangePreset.allCases
        for i in 1..<cases.count {
            #expect(cases[i - 1].seconds < cases[i].seconds)
        }
    }

    @Test("barCount · 1D × 5m = 288 bars（24h × 12 bars/h）")
    func dayOnFiveMinute() {
        #expect(ChartTimeRangePreset.oneDay.barCount(for: .minute5) == 288)
    }

    @Test("barCount · 1W × 1h = 168 bars（7 × 24 = 168）")
    func weekOnHour() {
        #expect(ChartTimeRangePreset.oneWeek.barCount(for: .hour1) == 168)
    }

    @Test("barCount · 1M × daily = 30 bars · 3M × daily = 90 · 1Y × daily = 365")
    func monthsOnDaily() {
        #expect(ChartTimeRangePreset.oneMonth.barCount(for: .daily) == 30)
        #expect(ChartTimeRangePreset.threeMonths.barCount(for: .daily) == 90)
        #expect(ChartTimeRangePreset.sixMonths.barCount(for: .daily) == 180)
        #expect(ChartTimeRangePreset.oneYear.barCount(for: .daily) == 365)
    }

    @Test("barCount · period > 范围（1D × weekly）→ floor 到至少 10 bars")
    func longerPeriodThanRangeClamps() {
        // 1D = 86400s · weekly = 604800s · ceil(86400/604800) = 1 → clamp 10
        #expect(ChartTimeRangePreset.oneDay.barCount(for: .weekly) == 10)
    }

    @Test("barCount · 向上取整（不留半根丢失）")
    func ceilDivision() {
        // 1W = 604800 · minute30 = 1800 · 604800/1800 = 336 整除
        #expect(ChartTimeRangePreset.oneWeek.barCount(for: .minute30) == 336)
        // 1M = 2592000 · hour4 = 14400 · 2592000/14400 = 180 整除
        #expect(ChartTimeRangePreset.oneMonth.barCount(for: .hour4) == 180)
    }
}
