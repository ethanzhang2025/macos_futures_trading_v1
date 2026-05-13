// v17.170 · 多周期共振叠加（M6 Pro 订阅核心卖点 · trader 实战必备）
//
// 原理：
//   trader 看 15min 入场 · 但需要 60min/daily 大周期方向确认（"不和大周期作对"）
//   把当前周期 bars 向下采样（aggregate-up）到更高周期 · 在高周期上检测 MACD/EMA 金叉死叉
//   把高周期信号按时间戳映射回当前周期的 bar index · 用小箭头标注
//
// 信号类型 v1（4 种 · 简单高信任度）：
//   - MACD 金叉：DIF 上穿 DEA · 看多
//   - MACD 死叉：DIF 下穿 DEA · 看空
//   - EMA  金叉：fast EMA 上穿 slow EMA · 看多
//   - EMA  死叉：fast EMA 下穿 slow EMA · 看空
//
// v2/v3 留：KDJ 金叉/死叉 / RSI 突破 50 / SuperTrend 翻转
//
// 数据方向限制：
//   只能 aggregate-up（小周期 → 大周期）· 不能 aggregate-down（无原始 tick）
//   defaultTargets(for:) 内置常用映射 · 当前周期 ≥ 月线 时返回空
//
// 映射回 base bar：
//   target 周期第 j 根的信号 close time = target_bar[j].openTime + targetPeriod.seconds
//   在 base bars 上二分找最后一根 openTime ≤ close time · 即"高周期一根收盘"覆盖的最后一根低周期 bar
//   实战意义：trader 在 base bar 收盘那一刻可见高周期已确认的信号

import Foundation
import Shared

/// 共振信号类型
public enum ResonanceSignalKind: String, Sendable, Codable, CaseIterable {
    case macdGoldCross
    case macdDeathCross
    case emaGoldCross
    case emaDeathCross

    public var displayName: String {
        switch self {
        case .macdGoldCross:  return "MACD 金叉"
        case .macdDeathCross: return "MACD 死叉"
        case .emaGoldCross:   return "EMA 金叉"
        case .emaDeathCross:  return "EMA 死叉"
        }
    }

    /// +1 看多 · -1 看空
    public var direction: Int {
        switch self {
        case .macdGoldCross, .emaGoldCross:   return 1
        case .macdDeathCross, .emaDeathCross: return -1
        }
    }

    /// 简短代号（overlay marker 内显示用）
    public var shortCode: String {
        switch self {
        case .macdGoldCross:  return "M↑"
        case .macdDeathCross: return "M↓"
        case .emaGoldCross:   return "E↑"
        case .emaDeathCross:  return "E↓"
        }
    }
}

/// 检测到的一条共振信号
public struct ResonanceSignal: Sendable, Equatable {
    public let kind: ResonanceSignalKind
    /// 映射到当前周期 bars 的索引（高周期收盘时刻对应的最后一根低周期 bar）
    public let baseBarIndex: Int
    /// 信号来源的高周期（如 .hour1 / .daily）
    public let sourcePeriod: KLinePeriod
    /// 高周期 bar 的开始时间（便于 debug / HUD 显示）
    public let sourceOpenTime: Date

    public init(kind: ResonanceSignalKind, baseBarIndex: Int, sourcePeriod: KLinePeriod, sourceOpenTime: Date) {
        self.kind = kind
        self.baseBarIndex = baseBarIndex
        self.sourcePeriod = sourcePeriod
        self.sourceOpenTime = sourceOpenTime
    }
}

/// 检测参数
public struct MultiTimeframeResonanceParams: Sendable, Equatable {
    public var macdFast: Int
    public var macdSlow: Int
    public var macdSignal: Int
    public var emaFast: Int
    public var emaSlow: Int
    public var enabledKinds: Set<ResonanceSignalKind>

    public init(
        macdFast: Int = 12,
        macdSlow: Int = 26,
        macdSignal: Int = 9,
        emaFast: Int = 5,
        emaSlow: Int = 20,
        enabledKinds: Set<ResonanceSignalKind> = Set(ResonanceSignalKind.allCases)
    ) {
        self.macdFast = macdFast
        self.macdSlow = macdSlow
        self.macdSignal = macdSignal
        self.emaFast = emaFast
        self.emaSlow = emaSlow
        self.enabledKinds = enabledKinds
    }

