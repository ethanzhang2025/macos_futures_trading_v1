// WP-51 模块 1 · K 线回放数据类型
// 沉浸式复盘：历史日期 + 品种 + 周期选择 → 回放控制（播放/暂停/2x-8x/倒退/单步）+ 成交点叠加
//
// 设计原则：
// - 时间外置：player 不持有 Timer / Task；caller 用 60fps Timer 驱动 stepForward
// - speed 仅是 metadata（caller 用来决定 Timer interval），不影响 player 离散 step 逻辑
// - 数据模型层不涉及实际渲染（图表渲染走 ChartCore，与实时模式共享）
//
// A07 禁做项："不要为了回放复制一套图表代码" → ReplayPlayer 提供 KLine 流，UnifiedDataSource
// 上层只需切换数据源，图表代码零改动

import Foundation
import Shared

// MARK: - 回放速度

/// 回放速度档位（与 D2 §2 多档加速对齐）
public enum ReplaySpeed: String, Sendable, Codable, CaseIterable {
    case x05    // 0.5x（慢放）
    case x1     // 1x（实时同速）
    case x2     // 2x
    case x4     // 4x
    case x8     // 8x

    /// 速度乘数（用于 caller 计算 Timer interval）
    public var multiplier: Double {
        switch self {
        case .x05: return 0.5
        case .x1:  return 1.0
        case .x2:  return 2.0
        case .x4:  return 4.0
        case .x8:  return 8.0
        }
    }
}

// MARK: - 回放状态

public enum ReplayState: String, Sendable, Codable, CaseIterable {
    case stopped   // 未加载或主动停止（cursor 重置 0）
    case playing   // 正在播放（caller 周期性调 stepForward）
    case paused    // 暂停（cursor 保留）
}

/// 回放方向（forward = 单 K 线 +1，backward = 单 K 线 -1）
public enum ReplayDirection: String, Sendable, Codable, CaseIterable {
    case forward
    case backward
}

// MARK: - 回放游标（位置 + 进度）

public struct ReplayCursor: Sendable, Equatable, Hashable {
    /// 当前 K 线索引（0..<totalCount）；-1 表示未加载
    public let currentIndex: Int
    /// 总 K 线数
    public let totalCount: Int

    public init(currentIndex: Int, totalCount: Int) {
        self.currentIndex = currentIndex
        self.totalCount = totalCount
    }

    /// 进度百分比 [0, 1]；未加载或空时为 0
    public var progress: Double {
        guard totalCount > 0, currentIndex >= 0 else { return 0 }
        return Double(currentIndex + 1) / Double(totalCount)
    }

    /// 是否到达末尾（自动暂停判定）
    public var isAtEnd: Bool { currentIndex >= totalCount - 1 }
    /// 是否在起点（向后退到不能再退）
    public var isAtStart: Bool { currentIndex <= 0 }
}

// MARK: - 回放更新事件（AsyncStream 元素）

public enum ReplayUpdate: Sendable, Equatable {
    /// K 线被推进 emit
    case barEmitted(KLine, cursor: ReplayCursor)
    /// 状态变更（含 state / speed / direction 任一变化）
    case stateChanged(state: ReplayState, speed: ReplaySpeed, direction: ReplayDirection)
    /// seek 完成（跳转后 emit 新 cursor，不 emit bar；caller 自行根据 currentBar 重画）
    case seekFinished(cursor: ReplayCursor)
    /// 当前 K 线时间窗口内的成交点（叠加层用）
    case tradeMarks([TradeMark])
}

// MARK: - 成交点叠加

/// 成交方向
public enum TradeMarkSide: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case buy    // 买入
    case sell   // 卖出
}

/// 成交点（叠加在图表上的标记）
/// 数据模型层只描述"在哪个 K 线时间 + 什么价格 + 多大量"，不实际渲染
public struct TradeMark: Sendable, Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var instrumentID: String
    public var time: Date
    public var price: Decimal
    public var side: TradeMarkSide
    public var volume: Int

    public init(
        id: UUID = UUID(),
        instrumentID: String,
        time: Date,
        price: Decimal,
        side: TradeMarkSide,
        volume: Int
    ) {
        self.id = id
        self.instrumentID = instrumentID
        self.time = time
        self.price = price
        self.side = side
        self.volume = volume
    }
}
