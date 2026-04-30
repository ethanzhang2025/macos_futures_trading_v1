// WP-52 模块 4 · 预警评估器
// 职责：onTick(_) → 评估所有 active 预警 → 触发 → 写 history + dispatch 通知 + emit AsyncStream
//
// 设计要点：
// - actor 隔离并发安全
// - 维护 perInstrument 上一次 Tick（用于 crossAbove/crossBelow 判断）
// - 维护 perInstrument volume 滑动窗口（用于 volumeSpike 判断）
// - 维护 perInstrument 价格时间窗口（用于 priceMoveSpike 判断）
// - 频控冷却：Alert.cooldownSeconds 控制（边界条件下不重复疯狂触发，A08 验收硬要求）
// - 时间外置：通过 now 参数注入，便于测试可控

import Foundation
import Shared
import IndicatorCore

/// 单次触发事件 · AsyncStream 推送给 caller（UI 更新 / 集成测试）
public struct AlertTriggeredEvent: Sendable, Equatable, Hashable {
    public let alertID: UUID
    public let alertName: String
    public let instrumentID: String
    public let triggerPrice: Decimal
    public let triggeredAt: Date
    public let message: String

    public init(
        alertID: UUID,
        alertName: String,
        instrumentID: String,
        triggerPrice: Decimal,
        triggeredAt: Date,
        message: String
    ) {
        self.alertID = alertID
        self.alertName = alertName
        self.instrumentID = instrumentID
        self.triggerPrice = triggerPrice
        self.triggeredAt = triggeredAt
        self.message = message
    }

    /// 转为 NotificationEvent（同结构 · 解耦 evaluator 与通知层）
    public var notificationEvent: NotificationEvent {
        NotificationEvent(
            alertID: alertID,
            alertName: alertName,
            instrumentID: instrumentID,
            triggerPrice: triggerPrice,
            triggeredAt: triggeredAt,
            message: message
        )
    }
}

