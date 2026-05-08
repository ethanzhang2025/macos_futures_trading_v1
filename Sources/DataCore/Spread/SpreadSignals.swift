// 套利信号生成器（v15.37 · 套利分析 V2）
//
// 基于滚动 Z-score 阈值生成进出场信号 · 状态机驱动 · 单边持仓
//
// 信号规则：
//   - 无仓位 + 滚动 Z >= +entryThreshold → 进场做空价差（预期向均值回归向下）
//   - 无仓位 + 滚动 Z <= -entryThreshold → 进场做多价差（预期向均值回归向上）
//   - 持空 + Z <= +exitThreshold → 平空出场
//   - 持多 + Z >= -exitThreshold → 平多出场
//   - 持仓持续超过 maxHoldingBars → 强平（防止永久套牢）
//
// 单边持仓约束：进场后必须先出场才能开新仓 · 不重叠 · 简化回测语义

import Foundation

public struct SpreadSignal: Sendable, Equatable {

    public enum Side: Sendable, Equatable {
        case long       // 做多价差（Z 极低 · 价差太低 · 预期向上）
        case short      // 做空价差（Z 极高 · 价差太高 · 预期向下）
    }

    public enum Action: Sendable, Equatable {
        case entry      // 进场
        case exit       // 出场
    }

    public let index: Int               // bars[index]
    public let openTime: Date
    public let value: Decimal           // 该点价差值
    public let zScore: Double           // 该点滚动 Z-score
    public let side: Side
    public let action: Action

    public init(index: Int, openTime: Date, value: Decimal, zScore: Double,
                side: Side, action: Action) {
        self.index = index
        self.openTime = openTime
        self.value = value
        self.zScore = zScore
        self.side = side
        self.action = action
    }
}

public enum SpreadSignalGenerator {

    /// 生成进出场信号序列
    /// - Parameters:
    ///   - values: 价差时序
    ///   - rollingZScores: 与 values 等长的滚动 Z 时序（来自 SpreadStatisticsCalculator.rollingZScores）
    ///   - entryThreshold: 进场 |Z| 阈值（默认 2.0 · 极值入场）
    ///   - exitThreshold: 出场 |Z| 阈值（默认 0.5 · 接近均值出场）
    ///   - maxHoldingBars: 最长持仓周期（防永久套牢 · 默认 60）
    /// - Returns: 信号序列 · 按时间升序 · entry/exit 严格成对
    public static func generate(
        values: [SpreadValue],
        rollingZScores: [Double],
        entryThreshold: Double = 2.0,
        exitThreshold: Double = 0.5,
        maxHoldingBars: Int = 60
    ) -> [SpreadSignal] {
        guard values.count == rollingZScores.count, !values.isEmpty else { return [] }

        var signals: [SpreadSignal] = []
        var currentSide: SpreadSignal.Side? = nil
        var entryIdx: Int = 0

        for i in 0..<values.count {
            let z = rollingZScores[i]
            let v = values[i]

            if let side = currentSide {
                // 持仓中 · 检查出场
                let holdingTooLong = (i - entryIdx) >= maxHoldingBars
                let zReturned: Bool
                switch side {
                case .long:  zReturned = z >= -exitThreshold
                case .short: zReturned = z <= +exitThreshold
                }
                if zReturned || holdingTooLong {
                    signals.append(SpreadSignal(
                        index: i, openTime: v.openTime, value: v.value, zScore: z,
                        side: side, action: .exit
                    ))
                    currentSide = nil
                }
            } else {
                // 无仓位 · 检查进场
                if z >= +entryThreshold {
                    signals.append(SpreadSignal(
                        index: i, openTime: v.openTime, value: v.value, zScore: z,
                        side: .short, action: .entry
                    ))
                    currentSide = .short
                    entryIdx = i
                } else if z <= -entryThreshold {
                    signals.append(SpreadSignal(
                        index: i, openTime: v.openTime, value: v.value, zScore: z,
                        side: .long, action: .entry
                    ))
                    currentSide = .long
                    entryIdx = i
                }
            }
        }

        // 末尾若仍持仓 · 用末样本强平（避免回测有未平仓 trade 误导统计）
        if let side = currentSide, let last = values.indices.last {
            let v = values[last]
            signals.append(SpreadSignal(
                index: last, openTime: v.openTime, value: v.value,
                zScore: rollingZScores[last], side: side, action: .exit
            ))
        }

        return signals
    }
}
