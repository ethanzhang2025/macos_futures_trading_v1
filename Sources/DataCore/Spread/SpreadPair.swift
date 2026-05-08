// 跨品种 / 跨期 / 跨市场价差对模型（v15.27 · WP-套利分析 V1 MVP）
//
// 设计：
//   - SpreadLeg = 单条腿（合约 + 比率）· 比率支持负数表示空腿
//   - SpreadPair = 两条腿组合 · 价差 = leg1.close * ratio1 + leg2.close * ratio2
//   - 经典对见 SpreadPresets · 用户可自定义对存 SpreadCustomStore（V2）
//
// 例：
//   螺纹热卷价差（rb-hc）= 1 × rb_close + (-1) × hc_close
//   黄金白银比（au-80*ag）= 1 × au_close + (-80) × ag_close
//   月间套利（rb 近月-远月）= 1 × rb_near_close + (-1) × rb_far_close

import Foundation
import Shared

/// 价差单腿
public struct SpreadLeg: Sendable, Codable, Equatable {
    /// 合约 ID（如 "rb2509" / "RB0" / "IF2505"）
    public let instrumentID: String
    /// 腿系数（带符号 · 正=多腿 · 负=空腿）· int 简化（凯利 / 1:1 / 1:80 等整数比常见）
    public let ratio: Int

    public init(instrumentID: String, ratio: Int) {
        self.instrumentID = instrumentID
        self.ratio = ratio
    }
}

/// 价差对（两条腿）
public struct SpreadPair: Sendable, Codable, Equatable, Identifiable {
    public let id: String              // 唯一 ID（"rb-hc" / "au-80ag" / "IF-IH" 等）
    public let name: String            // 显示名（"螺纹热卷" / "金银比" / "沪深300-上证50"）
    public let category: Category      // 分类（跨品种 / 月间 / 跨指数 / 跨期限）
    public let leg1: SpreadLeg         // 第 1 腿（通常多腿 · ratio > 0）
    public let leg2: SpreadLeg         // 第 2 腿（通常空腿 · ratio < 0）
    public let unitLabel: String       // 价差单位（"元/吨" / "点" / "无量纲" 等）
    public let description: String     // 经济含义（如 "钢材消费结构 · 螺纹建材偏弱时缩价差"）

    public init(
        id: String, name: String, category: Category,
        leg1: SpreadLeg, leg2: SpreadLeg,
        unitLabel: String, description: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.leg1 = leg1
        self.leg2 = leg2
        self.unitLabel = unitLabel
        self.description = description
    }

    /// 分类
    public enum Category: String, Sendable, Codable, CaseIterable {
        case 跨品种   = "跨品种"
        case 月间     = "月间"
        case 跨指数   = "跨指数"
        case 跨期限   = "跨期限"
        case 跨市场   = "跨市场"
        case 产业链   = "产业链"
    }
}

/// 价差时序点（计算输出）
public struct SpreadValue: Sendable, Equatable {
    public let openTime: Date          // 时间戳（与两腿 K 线的 openTime 对齐）
    public let value: Decimal          // 价差值 = leg1.close * ratio1 + leg2.close * ratio2
    public let leg1Close: Decimal      // 第 1 腿当时收盘价（调试 / HUD 用）
    public let leg2Close: Decimal      // 第 2 腿当时收盘价

    public init(openTime: Date, value: Decimal, leg1Close: Decimal, leg2Close: Decimal) {
        self.openTime = openTime
        self.value = value
        self.leg1Close = leg1Close
        self.leg2Close = leg2Close
    }
}
