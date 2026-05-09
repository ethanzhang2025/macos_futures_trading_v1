// WP-52 模块 1 · Alert 数据模型
// 4 类预警：价格（4 子类）+ 画线（v1 仅水平线）+ 异常（成交量/持仓量/价格急动）+ 指标
// 数据模型层 · 不引入通知发送逻辑（统一 NotificationChannel 层）· 不实际订阅 Tick（AlertEvaluator 做）
//
// 评估逻辑分离：本文件只描述"什么是预警"（数据），AlertEvaluator 决定"如何判断"（行为）
// 这是 Karpathy "避免过度复杂" 原则——enum 不嵌入 evaluate 函数，避免 enum 状态膨胀

import Foundation
import Shared

/// 预警条件 · 9 类（价格 4 + 画线 1 + 异常 3 + 指标 1）
public enum AlertCondition: Sendable, Codable, Equatable, Hashable {

    // MARK: - 价格类（4 子类，与 Legacy ConditionalOrder.PriceCondition 同形）

    /// 价格高于阈值
    case priceAbove(Decimal)
    /// 价格低于阈值
    case priceBelow(Decimal)
    /// 价格上穿阈值（prev < target 且 current >= target）· 边界不重复触发
    case priceCrossAbove(Decimal)
    /// 价格下穿阈值（prev > target 且 current <= target）
    case priceCrossBelow(Decimal)

    // MARK: - Donchian 突破（v15.19+ batch16 · trader 趋势启动捕捉）

    /// 突破前 N 根（同周期）K 线最高价（不含本根 · 当前 bar.close > max(highs[-N..<-1])）
    /// trader 经典 Donchian 通道突破信号 · 顺势启动入场参考
    case priceBreakoutHigh(period: KLinePeriod, lookback: Int)

    /// 跌破前 N 根（同周期）K 线最低价（不含本根 · 当前 bar.close < min(lows[-N..<-1])）
    case priceBreakoutLow(period: KLinePeriod, lookback: Int)

    // MARK: - 画线类（v1 仅水平线，其他画线类型留 v2）

    /// 价格触及水平线（drawingID 引用 WP-42 Drawing UUID）
    /// v1 只支持 horizontalLine 类型；趋势线/矩形/斐波那契等留 v2 接 DrawingGeometry
    case horizontalLineTouched(drawingID: UUID, price: Decimal)

    // MARK: - 异常类（3 子类）

    /// 成交量异常：当前 volume / 近 N 期均值 ≥ multiple
    /// AlertEvaluator 维护滑动窗口
    case volumeSpike(multiple: Decimal, windowBars: Int)

    /// 持仓量异常：当前 OI / 近 N 期均值 ≥ multiple（v15.12 WP-52 v3 · 期货特有）
    /// 用户场景：突然增仓暗示资金动向（夜盘开盘 / 主力建仓 / 平仓潮）
    /// 与 volumeSpike 同模式 · 滑动窗口 + 比值阈值 · 走 onTick 路径（Tick.openInterest 直接读）
    case openInterestSpike(multiple: Decimal, windowBars: Int)

    /// 价格急动：windowSeconds 内价格变化绝对值 / 起始价 ≥ percentThreshold
    case priceMoveSpike(percentThreshold: Decimal, windowSeconds: Int)

    // MARK: - 指标类（v15.x WP-52 扩展）

    /// 指标条件预警 · 走 K 线序列驱动 · 由 evaluator.onBar 评估（不在 onTick 路径）
    /// 详见 IndicatorAlertSpec
    case indicator(IndicatorAlertSpec)

    // MARK: - 价差类（v15.57 · ⌘⌥W 一键加预警）

    /// 价差偏离预警 · spreadID 引用 SpreadPresets / CalendarSpreadPresets 的对 ID
    /// - spreadID："rb-hc"（跨品种）/ "rb-05-10"（跨期）
    /// - isCalendar: true=跨期 · false=跨品种
    /// - zThreshold: |Z-score| 触发阈值（典型 2.0 = ±2σ）
    ///
    /// v15.60 · evaluator.onSpreadValue() 真触发已接通 · caller 周期性扫描喂 series
    /// instrumentID 字段保留近月合约 · UI 通过 spreadID 反查 SpreadPresets 显示价差名。
    case spreadDeviation(spreadID: String, isCalendar: Bool, zThreshold: Decimal)
}

/// 价差时序点抽象（v15.60 · onSpreadValue 入参 · 不引 DataCore dep）
///
/// DataCore.SpreadValue 实现此协议（仅暴露 value）· AlertCore 不依赖 DataCore 具体类型
/// caller 转换：values.map { SpreadValueLikeImpl(value: $0.value) }
/// （或直接 conform DataCore.SpreadValue 到此协议）
public protocol SpreadValueLike: Sendable {
    var value: Decimal { get }
}

