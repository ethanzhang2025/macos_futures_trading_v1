// 价差套利 alert 检测器（v15.55 · ⌘⌥W · 全市场 26 对扫描）
//
// 套利 trader 用法：
//   - 同时盯 12 跨品种 + 14 跨期 = 26 对 · 找 |Z| ≥ 阈值的偏离机会
//   - 偏离 ±2σ → 反向开仓做 mean-reverting · 偏离 ±3σ → 极值机会
//   - 与 ⌘⌥A 异常品种监控互补：A=单品种异动 · W=价差对偏离
//
// 数据流：
//   - 跨品种：mock 两腿 K 线（与 SpreadWindow.MockSpreadData 同算法）→ SpreadCalculator → SpreadValue → SpreadStatistics
//   - 跨期：CalendarSpreadCalculator.generateMockSeries → toSpreadValues → SpreadStatistics
//   - 评估：|zScore| ≥ threshold 触发
//
// v1 mock · v2 接 CTP 真行情后 evaluate(values:) 不变 · 仅 scanAll 内部数据源切换

import Foundation
import Shared

/// 单条价差 alert 事件
public struct SpreadAlertEvent: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let spreadID: String          // "rb-hc" / "rb-05-10"
    public let spreadName: String        // "螺纹热卷" / "螺纹 5-10"
    public let kind: Kind                // 跨品种 / 跨期
    public let categoryDisplay: String   // "跨品种" / "黑色系跨期"
    public let zScore: Double            // 当前 Z-score（带符号）
    public let absZ: Double              // |zScore|（排序 / 严重度用）
    public let currentValue: Double
    public let mean: Double
    public let stdDev: Double
    public let upperBand: Double         // mean + 2σ
    public let lowerBand: Double         // mean - 2σ
    public let direction: Direction
    public let strategy: String          // 操作建议
    public let unitLabel: String         // "元/吨" / "点"
    public let detectedAt: Date

    public enum Kind: String, Sendable, Codable {
        case crossInstrument  // 跨品种
        case calendar         // 跨期
    }

    public enum Direction: String, Sendable, Codable {
        case upperBreached    // 价差偏高（>= upperBand）→ 做空价差
        case lowerBreached    // 价差偏低（<= lowerBand）→ 做多价差

        public var displayName: String {
            switch self {
            case .upperBreached: return "上轨突破"
            case .lowerBreached: return "下轨突破"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        spreadID: String, spreadName: String, kind: Kind, categoryDisplay: String,
        zScore: Double, currentValue: Double, mean: Double, stdDev: Double,
        upperBand: Double, lowerBand: Double, direction: Direction,
        strategy: String, unitLabel: String, detectedAt: Date = Date()
    ) {
        self.id = id
        self.spreadID = spreadID
        self.spreadName = spreadName
        self.kind = kind
        self.categoryDisplay = categoryDisplay
        self.zScore = zScore
        self.absZ = abs(zScore)
        self.currentValue = currentValue
        self.mean = mean
        self.stdDev = stdDev
        self.upperBand = upperBand
        self.lowerBand = lowerBand
        self.direction = direction
        self.strategy = strategy
        self.unitLabel = unitLabel
        self.detectedAt = detectedAt
    }
}

/// 检测阈值
public struct SpreadAlertThresholds: Sendable, Equatable {
    /// |zScore| 触发阈值（默认 2.0 · ±2σ 经典套利信号）
    public var zThreshold: Double
    /// 是否扫描跨品种对（12 对）
    public var includeCrossInstrument: Bool
    /// 是否扫描跨期对（14 对）
    public var includeCalendar: Bool
    /// 最小样本数（不足时跳过 · 防早期不稳定 stat 误触发）
    public var minSamples: Int

    public init(
        zThreshold: Double = 2.0,
        includeCrossInstrument: Bool = true,
        includeCalendar: Bool = true,
        minSamples: Int = 30
    ) {
        self.zThreshold = zThreshold
        self.includeCrossInstrument = includeCrossInstrument
        self.includeCalendar = includeCalendar
        self.minSamples = minSamples
    }

    public static let `default` = SpreadAlertThresholds()
}

public enum SpreadAlertDetector {

    /// 全市场扫描 · 26 对（12 跨品种 + 14 跨期）+ 用户自定义对（可选 · v15.75）
    /// - Parameter customPairs: 用户自建跨品种对（与 SpreadPresets.all 同模式扫描 · 受 includeCrossInstrument 控）
    public static func scanAll(
        thresholds: SpreadAlertThresholds = .default,
        customPairs: [SpreadPair] = [],
        now: Date = Date()
    ) -> [SpreadAlertEvent] {
        var events: [SpreadAlertEvent] = []

        if thresholds.includeCrossInstrument {
            for pair in SpreadPresets.all {
                let values = mockCrossInstrumentSeries(for: pair, count: 200)
                if let evt = evaluate(values: values, pair: pair, thresholds: thresholds, now: now) {
                    events.append(evt)
                }
            }
            // v15.75 · 用户自定义对（与 preset 同 mock 算法 · trader 看到一致量纲）
            for pair in customPairs {
                let values = mockCrossInstrumentSeries(for: pair, count: 200)
                if let evt = evaluate(values: values, pair: pair, thresholds: thresholds, now: now) {
                    events.append(evt)
                }
            }
        }

        if thresholds.includeCalendar {
            for pair in CalendarSpreadPresets.all {
                let basePrice = defaultBasePrice(pair.underlyingID)
                let cal = CalendarSpreadCalculator.generateMockSeries(for: pair, basePrice: basePrice, count: 200)
                let values = CalendarSpreadCalculator.toSpreadValues(cal)
                if let evt = evaluate(values: values, pair: pair, thresholds: thresholds, now: now) {
                    events.append(evt)
                }
            }
        }

        events.sort { $0.absZ > $1.absZ }
        return events
    }

    // MARK: - 评估单 spread series（纯函数 · v2 接 CTP 真行情时唯一保留的入口）

    /// 跨品种评估
    public static func evaluate(
        values: [SpreadValue],
        pair: SpreadPair,
        thresholds: SpreadAlertThresholds,
        now: Date = Date()
    ) -> SpreadAlertEvent? {
        guard values.count >= thresholds.minSamples else { return nil }
        let stat = SpreadStatisticsCalculator.compute(values)
        let z = NSDecimalNumber(decimal: stat.zScore).doubleValue
        guard abs(z) >= thresholds.zThreshold else { return nil }
        let direction: SpreadAlertEvent.Direction = z >= 0 ? .upperBreached : .lowerBreached
        let strategy = crossInstrumentStrategy(pair: pair, direction: direction)
        return SpreadAlertEvent(
            spreadID: pair.id,
            spreadName: pair.name,
            kind: .crossInstrument,
            categoryDisplay: pair.category.rawValue,
            zScore: z,
            currentValue: NSDecimalNumber(decimal: stat.current).doubleValue,
            mean: NSDecimalNumber(decimal: stat.mean).doubleValue,
            stdDev: NSDecimalNumber(decimal: stat.stdDev).doubleValue,
            upperBand: NSDecimalNumber(decimal: stat.upperBand2σ).doubleValue,
            lowerBand: NSDecimalNumber(decimal: stat.lowerBand2σ).doubleValue,
            direction: direction,
            strategy: strategy,
            unitLabel: pair.unitLabel,
            detectedAt: now
        )
    }

    /// 跨期评估
    public static func evaluate(
        values: [SpreadValue],
        pair: CalendarSpreadPair,
        thresholds: SpreadAlertThresholds,
        now: Date = Date()
    ) -> SpreadAlertEvent? {
        guard values.count >= thresholds.minSamples else { return nil }
        let stat = SpreadStatisticsCalculator.compute(values)
        let z = NSDecimalNumber(decimal: stat.zScore).doubleValue
        guard abs(z) >= thresholds.zThreshold else { return nil }
        let direction: SpreadAlertEvent.Direction = z >= 0 ? .upperBreached : .lowerBreached
        let strategy = calendarStrategy(pair: pair, direction: direction)
        return SpreadAlertEvent(
            spreadID: pair.id,
            spreadName: pair.name,
            kind: .calendar,
            categoryDisplay: pair.category.rawValue,
            zScore: z,
            currentValue: NSDecimalNumber(decimal: stat.current).doubleValue,
            mean: NSDecimalNumber(decimal: stat.mean).doubleValue,
            stdDev: NSDecimalNumber(decimal: stat.stdDev).doubleValue,
            upperBand: NSDecimalNumber(decimal: stat.upperBand2σ).doubleValue,
            lowerBand: NSDecimalNumber(decimal: stat.lowerBand2σ).doubleValue,
            direction: direction,
            strategy: strategy,
            unitLabel: "元",
            detectedAt: now
        )
    }

    // MARK: - 策略建议

    private static func crossInstrumentStrategy(pair: SpreadPair, direction: SpreadAlertEvent.Direction) -> String {
        let leg1 = pair.leg1.instrumentID
        let leg2 = pair.leg2.instrumentID
        switch direction {
        case .upperBreached:
            return "做空价差 · 卖 \(leg1) + 买 \(leg2)（mean-revert 回归）"
        case .lowerBreached:
            return "做多价差 · 买 \(leg1) + 卖 \(leg2)（mean-revert 回归）"
        }
    }

    private static func calendarStrategy(pair: CalendarSpreadPair, direction: SpreadAlertEvent.Direction) -> String {
        let near = pair.nearMonthID
        let far = pair.farMonthID
        switch direction {
        case .upperBreached:
            return "做空价差 · 卖 \(far) + 买 \(near)（contango 极值）"
        case .lowerBreached:
            return "做多价差 · 买 \(far) + 卖 \(near)（backwardation 极值）"
        }
    }

    // MARK: - mock 数据生成（跨品种）

    /// 跨品种 mock spread 时序（与 SpreadWindow.MockSpreadData 同算法 · 两腿不同 seed）
    /// v2 接 CTP 真历史 K 线后整段废弃
    /// v15.60 改 public · SpreadAlertWindow timer 周期喂 AlertEvaluator.onSpreadValue 用
    public static func mockCrossInstrumentSeries(for pair: SpreadPair, count: Int) -> [SpreadValue] {
        let basePrice1 = defaultBasePrice(pair.leg1.instrumentID)
        let basePrice2 = defaultBasePrice(pair.leg2.instrumentID)
        let leg1 = mockBars(instrumentID: pair.leg1.instrumentID, basePrice: basePrice1,
                            count: count, seed: pair.leg1.instrumentID.hashValue)
        let leg2 = mockBars(instrumentID: pair.leg2.instrumentID, basePrice: basePrice2,
                            count: count, seed: pair.id.hashValue ^ 0x1F)
        return SpreadCalculator.calculate(pair: pair, leg1Bars: leg1, leg2Bars: leg2)
    }

    private static func mockBars(instrumentID: String, basePrice: Double,
                                 count: Int, seed: Int) -> [KLine] {
        var rng = SpreadAlertSeededRNG(seed: UInt64(bitPattern: Int64(seed)))
        let stepSec: TimeInterval = 86400  // 日线（与 SpreadWindow 默认一致）
        let baseTime = Date().addingTimeInterval(-Double(count) * stepSec)
        var price = basePrice
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        for i in 0..<count {
            let cycle = sin(Double(i) * 0.1) * basePrice * 0.005
            let noise = rng.nextDouble(in: -0.002...0.002) * basePrice
            price = basePrice + cycle + noise + (price - basePrice) * 0.95
            let high = price + abs(noise) + 0.5
            let low = price - abs(noise) - 0.5
            bars.append(KLine(
                instrumentID: instrumentID, period: .daily,
                openTime: baseTime.addingTimeInterval(TimeInterval(i) * stepSec),
                open: Decimal(price - noise * 0.3),
                high: Decimal(high), low: Decimal(low), close: Decimal(price),
                volume: 100, openInterest: 0, turnover: 0
            ))
        }
        return bars
    }

    /// 默认基础价（按合约 ID · 与 SpreadWindow.defaultBasePrice 同步）
    /// v2 接 CTP 后从 instrument metadata 拿
    /// v15.60 改 public · SpreadAlertWindow timer 喂跨期 series 时反查近月底价用
    public static func defaultBasePrice(_ id: String) -> Double {
        switch id {
        case "RB0", "RB":  return 3245
        case "HC0", "HC":  return 3450
        case "I0",  "I":   return 812.5
        case "J0",  "J":   return 1925
        case "JM0", "JM":  return 1180
        case "M0",  "M":   return 3180
        case "Y0",  "Y":   return 8240
        case "P0",  "P":   return 8920
        case "OI0", "OI":  return 9180
        case "C0",  "C":   return 2480
        case "SR0", "SR":  return 6320
        case "CF0", "CF":  return 14580
        case "AU0", "AU":  return 612.5
        case "AG0", "AG":  return 7890
        case "CU0", "CU":  return 78650
        case "AL0", "AL":  return 19450
        case "IF0", "IF":  return 3856.4
        case "IH0", "IH":  return 2820.8
        case "IC0", "IC":  return 5680.2
        case "IM0", "IM":  return 6420.5
        case "T0",  "T":   return 104.85
        case "TF0", "TF":  return 103.42
        case "TS0", "TS":  return 101.85
        case "TL0", "TL":  return 108.20
        case "SC0", "SC":  return 485.2
        case "RU0", "RU":  return 13420
        default:           return 1000
        }
    }
}

// MARK: - SeededRNG（XorShift64 · 仅本模块用 · 不污染外部）

private struct SpreadAlertSeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xCAFE_BABE : seed }
    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        let u = Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}