/// 预警评估器
public actor AlertEvaluator {

    // MARK: - 依赖

    private let history: AlertHistoryStore
    private let dispatcher: NotificationDispatcher

    // MARK: - 状态

    private var alerts: [UUID: Alert] = [:]
    /// 上一次 Tick（按 instrumentID 维护，用于 cross 判断）
    private var previousPrices: [String: Decimal] = [:]
    /// 成交量滑动窗口（按 instrumentID）· 仅 volumeSpike 触发时用
    private var volumeWindows: [String: [Int]] = [:]
    /// 价格时间窗口（按 instrumentID 累积 N 秒内的 (price, timestamp)）
    private var priceWindows: [String: [(price: Decimal, timestamp: Date)]] = [:]
    /// K 线滑动窗口（按 instrumentID + period）· 指标条件预警评估用 · 最大 maxKlineWindow 根
    private var klineWindows: [String: [KLinePeriod: [KLine]]] = [:]
    /// 已记录 baseline 的指标预警 ID 集合（首次评估只记 baseline 不触发 · 防历史 K 线导入误触发）
    /// 仅用 Set 标记存在性 · 无需保存上次的指标值（cross 比较直接读 kline 末两根）
    private var indicatorBaselineRecorded: Set<UUID> = []
    /// K 线窗口最大长度（500 根足够覆盖 MA(500) / MACD(26) / RSI(14) 等所有内置指标 warm-up）
    private let maxKlineWindow: Int = 500
    /// 状态广播
    private var continuations: [UUID: AsyncStream<AlertTriggeredEvent>.Continuation] = [:]

    // MARK: - 初始化

    public init(
        history: AlertHistoryStore = InMemoryAlertHistoryStore(),
        dispatcher: NotificationDispatcher = NotificationDispatcher()
    ) {
        self.history = history
        self.dispatcher = dispatcher
    }

    // MARK: - 订阅事件

    /// 订阅触发事件（多订阅者；含初始无 yield）
    public func observe() -> AsyncStream<AlertTriggeredEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - 预警 CRUD

    /// 添加预警（已存在 id 则覆盖）
    public func addAlert(_ alert: Alert) {
        alerts[alert.id] = alert
    }

    /// 移除预警 + 联动清除其历史
    public func removeAlert(id: UUID) async {
        alerts[id] = nil
        indicatorBaselineRecorded.remove(id)
        try? await history.clear(alertID: id)
    }

    /// 更新预警（保留 lastTriggeredAt 不被覆盖；用户改 condition/name 等不应重置冷却）
    /// condition 变更时 reset 指标 baseline · 防止旧条件的 baseline 误判新条件 cross
    @discardableResult
    public func updateAlert(_ alert: Alert) -> Bool {
        guard let existing = alerts[alert.id] else { return false }
        var merged = alert
        merged.lastTriggeredAt = existing.lastTriggeredAt
        alerts[alert.id] = merged
        if existing.condition != alert.condition {
            indicatorBaselineRecorded.remove(alert.id)
        }
        return true
    }

    /// 暂停预警
    @discardableResult
    public func pauseAlert(id: UUID) -> Bool {
        guard alerts[id] != nil else { return false }
        alerts[id]?.status = .paused
        return true
    }

    /// 恢复预警（仅 paused → active；其他状态忽略）
    @discardableResult
    public func resumeAlert(id: UUID) -> Bool {
        guard let alert = alerts[id], alert.status == .paused else { return false }
        alerts[id]?.status = .active
        return true
    }

    /// 当前所有预警（测试 / UI 列表用）
    public func allAlerts() -> [Alert] {
        Array(alerts.values)
    }

    // MARK: - 评估入口

    /// onTick · 主驱动方法
    /// 上层 caller 应在每个 Tick 到达时调用本方法
    /// - Parameters:
    ///   - tick: 当前 Tick
    ///   - now: 当前时间（默认 Date()，注入便于测试）
    public func onTick(_ tick: Tick, now: Date = Date()) async {
        defer { previousPrices[tick.instrumentID] = tick.lastPrice }

        let prevPrice = previousPrices[tick.instrumentID]

        // 维护成交量窗口（最大 1000 周期，足够 v1）
        appendVolume(tick.volume, for: tick.instrumentID, capacity: 1000)
        // 维护价格时间窗口（按 timestamp 自动 truncate 到最大需求窗口）
        appendPriceWindow(price: tick.lastPrice, timestamp: now, for: tick.instrumentID, maxSeconds: 3600)

        // 评估该 instrumentID 的所有 active alerts
        for alert in alerts.values where alert.instrumentID == tick.instrumentID && alert.canTrigger(at: now) {
            if let event = evaluate(alert: alert, tick: tick, prevPrice: prevPrice, now: now) {
                await fire(event: event, alert: alert, now: now)
            }
        }
    }

    /// onBar · 完成 K 线驱动方法（指标条件预警）
    /// ChartScene 在 .completedBar 时与 onTick 并行调用 · spec.period 不匹配时不评估
    /// - Parameters:
    ///   - bar: 完成的 K 线
    ///   - instrumentID: 合约（与 bar.instrumentID 一致 · 显式传入避免 caller 看不见）
    ///   - period: K 线周期（与 bar.period 一致）
    ///   - now: 当前时间（默认 Date()，注入便于测试）
    public func onBar(_ bar: KLine, instrumentID: String, period: KLinePeriod, now: Date = Date()) async {
        // 1. 维护该 (instrumentID, period) 的 K 线滑动窗口
        var perInstrument = klineWindows[instrumentID] ?? [:]
        var window = perInstrument[period] ?? []
        window.append(bar)
        if window.count > maxKlineWindow {
            window.removeFirst(window.count - maxKlineWindow)
        }
        perInstrument[period] = window
        klineWindows[instrumentID] = perInstrument

        // 2. 评估该 instrumentID + period 的所有 active 指标预警
        for alert in alerts.values where alert.instrumentID == instrumentID && alert.canTrigger(at: now) {
            guard case .indicator(let spec) = alert.condition, spec.period == period else { continue }
            if let event = evaluateIndicator(alert: alert, spec: spec, kline: window, now: now) {
                await fire(event: event, alert: alert, now: now)
            }
        }
    }

    // MARK: - 私有：评估各类条件

    private func evaluate(alert: Alert, tick: Tick, prevPrice: Decimal?, now: Date) -> AlertTriggeredEvent? {
        let outcome: (matched: Bool, message: String) = {
            switch alert.condition {
            case .priceAbove(let target):
                return (tick.lastPrice >= target, "价格 \(tick.lastPrice) 高于 \(target)")
            case .priceBelow(let target):
                return (tick.lastPrice <= target, "价格 \(tick.lastPrice) 低于 \(target)")
            case .priceCrossAbove(let target):
                guard let prev = prevPrice else { return (false, "") }
                return (prev < target && tick.lastPrice >= target, "价格上穿 \(target)（前 \(prev) → 现 \(tick.lastPrice)）")
            case .priceCrossBelow(let target):
                guard let prev = prevPrice else { return (false, "") }
                return (prev > target && tick.lastPrice <= target, "价格下穿 \(target)（前 \(prev) → 现 \(tick.lastPrice)）")
            case .horizontalLineTouched(_, let price):
                guard let prev = prevPrice else { return (false, "") }
                let crossed = (prev < price && tick.lastPrice >= price) || (prev > price && tick.lastPrice <= price)
                return (crossed, "价格触及水平线 \(price)（前 \(prev) → 现 \(tick.lastPrice)）")
            case .volumeSpike(let multiple, let windowBars):
                guard let avg = averageVolume(for: tick.instrumentID, lastNBars: windowBars), avg > 0 else { return (false, "") }
                let ratio = Decimal(tick.volume) / Decimal(avg)
                return (ratio >= multiple, "成交量 \(tick.volume) 是近 \(windowBars) 期均值 \(avg) 的 \(ratio) 倍（阈值 \(multiple)）")
            case .priceMoveSpike(let percentThreshold, let windowSeconds):
                guard let move = priceMovePercent(for: tick.instrumentID, currentPrice: tick.lastPrice, now: now, windowSeconds: windowSeconds) else {
                    return (false, "")
                }
                return (abs(move) >= percentThreshold, "\(windowSeconds)s 内价格变化 \(move * 100)%（阈值 \(percentThreshold * 100)%）")
            case .indicator:
                // 指标条件预警走 onBar 路径 · onTick 不评估
                return (false, "")
            }
        }()

        guard outcome.matched else { return nil }
        return AlertTriggeredEvent(
            alertID: alert.id,
            alertName: alert.name,
            instrumentID: alert.instrumentID,
            triggerPrice: tick.lastPrice,
            triggeredAt: now,
            message: outcome.message
        )
    }

    private func fire(event: AlertTriggeredEvent, alert: Alert, now: Date) async {
        // 更新频控时间戳：cooldown 仅靠 lastTriggeredAt 时间窗判断
        // (AlertStatus.triggered 留 v2 用于 UI 显示更细的状态徽章；此处不写中间态)
        alerts[alert.id]?.lastTriggeredAt = now

        // 写 history
        let entry = AlertHistoryEntry(
            alertID: alert.id,
            alertName: alert.name,
            instrumentID: alert.instrumentID,
            conditionSnapshot: alert.condition,
            triggeredAt: now,
            triggerPrice: event.triggerPrice,
            message: event.message
        )
        try? await history.append(entry)

        // 广播 stream
        for cont in continuations.values { cont.yield(event) }

        // 通知（按 Alert.channels 选择性广播）
        if !alert.channels.isEmpty {
            await dispatcher.dispatch(event.notificationEvent, to: alert.channels)
        }
    }

    // MARK: - 私有：滑动窗口

    private func appendVolume(_ volume: Int, for instrumentID: String, capacity: Int) {
        var window = volumeWindows[instrumentID] ?? []
        window.append(volume)
        if window.count > capacity { window.removeFirst(window.count - capacity) }
        volumeWindows[instrumentID] = window
    }

    private func averageVolume(for instrumentID: String, lastNBars: Int) -> Int? {
        // 排除当前 tick(window 末位)，再取前 N 期作为基准
        guard let window = volumeWindows[instrumentID] else { return nil }
        let history = window.dropLast()
        let n = min(lastNBars, history.count)
        guard n > 0 else { return nil }
        let recent = history.suffix(n)
        return recent.reduce(0, +) / n
    }

    private func appendPriceWindow(price: Decimal, timestamp: Date, for instrumentID: String, maxSeconds: TimeInterval) {
        var window = priceWindows[instrumentID] ?? []
        window.append((price: price, timestamp: timestamp))
        // 截掉超出 maxSeconds 的旧条目
        let cutoff = timestamp.addingTimeInterval(-maxSeconds)
        window.removeAll { $0.timestamp < cutoff }
        priceWindows[instrumentID] = window
    }

    /// 计算 windowSeconds 内价格的相对变化 (current - start) / start
    private func priceMovePercent(for instrumentID: String, currentPrice: Decimal, now: Date, windowSeconds: Int) -> Decimal? {
        guard let window = priceWindows[instrumentID], !window.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-TimeInterval(windowSeconds))
        guard let firstInWindow = window.first(where: { $0.timestamp >= cutoff }) else { return nil }
        guard firstInWindow.price > 0 else { return nil }
        return (currentPrice - firstInWindow.price) / firstInWindow.price
    }

    // MARK: - 私有：指标条件评估（v15.x 新增）

    /// 末两根 (current, currentRef, previous, previousRef) · main vs ref 的 cross 用
    /// - MA/EMA：main = close, ref = MA/EMA 值
    /// - MACD：main = DIF, ref = DEA
    /// - RSI：main = RSI, ref = 阈值（事件自带 · pair 中 ref 占位 0）
    private typealias CrossPair = (current: Decimal, currentRef: Decimal, previous: Decimal, previousRef: Decimal)

    /// 评估单条指标预警 · 计算指标 → 取末两根值 → 按 event 判断 cross
    /// 返回 nil 表示未触发；返回 event 表示触发
    private func evaluateIndicator(alert: Alert, spec: IndicatorAlertSpec, kline: [KLine], now: Date) -> AlertTriggeredEvent? {
        guard kline.count >= 2 else { return nil }

        let series = makeKLineSeries(from: kline)
        let pair: CrossPair?
        switch spec.indicator {
        case .ma, .ema:
            pair = computeLineCrossPair(series: series, kline: kline, kind: spec.indicator, params: spec.params)
        case .macd:
            pair = computeMACDCrossPair(series: series, params: spec.params)
        case .rsi:
            pair = computeRSIPair(series: series, params: spec.params)
        }
        guard let pair else { return nil }

        // 首次评估只记 baseline 不触发（避免历史 K 线导入误触发）
        let isBaseline = !indicatorBaselineRecorded.contains(alert.id)
        defer { indicatorBaselineRecorded.insert(alert.id) }
        if isBaseline { return nil }

        guard let message = matchCrossEvent(spec.event, indicatorName: spec.indicator.displayName, pair: pair) else {
            return nil
        }
        return AlertTriggeredEvent(
            alertID: alert.id,
            alertName: alert.name,
            instrumentID: alert.instrumentID,
            triggerPrice: kline.last?.close ?? 0,
            triggeredAt: now,
            message: message
        )
    }

    /// 按事件类型判断 cross 并返回触发消息（返回 nil 表示未 cross）
    /// crossedAbove = previous < previousRef ∧ current >= currentRef
    /// crossedBelow = previous > previousRef ∧ current <= currentRef
    private func matchCrossEvent(_ event: IndicatorEvent, indicatorName: String, pair: CrossPair) -> String? {
        let (cur, curRef, prev, prevRef) = pair
        switch event {
        case .priceCrossAboveLine:
            guard prev < prevRef, cur >= curRef else { return nil }
            return "\(indicatorName) · 价格 \(cur) 上穿 \(curRef)（前 \(prev) < \(prevRef)）"
        case .priceCrossBelowLine:
            guard prev > prevRef, cur <= curRef else { return nil }
            return "\(indicatorName) · 价格 \(cur) 下穿 \(curRef)（前 \(prev) > \(prevRef)）"
        case .macdGoldenCross:
            guard prev < prevRef, cur >= curRef else { return nil }
            return "MACD 金叉 · DIF \(cur) 上穿 DEA \(curRef)"
        case .macdDeathCross:
            guard prev > prevRef, cur <= curRef else { return nil }
            return "MACD 死叉 · DIF \(cur) 下穿 DEA \(curRef)"
        case .rsiCrossAbove(let threshold):
            guard prev < threshold, cur >= threshold else { return nil }
            return "RSI \(cur) 上穿 \(threshold)（前 \(prev)）"
        case .rsiCrossBelow(let threshold):
            guard prev > threshold, cur <= threshold else { return nil }
            return "RSI \(cur) 下穿 \(threshold)（前 \(prev)）"
        }
    }

    /// MA/EMA 末两根 (close, line) 对
    private func computeLineCrossPair(series: KLineSeries, kline: [KLine], kind: IndicatorKind, params: [Decimal]) -> CrossPair? {
        let result: [IndicatorSeries]
        do {
            switch kind {
            case .ma:  result = try MA.calculate(kline: series, params: params)
            case .ema: result = try EMA.calculate(kline: series, params: params)
            default:   return nil
            }
        } catch { return nil }
        guard let line = result.first?.values, line.count == kline.count else { return nil }
        let n = kline.count
        guard let cur = line[n - 1], let prev = line[n - 2] else { return nil }
        return (current: kline[n - 1].close, currentRef: cur, previous: kline[n - 2].close, previousRef: prev)
    }

    /// MACD 末两根 (DIF, DEA) 对
    private func computeMACDCrossPair(series: KLineSeries, params: [Decimal]) -> CrossPair? {
        guard let result = try? MACD.calculate(kline: series, params: params),
              result.count >= 2
        else { return nil }
        let dif = result[0].values
        let dea = result[1].values
        let n = dif.count
        guard n >= 2,
              let curD = dif[n - 1], let prevD = dif[n - 2],
              let curE = dea[n - 1], let prevE = dea[n - 2]
        else { return nil }
        return (current: curD, currentRef: curE, previous: prevD, previousRef: prevE)
    }

    /// RSI 末两根 (RSI, 0) 对（threshold 在事件自带，pair 中 ref 占位 0）
    private func computeRSIPair(series: KLineSeries, params: [Decimal]) -> CrossPair? {
        guard let result = try? RSI.calculate(kline: series, params: params),
              let rsi = result.first?.values,
              rsi.count >= 2
        else { return nil }
        let n = rsi.count
        guard let cur = rsi[n - 1], let prev = rsi[n - 2] else { return nil }
        return (current: cur, currentRef: 0, previous: prev, previousRef: 0)
    }

    /// [KLine] → KLineSeries 转换
    private func makeKLineSeries(from bars: [KLine]) -> KLineSeries {
        KLineSeries(
            opens:         bars.map(\.open),
            highs:         bars.map(\.high),
            lows:          bars.map(\.low),
            closes:        bars.map(\.close),
            volumes:       bars.map(\.volume),
            openInterests: bars.map { Int(truncating: $0.openInterest as NSDecimalNumber) }
        )
    }
}
