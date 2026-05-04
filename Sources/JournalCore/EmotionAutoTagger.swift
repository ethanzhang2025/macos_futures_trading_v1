// WP-53 v15.19 batch21 · 自动情绪 / 标签建议（trader 复盘时一键看心理风险）
//
// 设计取舍：
// - 纯函数 · 无副作用 · 不修改 ClosedPosition
// - 仅"建议"标签 · 用户在 JournalWindow 编辑日志时可采纳或忽略
// - Context 把全局视角（连胜连败 + avg win/loss）注入单笔判定 · 与 streakMetrics 同 sign-run 模式
//
// 阈值（trader 经验值 · 后续可改可调）：
//   连败 ≥ 3 笔 → 复仇心态（revengeAfterLosses）· 警告：心理失衡风险大
//   连胜 ≥ 5 笔 → 连胜得意（overconfident）· 警告：仓位过大风险
//   单笔盈利 > avgWin × 3 → 豪赌仓位（oversize）· 即使赢也是侥幸
//   单笔亏损 > avgLoss × 3 → 亏损失控（lossOfControl）· 止损执行不严
//   持仓 < 60s   → 短炒（scalp）
//   持仓 > 7 day → 长持（heldTooLong）

import Foundation
import Shared

public enum EmotionAutoTagger {

    /// 6 类自动建议标签
    public enum Tag: String, Sendable, Codable, CaseIterable {
        case revengeAfterLosses    // 复仇心态（连败 ≥3 后下单）
        case overconfident         // 连胜得意（连胜 ≥5 后下单）
        case oversize              // 豪赌仓位（单笔盈利 > avgWin×3）
        case lossOfControl         // 亏损失控（单笔亏损 > avgLoss×3）
        case scalp                 // 短炒（持仓 < 60s）
        case heldTooLong           // 长持（持仓 > 7 天）

        public var displayName: String {
            switch self {
            case .revengeAfterLosses: return "复仇心态"
            case .overconfident:      return "连胜得意"
            case .oversize:           return "豪赌仓位"
            case .lossOfControl:      return "亏损失控"
            case .scalp:              return "短炒"
            case .heldTooLong:        return "长持"
            }
        }

        /// 推断到 JournalEmotion · 同时给标签和情绪建议（一对多 → 取首个 emotion · UI 可让用户改）
        public var suggestedEmotion: JournalEmotion {
            switch self {
            case .revengeAfterLosses: return .fearful   // 复仇 ≈ 情绪化（fearful 最近）
            case .overconfident:      return .greedy
            case .oversize:           return .greedy
            case .lossOfControl:      return .fearful
            case .scalp:              return .calm
            case .heldTooLong:        return .calm
            }
        }
    }

    /// 单笔评估上下文（前置 streak · 历史平均 win/loss）
    public struct Context: Sendable, Equatable {
        public let priorStreak: Int           // 本笔之前 streak · 正连胜 / 负连败 / 0
        public let avgWin: Decimal            // 历史平均盈利金额（>0 才有意义）
        public let avgLoss: Decimal           // 历史平均亏损金额（绝对值）

        public init(priorStreak: Int = 0, avgWin: Decimal = 0, avgLoss: Decimal = 0) {
            self.priorStreak = priorStreak
            self.avgWin = avgWin
            self.avgLoss = avgLoss
        }
    }

    /// 单笔自动标签
    public static func tags(for position: ClosedPosition, context: Context) -> [Tag] {
        var out: [Tag] = []
        if context.priorStreak <= -3 { out.append(.revengeAfterLosses) }
        if context.priorStreak >= 5  { out.append(.overconfident) }
        let pnl = position.realizedPnL
        if pnl > 0, context.avgWin > 0, pnl > context.avgWin * 3 {
            out.append(.oversize)
        } else if pnl < 0, context.avgLoss > 0, -pnl > context.avgLoss * 3 {
            out.append(.lossOfControl)
        }
        let secs = position.holdingSeconds
        if secs < 60 { out.append(.scalp) }
        else if secs > 7 * 86_400 { out.append(.heldTooLong) }
        return out
    }

    /// 整批自动标签 · 按 closeTime 升序遍历 · 维护 streak + 累积 win/loss 平均
    /// 与 ReviewAnalytics.streakMetrics 同 sign-run 模式 · 平交易（PnL=0）跳过
    public static func tagAll(_ positions: [ClosedPosition]) -> [(position: ClosedPosition, tags: [Tag])] {
        let sorted = positions.sorted { $0.closeTime < $1.closeTime }
        var streak = 0
        var winSum: Decimal = 0
        var lossSum: Decimal = 0
        var winCount = 0
        var lossCount = 0
        var result: [(ClosedPosition, [Tag])] = []
        result.reserveCapacity(sorted.count)
        for p in sorted {
            let avgWin = winCount > 0 ? winSum / Decimal(winCount) : 0
            let avgLoss = lossCount > 0 ? lossSum / Decimal(lossCount) : 0
            let ctx = Context(priorStreak: streak, avgWin: avgWin, avgLoss: avgLoss)
            result.append((p, tags(for: p, context: ctx)))
            // 推进 streak / 累积（与 streakMetrics 一致：平交易跳过）
            let pnl = p.realizedPnL
            if pnl > 0 {
                if streak < 0 { streak = 0 }
                streak += 1
                winSum += pnl
                winCount += 1
            } else if pnl < 0 {
                if streak > 0 { streak = 0 }
                streak -= 1
                lossSum += -pnl
                lossCount += 1
            }
        }
        return result
    }
}
