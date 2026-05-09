// 异常检测器（v15.54 · ⌘⌥A 异常品种监控）
//
// 纯函数 · 输入 [SectorInstrument] + AnomalyThresholds → 输出 AnomalyDetectionResult
// 5 检测算法各自独立 · 同一品种可命中多类 · 严重度归一化到 [0, 100]
//
// 设计要点（Karpathy）：
// - 算法层不引 SwiftUI · 不引 Date 之外的运行时
// - 不预留 ML 接口 · v2 接 CTP 后这层算法直接复用
// - mock 公式与 ⌘⌥N 资金流向 / ⌘⌥B 板块联动一致 · trader 看到一致量纲

import Foundation

public enum AnomalyDetector {

    /// 全市场扫描 · 5 类异常并行
    /// - Parameters:
    ///   - instruments: 全市场快照（默认 SectorPresets.all）
    ///   - thresholds: 阈值配置
    ///   - now: 检测时间戳（注入便于测试）
    public static func scan(
        instruments: [SectorInstrument] = SectorPresets.all,
        thresholds: AnomalyThresholds = .default,
        now: Date = Date()
    ) -> AnomalyDetectionResult {
        var events: [AnomalyEvent] = []

        if thresholds.enabledKinds.contains(.priceSpike) {
            events.append(contentsOf: detectPriceSpike(instruments: instruments, threshold: thresholds.priceSpikePct, now: now))
        }
        if thresholds.enabledKinds.contains(.oiSpike) {
            events.append(contentsOf: detectOISpike(instruments: instruments, multiple: thresholds.oiSpikeMultiple, now: now))
        }
        if thresholds.enabledKinds.contains(.fundSurge) {
            events.append(contentsOf: detectFundSurge(instruments: instruments, thresholdMillion: thresholds.fundSurgeMillion, now: now))
        }
        if thresholds.enabledKinds.contains(.priceOIDivergence) {
            events.append(contentsOf: detectPriceOIDivergence(instruments: instruments, now: now))
        }
        if thresholds.enabledKinds.contains(.sectorOutlier) {
            events.append(contentsOf: detectSectorOutlier(instruments: instruments, now: now))
        }

        events.sort { $0.severity > $1.severity }

        var countByKind: [AnomalyKind: Int] = [:]
        var countBySector: [Sector: Int] = [:]
        for e in events {
            countByKind[e.kind, default: 0] += 1
            countBySector[e.sector, default: 0] += 1
        }

        return AnomalyDetectionResult(events: events, countByKind: countByKind, countBySector: countBySector)
    }

    // MARK: - 价格异动

    /// |changePct| ≥ threshold（百分比 · threshold = 2.0 表示 2%）
    /// severity = min(100, |changePct| / threshold × 50) · 2× 阈值 → 100 分
    public static func detectPriceSpike(
        instruments: [SectorInstrument],
        threshold: Double,
        now: Date = Date()
    ) -> [AnomalyEvent] {
        guard threshold > 0 else { return [] }
        return instruments.compactMap { inst in
            let absPct = abs(inst.changePct)
            guard absPct >= threshold else { return nil }
            let severity = min(100.0, absPct / threshold * 50.0)
            let direction = inst.changePct > 0 ? "上涨" : "下跌"
            let desc = String(format: "%@ %@ %.2f%%（阈值 %.1f%%）", inst.name, direction, absPct, threshold)
            return AnomalyEvent(
                instrumentID: inst.id,
                instrumentName: inst.name,
                sector: inst.sector,
                kind: .priceSpike,
                severity: severity,
                description: desc,
                detectedAt: now
            )
        }
    }

    // MARK: - 持仓异动

    /// openInterestK / 板块均值 ≥ multiple
    /// severity = min(100, (ratio - 1) / (multiple - 1) × 50) · 2× multiple → 100 分
    public static func detectOISpike(
        instruments: [SectorInstrument],
        multiple: Double,
        now: Date = Date()
    ) -> [AnomalyEvent] {
        guard multiple > 1.0 else { return [] }
        let bySector = Dictionary(grouping: instruments, by: \.sector)
        var events: [AnomalyEvent] = []
        for (sector, list) in bySector {
            guard list.count >= 2 else { continue }
            let avg = list.map(\.openInterestK).reduce(0, +) / Double(list.count)
            guard avg > 0 else { continue }
            for inst in list {
                let ratio = inst.openInterestK / avg
                guard ratio >= multiple else { continue }
                let severity = min(100.0, (ratio - 1.0) / (multiple - 1.0) * 50.0)
                let desc = String(format: "%@ 持仓 %.0fK · %@ 板块均值 %.0fK 的 %.2f×（阈值 %.1f×）",
                                  inst.name, inst.openInterestK, sector.displayName, avg, ratio, multiple)
                events.append(AnomalyEvent(
                    instrumentID: inst.id,
                    instrumentName: inst.name,
                    sector: inst.sector,
                    kind: .oiSpike,
                    severity: severity,
                    description: desc,
                    detectedAt: now
                ))
            }
        }
        return events
    }