    public static let `default` = MultiTimeframeResonanceParams()
}

public enum MultiTimeframeResonance {

    // MARK: - 默认 target 周期映射

    /// 给定 base 周期 · 推荐 2 个更高周期（trader 实战常用阶梯）
    public static func defaultTargets(for basePeriod: KLinePeriod) -> [KLinePeriod] {
        switch basePeriod {
        case .second1, .second3, .second5, .second10, .second15, .second30:
            return [.minute1, .minute5]
        case .minute1:    return [.minute5, .minute15]
        case .minute3:    return [.minute15, .minute30]
        case .minute5:    return [.minute15, .hour1]
        case .minute15:   return [.hour1, .hour4]
        case .minute30:   return [.hour1, .hour4]
        case .hour1:      return [.hour4, .daily]
        case .hour2:      return [.hour4, .daily]
        case .hour4:      return [.daily, .weekly]
        case .daily:      return [.weekly, .monthly]
        case .weekly:     return [.monthly, .quarterly]
        case .monthly:    return [.quarterly, .annual]
        case .quarterly, .semiAnnual, .annual:
            return []
        }
    }

    // MARK: - 聚合：base 周期 bars → target 周期 bars

    /// 按 epoch 整数桶聚合 · 跨周期开盘对齐由 (epoch / targetSeconds) 整除决定
    /// 注意：目标周期必须严格大于 base · 否则返回空
    public static func aggregate(bars: [KLine], targetPeriod: KLinePeriod) -> [KLine] {
        guard !bars.isEmpty else { return [] }
        let bucketSize = targetPeriod.seconds
        guard bucketSize > 0 else { return [] }
        guard let basePeriod = bars.first?.period, basePeriod.seconds < bucketSize else { return [] }

        var out: [KLine] = []
        out.reserveCapacity(bars.count / max(1, bucketSize / max(1, basePeriod.seconds)) + 1)
        var currentBucketStart: TimeInterval = -1
        var open: Decimal = 0
        var high: Decimal = 0
        var low: Decimal = 0
        var close: Decimal = 0
        var volume: Int = 0
        var turnover: Decimal = 0
        var openInterest: Decimal = 0
        var instrumentID: String = bars[0].instrumentID
        var bucketHasData = false

        func flush() {
            guard bucketHasData else { return }
            out.append(KLine(
                instrumentID: instrumentID,
                period: targetPeriod,
                openTime: Date(timeIntervalSince1970: currentBucketStart),
                open: open, high: high, low: low, close: close,
                volume: volume,
                openInterest: openInterest,
                turnover: turnover
            ))
        }

        for bar in bars {
            let t = bar.openTime.timeIntervalSince1970
            let bucketStart = floor(t / Double(bucketSize)) * Double(bucketSize)
            if bucketStart != currentBucketStart {
                flush()
                currentBucketStart = bucketStart
                instrumentID = bar.instrumentID
                open = bar.open
                high = bar.high
                low = bar.low
                close = bar.close
                volume = bar.volume
                turnover = bar.turnover
                openInterest = bar.openInterest
                bucketHasData = true
            } else {
                if bar.high > high { high = bar.high }
                if bar.low < low { low = bar.low }
                close = bar.close
                volume += bar.volume
                turnover += bar.turnover
                openInterest = bar.openInterest
            }
        }
        flush()
        return out
    }

    // MARK: - 信号检测（单 target 周期）

