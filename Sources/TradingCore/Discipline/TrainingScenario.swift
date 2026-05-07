// WP-54 v15.23 batch15 · 模拟训练场景预设库（M5 节点功能性扩展）
//
// 用途：
// - trader 选场景代替空跑训练 · 锁定特定历史时段的合约 + 推荐时长 + 初始资金
// - 后续 batch 会把场景接到 ChartScene 的"复盘回放" · 自动播 onTick 触发 evaluator
// - v15.23 batch15 先落地数据模型 + 8 个推荐预设 · UI 集成下一 batch
//
// 设计要点：
// - 纯值类型 + Codable · trader 后续可自定义场景导出 / 导入 JSON
// - 时间范围 [startDate, endDate] 是历史区间的 [开盘, 收盘]
// - recommendedDurationMinutes：UI 显示该场景预期训练时长（trader 可自行延长）
// - initialBalance：场景设计的合理初始资金（与合约保证金匹配 · 防止资金太小连开 1 手都不行）

import Foundation

/// 模拟训练场景（一个完整的复盘训练单元）
public struct TrainingScenario: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let instrumentID: String
    public let startDate: Date
    public let endDate: Date
    public let description: String
    public let initialBalance: Decimal
    public let recommendedDurationMinutes: Int
    public let difficulty: Difficulty
    /// v15.23 batch115 · 价格形态枚举（用于 K 线 thumbnail 生成 · trader 选场景前一眼看懂走势特征）
    public let pattern: TrainingScenarioPattern

    public init(id: UUID = UUID(),
                name: String,
                instrumentID: String,
                startDate: Date,
                endDate: Date,
                description: String,
                initialBalance: Decimal,
                recommendedDurationMinutes: Int,
                difficulty: Difficulty = .medium,
                pattern: TrainingScenarioPattern = .oscillation) {
        self.id = id
        self.name = name
        self.instrumentID = instrumentID
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
        self.initialBalance = initialBalance
        self.recommendedDurationMinutes = recommendedDurationMinutes
        self.difficulty = difficulty
        self.pattern = pattern
    }

    // batch115 · 自定义 Codable 兼容 v15.23 batch15-114 老 JSON（无 pattern 字段 → 默认 .oscillation）
    private enum CodingKeys: String, CodingKey {
        case id, name, instrumentID, startDate, endDate, description
        case initialBalance, recommendedDurationMinutes, difficulty, pattern
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.instrumentID = try c.decode(String.self, forKey: .instrumentID)
        self.startDate = try c.decode(Date.self, forKey: .startDate)
        self.endDate = try c.decode(Date.self, forKey: .endDate)
        self.description = try c.decode(String.self, forKey: .description)
        self.initialBalance = try c.decode(Decimal.self, forKey: .initialBalance)
        self.recommendedDurationMinutes = try c.decode(Int.self, forKey: .recommendedDurationMinutes)
        self.difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .medium
        self.pattern = try c.decodeIfPresent(TrainingScenarioPattern.self, forKey: .pattern) ?? .oscillation
    }

    public enum Difficulty: String, Sendable, Codable, Equatable, CaseIterable {
        case easy   = "easy"
        case medium = "medium"
        case hard   = "hard"

        public var displayName: String {
            switch self {
            case .easy:   return "入门"
            case .medium: return "中级"
            case .hard:   return "高级"
            }
        }

        public var emoji: String {
            switch self {
            case .easy:   return "🟢"
            case .medium: return "🟡"
            case .hard:   return "🔴"
            }
        }
    }

    /// 时间跨度（秒）
    public var durationSeconds: Int {
        Int(endDate.timeIntervalSince(startDate))
    }

    /// 场景跨度文本（如 "2 小时 30 分"）
    public var durationDescription: String {
        let secs = durationSeconds
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h) 小时 \(m) 分" }
        return "\(m) 分"
    }
}

/// v15.23 batch115 · 训练场景价格形态（用于 K 线 thumbnail 生成）
/// trader 选场景时预先看懂走势特征 · 不同形态对应不同纪律训练焦点
public enum TrainingScenarioPattern: String, Sendable, Codable, Equatable, CaseIterable {
    case oscillation     // 震荡（无方向 sin 波 · 训练止损不追高）
    case uptrend         // 单边上升趋势（训练持仓不被洗）
    case downtrend       // 单边下降趋势
    case vReversal       // V 反转（先跌后涨 · 训练 V 反不追、不报复加仓）
    case breakout        // 突破（横盘后单边突破 · 训练突破回踩进场）
    case fakeBreakout    // 假突破后真突破（训练用量能确认信号）
    case gapAndHalt      // 跳空 + 熔断（极端行情 · 训练清仓决策）
    case nightRally      // 夜盘急拉（训练快速反应 + 不追高）
    case multiPhase      // 4 段综合（震荡→突破→趋势→反转 · 综合考核）

    /// thumbnail 提示用中文短名
    public var displayName: String {
        switch self {
        case .oscillation:  return "震荡"
        case .uptrend:      return "上升趋势"
        case .downtrend:    return "下降趋势"
        case .vReversal:    return "V 反转"
        case .breakout:     return "突破"
        case .fakeBreakout: return "假突破"
        case .gapAndHalt:   return "跳空熔断"
        case .nightRally:   return "夜盘急拉"
        case .multiPhase:   return "4 段综合"
        }
    }

