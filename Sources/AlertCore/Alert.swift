// WP-52 模块 1 · Alert 数据模型
// 3 类预警：价格（4 子类）+ 画线（v1 仅水平线）+ 异常（成交量/价格急动）
// 数据模型层 · 不引入通知发送逻辑（统一 NotificationChannel 层）· 不实际订阅 Tick（AlertEvaluator 做）
//
// 评估逻辑分离：本文件只描述"什么是预警"（数据），AlertEvaluator 决定"如何判断"（行为）
// 这是 Karpathy "避免过度复杂" 原则——enum 不嵌入 evaluate 函数，避免 enum 状态膨胀

import Foundation

/// 预警条件 · 6 类（价格 4 + 画线 1 + 异常 2）
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

    // MARK: - 画线类（v1 仅水平线，其他画线类型留 v2）

    /// 价格触及水平线（drawingID 引用 WP-42 Drawing UUID）
    /// v1 只支持 horizontalLine 类型；趋势线/矩形/斐波那契等留 v2 接 DrawingGeometry
    case horizontalLineTouched(drawingID: UUID, price: Decimal)

    // MARK: - 异常类（2 子类）

    /// 成交量异常：当前 volume / 近 N 期均值 ≥ multiple
    /// AlertEvaluator 维护滑动窗口
    case volumeSpike(multiple: Decimal, windowBars: Int)

    /// 价格急动：windowSeconds 内价格变化绝对值 / 起始价 ≥ percentThreshold
    case priceMoveSpike(percentThreshold: Decimal, windowSeconds: Int)
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
}

/// 单条预警
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

    public init(
        id: UUID = UUID(),
        name: String,
        instrumentID: String,
        condition: AlertCondition,
        status: AlertStatus = .active,
        channels: Set<NotificationChannelKind> = [.inApp, .systemNotice],
        cooldownSeconds: TimeInterval = 60,
        createdAt: Date = Date(),
        lastTriggeredAt: Date? = nil
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
    }

    /// 是否处于可触发状态（active 且不在 cooldown 内）
    public func canTrigger(at now: Date = Date()) -> Bool {
        guard status == .active else { return false }
        guard let last = lastTriggeredAt else { return true }
        return now.timeIntervalSince(last) >= cooldownSeconds
    }
}