    /// 在已聚合的 target bars 上跑 MACD/EMA · 输出 (索引, 信号类型) 列表
    /// 索引为 target bars 内部索引（之后再映射回 base bars）
    public static func detectSignals(
        on targetBars: [KLine],
        params: MultiTimeframeResonanceParams = .default
    ) throws -> [(barIndex: Int, kind: ResonanceSignalKind)] {
        // 不在此处做"bars 足够多"的预检 · MACD/EMA calculate 会返回 nil-padded 数列 · detectCrosses 自动跳过 nil
        // 这样无论 enabledKinds 怎么子集化都能正确处理（避免 macdSlow 默认 26 时 emaSlow=5 测被误拒）
        guard !targetBars.isEmpty else { return [] }
        let kline = KLineSeries(
            opens: targetBars.map(\.open),
            highs: targetBars.map(\.high),
            lows: targetBars.map(\.low),
            closes: targetBars.map(\.close),
            volumes: targetBars.map(\.volume),
            openInterests: targetBars.map { _ in 0 }
        )
        var out: [(Int, ResonanceSignalKind)] = []

        // MACD：DIF 上/下穿 DEA
        if params.enabledKinds.contains(.macdGoldCross) || params.enabledKinds.contains(.macdDeathCross) {
            let macdParams: [Decimal] = [
                Decimal(params.macdFast), Decimal(params.macdSlow), Decimal(params.macdSignal)
            ]
            let series = try MACD.calculate(kline: kline, params: macdParams)
            let dif = series[0].values
            let dea = series[1].values
            for cross in detectCrosses(a: dif, b: dea) {
                let kind: ResonanceSignalKind = cross.isGold ? .macdGoldCross : .macdDeathCross
                if params.enabledKinds.contains(kind) {
                    out.append((cross.index, kind))
                }
            }
        }

        // EMA：fast 上/下穿 slow
        if params.enabledKinds.contains(.emaGoldCross) || params.enabledKinds.contains(.emaDeathCross) {
            let fast = try EMA.calculate(kline: kline, params: [Decimal(params.emaFast)])[0].values
            let slow = try EMA.calculate(kline: kline, params: [Decimal(params.emaSlow)])[0].values
            for cross in detectCrosses(a: fast, b: slow) {
                let kind: ResonanceSignalKind = cross.isGold ? .emaGoldCross : .emaDeathCross
                if params.enabledKinds.contains(kind) {
                    out.append((cross.index, kind))
                }
            }
        }

        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - 完整流水线：base bars + target periods → 映射后的信号列表

    /// trader 真正调用的入口 · 输入当前周期 bars + 要叠加的 target 周期列表（如 [.hour1, .daily]）
    /// 输出已映射到 base bar index 的 ResonanceSignal 列表（按 baseBarIndex 升序）
    public static func detect(
        baseBars: [KLine],
        targetPeriods: [KLinePeriod],
        params: MultiTimeframeResonanceParams = .default
    ) throws -> [ResonanceSignal] {
        guard !baseBars.isEmpty, !targetPeriods.isEmpty else { return [] }
        var result: [ResonanceSignal] = []
        for target in targetPeriods {
            let aggregated = aggregate(bars: baseBars, targetPeriod: target)
            guard !aggregated.isEmpty else { continue }
            let signals = try detectSignals(on: aggregated, params: params)
            for (j, kind) in signals {
                let closeTime = aggregated[j].openTime.timeIntervalSince1970 + Double(target.seconds)
                if let mapped = mapToBaseBar(closeTime: closeTime, baseBars: baseBars) {
                    result.append(ResonanceSignal(
                        kind: kind,
                        baseBarIndex: mapped,
                        sourcePeriod: target,
                        sourceOpenTime: aggregated[j].openTime
                    ))
                }
            }
        }
        return result.sorted {
            if $0.baseBarIndex != $1.baseBarIndex { return $0.baseBarIndex < $1.baseBarIndex }
            return $0.sourcePeriod.seconds < $1.sourcePeriod.seconds
        }
    }

    // MARK: - helpers

    /// 二分：找最后一根 openTime ≤ closeTime 的 base bar · 找不到（closeTime 早于第一根）返回 nil
    private static func mapToBaseBar(closeTime: TimeInterval, baseBars: [KLine]) -> Int? {
        if baseBars.isEmpty { return nil }
        let first = baseBars[0].openTime.timeIntervalSince1970
        if closeTime < first { return nil }
        var lo = 0
        var hi = baseBars.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if baseBars[mid].openTime.timeIntervalSince1970 <= closeTime {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// 通用穿越检测：i>=1 时 · a[i-1]<b[i-1] && a[i]>=b[i] → 金叉；反之 → 死叉
    /// 端点 nil 跳过
    private static func detectCrosses(a: [Decimal?], b: [Decimal?]) -> [(index: Int, isGold: Bool)] {
        guard a.count == b.count, a.count >= 2 else { return [] }
        var out: [(Int, Bool)] = []
        for i in 1..<a.count {
            guard let a0 = a[i - 1], let b0 = b[i - 1], let a1 = a[i], let b1 = b[i] else { continue }
            if a0 < b0 && a1 >= b1 {
                out.append((i, true))
            } else if a0 > b0 && a1 <= b1 {
                out.append((i, false))
            }
        }
        return out
    }
}