    /// 形态 emoji（trader Menu 选项视觉前缀 · 快速识别走势类型）
    public var emoji: String {
        switch self {
        case .oscillation:  return "〰️"
        case .uptrend:      return "📈"
        case .downtrend:    return "📉"
        case .vReversal:    return "✓"
        case .breakout:     return "🚀"
        case .fakeBreakout: return "↪️"
        case .gapAndHalt:   return "⚡️"
        case .nightRally:   return "🌙"
        case .multiPhase:   return "🎯"
        }
    }
}

/// 静态推荐场景库（v15.23 batch15 · 8 个典型期货训练场景）
public enum TrainingScenarios {

    /// 推荐预设（覆盖入门 / 中级 / 高级 三个梯度）· UI 一键加载
    public static let defaultPresets: [TrainingScenario] = [
        // 入门
        TrainingScenario(
            name: "螺纹钢日内震荡（学止损）",
            instrumentID: "RB0",
            startDate: dateFor(year: 2024, month: 3, day: 18, hour: 9, minute: 0),
            endDate:   dateFor(year: 2024, month: 3, day: 18, hour: 11, minute: 30),
            description: "无方向震荡 · 训练止损纪律 · 不追高不抄底",
            initialBalance: 100_000,
            recommendedDurationMinutes: 60,
            difficulty: .easy,
            pattern: .oscillation
        ),
        TrainingScenario(
            name: "IF 趋势日（学持仓）",
            instrumentID: "IF0",
            startDate: dateFor(year: 2024, month: 4, day: 5, hour: 9, minute: 30),
            endDate:   dateFor(year: 2024, month: 4, day: 5, hour: 15, minute: 0),
            description: "明显单边趋势 · 训练持仓不被洗出去 · 主升浪不平掉",
            initialBalance: 200_000,
            recommendedDurationMinutes: 90,
            difficulty: .easy,
            pattern: .uptrend
        ),

        // 中级
        TrainingScenario(
            name: "铜急涨急跌 2020-08-12（学情绪）",
            instrumentID: "CU0",
            startDate: dateFor(year: 2020, month: 8, day: 12, hour: 9, minute: 0),
            endDate:   dateFor(year: 2020, month: 8, day: 12, hour: 14, minute: 0),
            description: "高位插针 + 急跌反弹 · 训练 V 反不追、不报复加仓",
            initialBalance: 300_000,
            recommendedDurationMinutes: 75,
            difficulty: .medium,
            pattern: .vReversal
        ),
        TrainingScenario(
            name: "黄金避险拉升（学突破）",
            instrumentID: "AU0",
            startDate: dateFor(year: 2024, month: 4, day: 12, hour: 21, minute: 0),
            endDate:   dateFor(year: 2024, month: 4, day: 12, hour: 23, minute: 30),
            description: "突破历史高点 · 训练突破回踩进场 · 不抢、不死多",
            initialBalance: 250_000,
            recommendedDurationMinutes: 60,
            difficulty: .medium,
            pattern: .breakout
        ),
        TrainingScenario(
            name: "棉花横盘破位（学过滤假突破）",
            instrumentID: "MA0",
            startDate: dateFor(year: 2024, month: 5, day: 8, hour: 9, minute: 0),
            endDate:   dateFor(year: 2024, month: 5, day: 8, hour: 14, minute: 0),
            description: "长时间横盘 + 假突破 + 真突破 · 训练用量能确认信号真假",
            initialBalance: 150_000,
            recommendedDurationMinutes: 90,
            difficulty: .medium,
            pattern: .fakeBreakout
        ),

        // 高级
        TrainingScenario(
            name: "原油跳空高开熔断 2020-04-21（极端行情）",
            instrumentID: "I0",
            startDate: dateFor(year: 2020, month: 4, day: 21, hour: 9, minute: 0),
            endDate:   dateFor(year: 2020, month: 4, day: 21, hour: 11, minute: 30),
            description: "跳空 + 熔断 · 训练极端行情下的清仓决策 · 资金保命第一",
            initialBalance: 500_000,
            recommendedDurationMinutes: 120,
            difficulty: .hard,
            pattern: .gapAndHalt
        ),
        TrainingScenario(
            name: "螺纹钢夜盘急拉（学夜盘节奏）",
            instrumentID: "RB0",
            startDate: dateFor(year: 2024, month: 6, day: 17, hour: 21, minute: 0),
            endDate:   dateFor(year: 2024, month: 6, day: 17, hour: 23, minute: 0),
            description: "夜盘消息驱动 · 训练快速反应 · 但避免追高 · 凌晨睡觉守纪律",
            initialBalance: 200_000,
            recommendedDurationMinutes: 60,
            difficulty: .hard,
            pattern: .nightRally
        ),
        TrainingScenario(
            name: "全天 4 行情（综合考核）",
            instrumentID: "RB0",
            startDate: dateFor(year: 2024, month: 7, day: 22, hour: 9, minute: 0),
            endDate:   dateFor(year: 2024, month: 7, day: 22, hour: 15, minute: 0),
            description: "震荡 → 突破 → 趋势 → 反转 4 段 · 综合训练所有纪律",
            initialBalance: 300_000,
            recommendedDurationMinutes: 240,
            difficulty: .hard,
            pattern: .multiPhase
        ),
    ]

    /// 按难度筛选
    public static func presets(of difficulty: TrainingScenario.Difficulty) -> [TrainingScenario] {
        defaultPresets.filter { $0.difficulty == difficulty }
    }

    /// 按合约筛选
    public static func presets(forInstrument instrumentID: String) -> [TrainingScenario] {
        defaultPresets.filter { $0.instrumentID == instrumentID }
    }

    // MARK: - 内部 helper · 构造日期

    static func dateFor(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }
}
