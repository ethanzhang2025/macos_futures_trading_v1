// 跨期套利（v15.50 · WP-套利分析 跨期 · 同品种不同月份合约价差）
//
// 核心区别（vs ⌘⌥S 跨品种套利）：
//   - 跨品种：rb-hc · m-y · au-ag 等不同品种之间的价差
//   - 跨期（本模块）：同品种 RB05-RB10 / M05-M09 等不同月份合约之间的价差
//
// 经典形态：
//   - Contango（升水/正向）：远月 > 近月 · 持有成本 + 仓储费 · 农产品淡季
//   - Backwardation（贴水/反向）：远月 < 近月 · 现货紧张 · 旺季供应不足
//
// trader 用法：
//   - mean-reverting 套利：当跨期价差偏离历史均值 ±2σ 时反向开仓
//   - 移仓提示：临近交割月时近月升水/贴水加剧 · 提前移仓策略
//   - 板块轮动：黑色系（rb 5-10 旺季-淡季差）/ 农产品（M 5-9 北美收割季）

import Foundation

/// 跨期套利对（同品种 · 近月 vs 远月）
public struct CalendarSpreadPair: Sendable, Equatable, Identifiable, Codable {
    public let id: String                 // "rb-05-10"
    public let name: String               // "螺纹 5-10"
    public let underlyingID: String       // "RB"（不带月份的标的代号）
    public let underlyingName: String     // "螺纹钢"
    public let nearMonthID: String        // "RB2505"
    public let farMonthID: String         // "RB2510"
    public let category: Category
    public let description: String        // "黑色系传统跨期 · 旺季-淡季供需差"

    public enum Category: String, Sendable, Codable, CaseIterable {
        case 黑色   = "黑色系跨期"
        case 农产品 = "农产品跨期"
        case 软商品 = "软商品跨期"
        case 能化   = "能化跨期"
        case 贵金属 = "贵金属跨期"
        case 股指   = "股指跨期"
        case 国债   = "国债跨期"
    }

    public init(id: String, name: String, underlyingID: String, underlyingName: String,
                nearMonthID: String, farMonthID: String,
                category: Category, description: String) {
        self.id = id
        self.name = name
        self.underlyingID = underlyingID
        self.underlyingName = underlyingName
        self.nearMonthID = nearMonthID
        self.farMonthID = farMonthID
        self.category = category
        self.description = description
    }
}

// MARK: - 经典跨期 preset 集合

public enum CalendarSpreadPresets {

    public static let all: [CalendarSpreadPair] = [
        // 黑色系（4）
        .init(id: "rb-05-10", name: "螺纹 5-10",
              underlyingID: "RB", underlyingName: "螺纹钢",
              nearMonthID: "RB2505", farMonthID: "RB2510",
              category: .黑色,
              description: "黑色系传统跨期 · 5 月旺季 vs 10 月淡季 · 库存周期"),
        .init(id: "rb-10-01", name: "螺纹 10-01",
              underlyingID: "RB", underlyingName: "螺纹钢",
              nearMonthID: "RB2510", farMonthID: "RB2601",
              category: .黑色,
              description: "螺纹跨年 · 北方冬储季 · 北方限产周期"),
        .init(id: "i-05-09", name: "铁矿 5-9",
              underlyingID: "I", underlyingName: "铁矿石",
              nearMonthID: "I2505", farMonthID: "I2509",
              category: .黑色,
              description: "铁矿石跨期 · 海外发运季节性"),
        .init(id: "j-05-09", name: "焦炭 5-9",
              underlyingID: "J", underlyingName: "焦炭",
              nearMonthID: "J2505", farMonthID: "J2509",
              category: .黑色,
              description: "焦炭跨期 · 焦煤限产周期 + 钢厂利润"),

        // 农产品（4）
        .init(id: "m-05-09", name: "豆粕 5-9",
              underlyingID: "M", underlyingName: "豆粕",
              nearMonthID: "M2505", farMonthID: "M2509",
              category: .农产品,
              description: "豆粕跨期 · 北美种植季（5 月播种 vs 9 月收割）"),
        .init(id: "y-05-09", name: "豆油 5-9",
              underlyingID: "Y", underlyingName: "豆油",
              nearMonthID: "Y2505", farMonthID: "Y2509",
              category: .农产品,
              description: "豆油跨期 · 大豆压榨利润 + 季节性消费"),
        .init(id: "p-05-09", name: "棕榈油 5-9",
              underlyingID: "P", underlyingName: "棕榈油",
              nearMonthID: "P2505", farMonthID: "P2509",
              category: .农产品,
              description: "棕榈油跨期 · 东南亚产量周期 + 北方冬季消费替代"),
        .init(id: "c-05-09", name: "玉米 5-9",
              underlyingID: "C", underlyingName: "玉米",
              nearMonthID: "C2505", farMonthID: "C2509",
              category: .农产品,
              description: "玉米跨期 · 春播 vs 秋收 · 临储拍卖"),

        // 软商品（2）
        .init(id: "sr-05-09", name: "白糖 5-9",
              underlyingID: "SR", underlyingName: "白糖",
              nearMonthID: "SR2505", farMonthID: "SR2509",
              category: .软商品,
              description: "白糖跨期 · 国内甘蔗榨季（11-4 月） + 巴西增产周期"),
        .init(id: "cf-05-09", name: "棉花 5-9",
              underlyingID: "CF", underlyingName: "棉花",
              nearMonthID: "CF2505", farMonthID: "CF2509",
              category: .软商品,
              description: "棉花跨期 · 新疆采棉季（9-11） vs 抛储季"),

        // 能化（2）
        .init(id: "sc-05-09", name: "原油 5-9",
              underlyingID: "SC", underlyingName: "原油",
              nearMonthID: "SC2505", farMonthID: "SC2509",
              category: .能化,
              description: "原油跨期 · 夏季驾车季消费高峰 vs OPEC+ 政策"),
        .init(id: "ru-05-09", name: "橡胶 5-9",
              underlyingID: "RU", underlyingName: "橡胶",
              nearMonthID: "RU2505", farMonthID: "RU2509",
              category: .能化,
              description: "橡胶跨期 · 东南亚停割季 · 轮胎厂排产"),

        // 贵金属（1）
        .init(id: "au-06-12", name: "黄金 6-12",
              underlyingID: "AU", underlyingName: "黄金",
              nearMonthID: "AU2506", farMonthID: "AU2512",
              category: .贵金属,
              description: "黄金跨期 · 长期通胀预期 · 美联储政策周期"),

        // 股指（1）
        .init(id: "if-05-06", name: "沪深300 5-6",
              underlyingID: "IF", underlyingName: "沪深300",
              nearMonthID: "IF2505", farMonthID: "IF2506",
              category: .股指,
              description: "股指季月跨期 · 移仓需求 + 分红预期"),

        // 国债（1）
        .init(id: "t-06-09", name: "10 年国债 6-9",
              underlyingID: "T", underlyingName: "10 年国债",
              nearMonthID: "T2506", farMonthID: "T2509",
              category: .国债,
              description: "国债跨期 · 收益率曲线 + 央行公开市场操作"),
    ]