    // MARK: - 资金异动

    /// netInflow = openInterestK × changePct × 0.5（百万元 · 与 ⌘⌥N 公式一致）
    /// severity = min(100, |netInflow| / threshold × 50)
    public static func detectFundSurge(
        instruments: [SectorInstrument],
        thresholdMillion: Double,
        now: Date = Date()
    ) -> [AnomalyEvent] {
        guard thresholdMillion > 0 else { return [] }
        return instruments.compactMap { inst in
            let netInflow = inst.openInterestK * inst.changePct * 0.5
            let absFlow = abs(netInflow)
            guard absFlow >= thresholdMillion else { return nil }
            let severity = min(100.0, absFlow / thresholdMillion * 50.0)
            let direction = netInflow > 0 ? "净流入" : "净流出"
            let desc = String(format: "%@ %@ %.1f 百万元（阈值 %.0f 百万）",
                              inst.name, direction, absFlow, thresholdMillion)
            return AnomalyEvent(
                instrumentID: inst.id,
                instrumentName: inst.name,
                sector: inst.sector,
                kind: .fundSurge,
                severity: severity,
                description: desc,
                detectedAt: now
            )
        }
    }

    // MARK: - 量价背离

    /// mock：基于 instrument id hash 标记 ~15% 品种为背离
    /// 涨价但减仓（多头乏力）/ 跌价但增仓（空头加仓）
    /// v2 接 CTP 后基于真实持仓变化 ΔOI 判断
    /// severity 基于 |changePct| × 标记强度
    public static func detectPriceOIDivergence(
        instruments: [SectorInstrument],
        now: Date = Date()
    ) -> [AnomalyEvent] {
        return instruments.compactMap { inst in
            // 稳定 hash · 同一 id 每次扫描结果一致
            let hash = abs(inst.id.hashValue)
            guard hash % 7 == 0 else { return nil }  // ~14% 命中
            // 量价方向：涨价 → "减仓"（多头乏力）/ 跌价 → "增仓"（空头加仓）
            let direction = inst.changePct >= 0 ? "涨价减仓 · 多头乏力" : "跌价增仓 · 空头加仓"
            let absPct = abs(inst.changePct)
            // 严重度：abs changePct 越大背离越显著 · 上限 100
            let severity = min(100.0, 30.0 + absPct * 25.0)
            let desc = String(format: "%@ %@（涨跌幅 %+.2f%% · 持仓 %.0fK）",
                              inst.name, direction, inst.changePct, inst.openInterestK)
            return AnomalyEvent(
                instrumentID: inst.id,
                instrumentName: inst.name,
                sector: inst.sector,
                kind: .priceOIDivergence,
                severity: severity,
                description: desc,
                detectedAt: now
            )
        }
    }

    // MARK: - 板块离群

    /// 同板块多数（≥ 60%）方向一致时 · 反向品种为离群
    /// 板块仅 1-2 个品种时不判定（样本不足）
    /// severity 基于 |changePct| 和板块共识强度
    public static func detectSectorOutlier(
        instruments: [SectorInstrument],
        now: Date = Date()
    ) -> [AnomalyEvent] {
        let bySector = Dictionary(grouping: instruments, by: \.sector)
        var events: [AnomalyEvent] = []
        for (_, list) in bySector {
            guard list.count >= 3 else { continue }
            let upCount = list.filter { $0.changePct > 0 }.count
            let downCount = list.filter { $0.changePct < 0 }.count
            let total = list.count
            // 共识：多数方向 ≥ 60%
            let upConsensus = Double(upCount) / Double(total)
            let downConsensus = Double(downCount) / Double(total)
            let majority: Bool? = {
                if upConsensus >= 0.6 { return true }
                if downConsensus >= 0.6 { return false }
                return nil
            }()
            guard let isUp = majority else { continue }
            let consensusPct = isUp ? upConsensus : downConsensus
            for inst in list {
                let isOutlier = isUp ? (inst.changePct < 0) : (inst.changePct > 0)
                guard isOutlier, abs(inst.changePct) >= 0.1 else { continue }  // 接近 0 不算离群
                let absPct = abs(inst.changePct)
                let severity = min(100.0, consensusPct * 60.0 + absPct * 10.0)
                let majorityWord = isUp ? "多数上涨" : "多数下跌"
                let myWord = inst.changePct > 0 ? "独自上涨" : "独自下跌"
                let desc = String(format: "%@ %@ %+.2f%% · %@ 板块 %@（%.0f%% 同向）",
                                  inst.name, myWord, inst.changePct, inst.sector.displayName,
                                  majorityWord, consensusPct * 100)
                events.append(AnomalyEvent(
                    instrumentID: inst.id,
                    instrumentName: inst.name,
                    sector: inst.sector,
                    kind: .sectorOutlier,
                    severity: severity,
                    description: desc,
                    detectedAt: now
                ))
            }
        }
        return events
    }
}
