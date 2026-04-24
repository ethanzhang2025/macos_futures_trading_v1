import Foundation
import Shared

/// K线合成器 — 从Tick实时合成任意周期K线
public final class KLineBuilder: @unchecked Sendable {
    private let instrumentID: String
    private let period: KLinePeriod
    private var currentBar: KLine?
    private var completedBars: [KLine] = []
    private var lastVolume: Int = 0  // 用于计算增量成交量

    public init(instrumentID: String, period: KLinePeriod) {
        self.instrumentID = instrumentID
        self.period = period
    }

    /// 输入一个Tick，返回是否产生了新的完成K线
    public func onTick(_ tick: Tick) -> KLine? {
        guard tick.instrumentID == instrumentID else { return nil }

        let barTime = alignTime(tick: tick)
        let tickVolume = max(0, tick.volume - lastVolume)
        lastVolume = tick.volume

        if var bar = currentBar {
            if bar.openTime == barTime {
                // 更新当前K线
                if tick.lastPrice > bar.high { bar.high = tick.lastPrice }
                if tick.lastPrice < bar.low { bar.low = tick.lastPrice }
                bar.close = tick.lastPrice
                bar.volume += tickVolume
                bar.openInterest = tick.openInterest
                bar.turnover += tick.turnover
                currentBar = bar
                return nil
            } else {
                // 当前K线完成，开始新K线
                let completed = bar
                completedBars.append(completed)
                currentBar = newBar(tick: tick, time: barTime, volume: tickVolume)
                return completed
            }
        } else {
            // 第一根K线
            currentBar = newBar(tick: tick, time: barTime, volume: tickVolume)
            return nil
        }
    }

    /// 获取当前未完成的K线
    public var currentKLine: KLine? { currentBar }

    /// 获取所有已完成的K线
    public var allBars: [KLine] { completedBars }

    /// 获取所有K线（含当前未完成的）
    public var allBarsIncludingCurrent: [KLine] {
        var bars = completedBars
        if let current = currentBar { bars.append(current) }
        return bars
    }

    /// 重置
    public func reset() {
        currentBar = nil
        completedBars.removeAll()
        lastVolume = 0
    }

    // MARK: - Private

    private func newBar(tick: Tick, time: Date, volume: Int) -> KLine {
        KLine(
            instrumentID: instrumentID,
            period: period,
            openTime: time,
            open: tick.lastPrice,
            high: tick.lastPrice,
            low: tick.lastPrice,
            close: tick.lastPrice,
            volume: volume,
            openInterest: tick.openInterest,
            turnover: tick.turnover
        )
    }

    /// 将Tick时间对齐到K线周期的起始时间
    private func alignTime(tick: Tick) -> Date {
        let components = tick.updateTime.split(separator: ":")
        guard components.count >= 3,
              let hour = Int(components[0]),
              let minute = Int(components[1]),
              let second = Int(components[2]) else {
            return Date()
        }

        // 用tradingDay构造基础日期
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let baseDate = formatter.date(from: tick.tradingDay) ?? Date()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let seconds = period.seconds
        if seconds < 86400 {
            // 日内周期：对齐到周期的整数倍
            let totalSeconds = hour * 3600 + minute * 60 + second
            let aligned = (totalSeconds / seconds) * seconds
            let alignedHour = aligned / 3600
            let alignedMinute = (aligned % 3600) / 60
            let alignedSecond = aligned % 60

            var comps = calendar.dateComponents([.year, .month, .day], from: baseDate)
            comps.hour = alignedHour
            comps.minute = alignedMinute
            comps.second = alignedSecond
            return calendar.date(from: comps) ?? baseDate
        } else {
            // 日线及以上：直接用tradingDay
            return baseDate
        }
    }
}