    public static let byID: [String: CalendarSpreadPair] = {
        var dict: [String: CalendarSpreadPair] = [:]
        for p in all { dict[p.id] = p }
        return dict
    }()

    public static let byCategory: [CalendarSpreadPair.Category: [CalendarSpreadPair]] = {
        var dict: [CalendarSpreadPair.Category: [CalendarSpreadPair]] = [:]
        for cat in CalendarSpreadPair.Category.allCases {
            dict[cat] = all.filter { $0.category == cat }
        }
        return dict
    }()
}

// MARK: - 跨期价差时序生成（mock）

public struct CalendarSpreadValue: Sendable, Equatable {
    public let openTime: Date
    public let nearPrice: Decimal      // 近月合约价
    public let farPrice: Decimal       // 远月合约价
    public let spread: Decimal         // 远月 - 近月（contango = 正 · backwardation = 负）

    public init(openTime: Date, nearPrice: Decimal, farPrice: Decimal, spread: Decimal) {
        self.openTime = openTime
        self.nearPrice = nearPrice
        self.farPrice = farPrice
        self.spread = spread
    }
}

public enum CalendarSpreadCalculator {

    /// mock 跨期价差时序（v2 接 CTP 真历史 K 线后整段废弃）
    /// - 近月：基于品种当前价 random walk
    /// - 远月：近月 + 持有成本 + sin 波动（mean-reverting）
    /// - 价差：远月 - 近月 · 围绕"持有成本"波动
    public static func generateMockSeries(
        for pair: CalendarSpreadPair,
        basePrice: Double,
        count: Int = 200
    ) -> [CalendarSpreadValue] {
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(pair.id.hashValue)))
        let now = Date()
        let stepSec: TimeInterval = 86400  // 日线
        let baseTime = now.addingTimeInterval(-Double(count) * stepSec)

        var nearPrice = basePrice
        var holdingCost = basePrice * 0.015  // 持有成本基线 ≈ 1.5%
        var values: [CalendarSpreadValue] = []
        values.reserveCapacity(count)

        for i in 0..<count {
            // 近月 random walk
            let nearMove = rng.nextGaussian() * 0.012
            nearPrice *= exp(nearMove)
            // 持有成本均值回归 + 周期波动（季节性）
            let cycle = sin(Double(i) * 0.05) * basePrice * 0.005
            let costNoise = rng.nextGaussian() * basePrice * 0.002
            holdingCost = holdingCost * 0.98 + (basePrice * 0.015) * 0.02 + cycle + costNoise
            let farPrice = nearPrice + holdingCost
            let spread = farPrice - nearPrice
            values.append(CalendarSpreadValue(
                openTime: baseTime.addingTimeInterval(Double(i) * stepSec),
                nearPrice: Decimal(nearPrice),
                farPrice: Decimal(farPrice),
                spread: Decimal(spread)
            ))
        }
        return values
    }

    /// 转 SpreadValue（复用现有套利分析的 SpreadStatistics / SpreadHistogram / SpreadSignals）
    public static func toSpreadValues(_ values: [CalendarSpreadValue]) -> [SpreadValue] {
        values.map { v in
            SpreadValue(
                openTime: v.openTime,
                value: v.spread,
                leg1Close: v.nearPrice,
                leg2Close: v.farPrice
            )
        }
    }
}

// MARK: - 简易 SeededRNG（XorShift64 · 不污染外部）

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xCAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }

    mutating func nextDouble() -> Double {
        Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
    }

    mutating func nextGaussian() -> Double {
        let u1 = max(1e-10, nextDouble())
        let u2 = max(1e-10, nextDouble())
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