/// 预警状态
public enum AlertStatus: String, Sendable, Codable, CaseIterable {
    case active     // 活跃监控中
    case triggered  // 已触发（在 cooldown 期间维持此状态）
    case paused     // 用户暂停
    case cancelled  // 用户取消（不会再触发）
}

/// 通知渠道枚举（v1 三个：App 内 / 系统通知中心 / 声音）
/// 数据模型层只描述"该走哪些渠道"，实际渠道实现见 NotificationChannel 协议
public enum NotificationChannelKind: String, Sendable, Codable, CaseIterable {
    case inApp           // App 内浮窗 / 状态栏徽章
    case systemNotice    // macOS UserNotifications
    case sound           // 系统声音 / 自定义铃声
    case console         // 🆕 stdout 调试通道（开发期 / Linux production-grade · 带时间戳与前缀）
    case file            // 🆕 本地文件追加日志通道（持久化预警记录 · 与 SQLite history 互补）
}

/// 单条预警
///
/// WP-60 同步预埋（v15.24 batch007 · 敏感数据 · 阿里云通道留 Stage B）：
/// - updatedAt / version / deletedAt 字段预埋（schema 兼容）
/// - 启用同步由 Stage B WP-84 合规方案落地后接入（D4 G1 方案 A · 不走 CloudKit）
public struct Alert: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var instrumentID: String
    public var condition: AlertCondition
    public var status: AlertStatus
    /// 触发后选择的通知渠道（为空表示仅写 history 不通知）
    public var channels: Set<NotificationChannelKind>
    /// 频控冷却时间：触发后 N 秒内不再重复触发（0 = 不冷却，每次满足条件都触发）
    public var cooldownSeconds: TimeInterval
    public var createdAt: Date
    /// 最近一次触发时间（用于频控判断）
    public var lastTriggeredAt: Date?
    /// WP-60 · 最后修改时间（不含 lastTriggeredAt 自更新 · 仅当用户实际改字段时刷新）
    public var updatedAt: Date
    /// WP-60 · 修改次数 · LWW 副决胜
    public var version: Int
    /// WP-60 · 软删除时间戳（同步友好 · 优先级高于 status.cancelled）
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        instrumentID: String,
        condition: AlertCondition,
        status: AlertStatus = .active,
        channels: Set<NotificationChannelKind> = [.inApp, .systemNotice],
        cooldownSeconds: TimeInterval = 60,
        createdAt: Date = Date(),
        lastTriggeredAt: Date? = nil,
        updatedAt: Date? = nil,
        version: Int = 1,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.instrumentID = instrumentID
        self.condition = condition
        self.status = status
        self.channels = channels
        self.cooldownSeconds = cooldownSeconds
        self.createdAt = createdAt
        self.lastTriggeredAt = lastTriggeredAt
        self.updatedAt = updatedAt ?? createdAt
        self.version = version
        self.deletedAt = deletedAt
    }

    // MARK: - Codable（兼容旧 JSON · 缺 updatedAt/version/deletedAt 时回退）

    private enum CodingKeys: String, CodingKey {
        case id, name, instrumentID, condition, status, channels
        case cooldownSeconds, createdAt, lastTriggeredAt
        case updatedAt, version, deletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.instrumentID = try c.decode(String.self, forKey: .instrumentID)
        self.condition = try c.decode(AlertCondition.self, forKey: .condition)
        self.status = try c.decode(AlertStatus.self, forKey: .status)
        self.channels = try c.decode(Set<NotificationChannelKind>.self, forKey: .channels)
        self.cooldownSeconds = try c.decode(TimeInterval.self, forKey: .cooldownSeconds)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastTriggeredAt = try c.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(instrumentID, forKey: .instrumentID)
        try c.encode(condition, forKey: .condition)
        try c.encode(status, forKey: .status)
        try c.encode(channels, forKey: .channels)
        try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastTriggeredAt, forKey: .lastTriggeredAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    /// 是否处于可触发状态（active 且不在 cooldown 内）
    public func canTrigger(at now: Date = Date()) -> Bool {
        guard status == .active else { return false }
        guard deletedAt == nil else { return false }
        guard let last = lastTriggeredAt else { return true }
        return now.timeIntervalSince(last) >= cooldownSeconds
    }

    /// 软删除（同步友好 · 不物理删 · 由调用方持久化）
    public mutating func markDeleted(now: Date = Date()) {
        guard deletedAt == nil else { return }
        deletedAt = now
        updatedAt = now
        version += 1
    }
}
