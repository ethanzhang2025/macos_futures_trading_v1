// 异常历史回溯（v15.59 · ⌘⌥A v2 历史频次）
//
// trader 用法：
//   - 看过去 30 天哪个品种"最频繁异动"（频次 + sparkline mini 图）
//   - 排序 → 重点关注 top N（往往是龙头 / 大空头）
//   - 类型分布 → 这个品种最常哪种异常（持仓/价格/资金）
//
// 数据流：
//   - mock：每品种 seeded RNG · 30d × 5 类异常概率独立采样
//   - v2 接 CTP 后：对历史 K 线日切批量跑 AnomalyDetector.scan + 落 SQLite + 30d 查询
//
// 数据契约 v1 一次拍板 · v2 切数据源不动 API：
//   - InstrumentAnomalyHistory · 单品种 30d 累积
//   - AnomalyHistoryEntry · 单日单品种 count + kind 分布
//   - AnomalyHistoryGenerator · 入口（mock 实现 / v2 替换）

import Foundation

/// 单品种单日异常计数
public struct AnomalyHistoryEntry: Sendable, Equatable, Codable {
    /// 当日 0:00（按 UTC · v2 真行情按交易日切）
    public let date: Date
    /// 当日异常总次数（5 类合计）
    public let count: Int
    /// 5 类各自次数（缺失 = 0）· UI hover 看分布用
    public let kindCounts: [AnomalyKind: Int]

    public init(date: Date, count: Int, kindCounts: [AnomalyKind: Int]) {
        self.date = date
        self.count = count
        self.kindCounts = kindCounts
    }
}

/// 单品种 30d 异常历史
public struct InstrumentAnomalyHistory: Sendable, Equatable, Identifiable {
    public let instrumentID: String
    public let instrumentName: String
    public let sector: Sector
    /// 30d 总异常次数（按总数排序用）
    public let totalCount: Int
    /// 30d 累计各类型次数
    public let countByKind: [AnomalyKind: Int]
    /// 30 日时序（升序 · 30 项 · 用于 sparkline）
    public let entries: [AnomalyHistoryEntry]

    public var id: String { instrumentID }

    /// sparkline 用：日度 count 序列（升序）
    public var dailyCounts: [Int] { entries.map(\.count) }

    /// 平均每天异常次数
    public var avgPerDay: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(totalCount) / Double(entries.count)
    }

    /// 最大日异常次数（sparkline y 轴归一化用）
    public var peakDayCount: Int { entries.map(\.count).max() ?? 0 }
}

public enum AnomalyHistoryGenerator {

    /// 全市场 30 天异常历史 · mock 生成
    /// - Parameters:
    ///   - days: 历史天数（默认 30）
    ///   - instruments: 品种列表（默认 SectorPresets.all · 60+ 主连续）
    ///   - now: 截止时间戳（注入便于测试）
    /// - Returns: 按 totalCount 降序排序
    ///
    /// v2 接 CTP 后整段切换：从 SQLite anomaly_history 表查 30d 切片
    public static func generate(
        days: Int = 30,
        instruments: [SectorInstrument] = SectorPresets.all,
        now: Date = Date()
    ) -> [InstrumentAnomalyHistory] {
        guard days > 0 else { return [] }
        let stepSec: TimeInterval = 86400
        let baseTime = now.addingTimeInterval(-Double(days) * stepSec)

        return instruments.map { inst in
            // 每品种独立 seed · 同 inst.id 多次扫描结果一致
            // String.hashValue 跨进程不稳定 · 但单进程多次扫描稳定（够 UI 一致性）
            var rng = AnomalyHistorySeededRNG(seed: UInt64(bitPattern: Int64(inst.id.hashValue)))
            // 基础异动率 [0.1, 0.6] · 部分品种"高频"部分"低频"
            let baseRate = 0.1 + rng.nextDouble() * 0.5
            // 5 类各自命中倍率 · seed 独立
            let kindMultipliers: [AnomalyKind: Double] = Dictionary(uniqueKeysWithValues:
                AnomalyKind.allCases.map { ($0, 0.3 + rng.nextDouble() * 1.4) }
            )

            var entries: [AnomalyHistoryEntry] = []
            var totalCount = 0
            var sumByKind: [AnomalyKind: Int] = [:]
            entries.reserveCapacity(days)

            for d in 0..<days {
                let dayDate = baseTime.addingTimeInterval(Double(d) * stepSec)
                // 当日波动：基础率 + 高斯噪声 + 周末稍降（周六周日 -30%）
                let weekday = Calendar(identifier: .gregorian).component(.weekday, from: dayDate)
                let weekendDamp = (weekday == 1 || weekday == 7) ? 0.7 : 1.0
                var dayKindCounts: [AnomalyKind: Int] = [:]
                var dayTotal = 0
                for kind in AnomalyKind.allCases {
                    let mul = kindMultipliers[kind] ?? 1.0
                    // 命中概率 = baseRate × kindMul × weekendDamp · 期望 0-2 次/类/天
                    let hits = sampleHits(rate: baseRate * mul * weekendDamp, rng: &rng)
                    if hits > 0 {
                        dayKindCounts[kind] = hits
                        dayTotal += hits
                        sumByKind[kind, default: 0] += hits
                    }
                }
                entries.append(AnomalyHistoryEntry(date: dayDate, count: dayTotal, kindCounts: dayKindCounts))
                totalCount += dayTotal
            }

            return InstrumentAnomalyHistory(
                instrumentID: inst.id,
                instrumentName: inst.name,
                sector: inst.sector,
                totalCount: totalCount,
                countByKind: sumByKind,
                entries: entries
            )
        }
        .sorted { $0.totalCount > $1.totalCount }
    }

    /// 单天命中次数采样：泊松-like · rate ∈ [0, 3]（期望 0-3 次/类/天）
    private static func sampleHits(rate: Double, rng: inout AnomalyHistorySeededRNG) -> Int {
        // 泊松 inverse CDF · rate 小（< 1）大概率 0 次 · rate 大可能 1-3 次
        let u = rng.nextDouble()
        if u < exp(-rate) { return 0 }
        if u < exp(-rate) * (1 + rate) { return 1 }
        if u < exp(-rate) * (1 + rate + rate * rate / 2) { return 2 }
        return 3  // cap 3 · trader 视角 4+ 已极端
    }
}

// MARK: - SeededRNG（XorShift64）

private struct AnomalyHistorySeededRNG {
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
    mutating func nextDouble() -> Double {
        Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x1F_FFFF_FFFF_FFFF)
    }
}
