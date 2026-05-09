// 板块聚合统计（v15.43 · WP-行情 V3）
//
// 输入：单板块或多板块品种列表
// 输出：涨跌家数 / 平均涨幅 / 多空偏向 / 最强最弱 / 总持仓
//
// trader 用法：
//   - 一眼看板块情绪（多空偏向进度条 · ±100% 量化）
//   - 找板块龙头（strongest = 涨幅最大 · 龙头多为板块趋势的领涨者）
//   - 找板块弱势（weakest = 跌幅最大 · 用于找做空标的或避坑）

import Foundation

public struct SectorStatistics: Sendable, Equatable {
    public let sector: Sector
    public let totalCount: Int
    public let gainers: Int
    public let losers: Int
    public let unchanged: Int
    public let avgChangePct: Double          // 平均涨跌幅
    /// 多空偏向 = (gainers - losers) / total · [-1, +1]
    public let bullBias: Double
    public let strongest: SectorInstrument?  // 涨幅最大
    public let weakest: SectorInstrument?    // 跌幅最大
    public let totalOpenInterestK: Double    // 板块总持仓量（K 单位）

    public static let empty = SectorStatistics(
        sector: .黑色, totalCount: 0,
        gainers: 0, losers: 0, unchanged: 0,
        avgChangePct: 0, bullBias: 0,
        strongest: nil, weakest: nil,
        totalOpenInterestK: 0
    )
}

public enum SectorStatisticsCalculator {

    /// 单板块聚合
    public static func compute(_ instruments: [SectorInstrument], sector: Sector) -> SectorStatistics {
        guard !instruments.isEmpty else {
            return SectorStatistics(
                sector: sector, totalCount: 0,
                gainers: 0, losers: 0, unchanged: 0,
                avgChangePct: 0, bullBias: 0,
                strongest: nil, weakest: nil,
                totalOpenInterestK: 0
            )
        }
        let total = instruments.count
        let gainers = instruments.filter { $0.changePct > 0 }.count
        let losers = instruments.filter { $0.changePct < 0 }.count
        let unchanged = total - gainers - losers
        let avg = instruments.reduce(0.0) { $0 + $1.changePct } / Double(total)
        let bullBias = Double(gainers - losers) / Double(total)
        let strongest = instruments.max(by: { $0.changePct < $1.changePct })
        let weakest = instruments.min(by: { $0.changePct < $1.changePct })
        let totalOI = instruments.reduce(0.0) { $0 + $1.openInterestK }
        return SectorStatistics(
            sector: sector, totalCount: total,
            gainers: gainers, losers: losers, unchanged: unchanged,
            avgChangePct: avg, bullBias: bullBias,
            strongest: strongest, weakest: weakest,
            totalOpenInterestK: totalOI
        )
    }

    /// 多板块聚合（每板块一个 SectorStatistics · 按 Sector enum 顺序）
    public static func computeAll(_ instruments: [SectorInstrument]) -> [SectorStatistics] {
        Sector.allCases.map { sec in
            let bySec = instruments.filter { $0.sector == sec }
            return compute(bySec, sector: sec)
        }
    }
}
