// v15.20 batch82 · K 线 swing high/low 检测（趋势可视化 · trader 找关键支撑阻力）
//
// 定义：
// - Swing High = bar i 的 high 严格大于前 N 根和后 N 根的 high
// - Swing Low  = bar i 的 low  严格小于前 N 根和后 N 根的 low
// - 边界 N 根（首/末）忽略 · 因为前/后窗口不完整
// - 严格大于（>）防平顶 / 平底产生过多噪声 swing
//
// 设计要点：
// - 纯函数 [KLine] → [SwingPoint]
// - lookback N 可配置（默认 5）· N=2 嫩噪声多 · N=10 关键趋势点
// - 不依赖 IndicatorCore · 仅用 KLine 字段（high/low/openTime）
// - barIndex 保留（UI 用 viewport 转屏幕 X）

import Foundation

public struct SwingPoint: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case high   // 局部高点
        case low    // 局部低点
    }

    public let kind: Kind
    public let barIndex: Int
    public let price: Decimal
    public let time: Date

    public init(kind: Kind, barIndex: Int, price: Decimal, time: Date) {
        self.kind = kind
        self.barIndex = barIndex
        self.price = price
        self.time = time
    }
}

public enum SwingPointsDetector {

    /// 检测全部 swing high/low
    /// - bars: K 线数组（按时间升序）
    /// - lookback: 前后窗口大小（默认 5 · 须 ≥1）
    /// - minBarSpacing: v15.21 batch105 · 同向 swing 最小 bar 间距（默认 0 不过滤 · >0 时密集合并保留更极值）
    public static func detect(_ bars: [KLine], lookback: Int = 5, minBarSpacing: Int = 0) -> [SwingPoint] {
        guard lookback >= 1, bars.count > 2 * lookback else { return [] }
        var out: [SwingPoint] = []
        for i in lookback..<(bars.count - lookback) {
            let bar = bars[i]
            let priorRange = (i - lookback)..<i
            let afterRange = (i + 1)...(i + lookback)

            // Swing High 判定
            let isLocalHigh = bars[priorRange].allSatisfy { bar.high > $0.high }
                && bars[afterRange].allSatisfy { bar.high > $0.high }
            if isLocalHigh {
                out.append(SwingPoint(kind: .high, barIndex: i, price: bar.high, time: bar.openTime))
                continue   // 同根不会同时是 swing low（high>low 必然）
            }

            // Swing Low 判定
            let isLocalLow = bars[priorRange].allSatisfy { bar.low < $0.low }
                && bars[afterRange].allSatisfy { bar.low < $0.low }
            if isLocalLow {
                out.append(SwingPoint(kind: .low, barIndex: i, price: bar.low, time: bar.openTime))
            }
        }
        return minBarSpacing > 0 ? filterDense(out, minSpacing: minBarSpacing) : out
    }

    /// v15.21 batch105 · 同向相邻 swing 距离 < minSpacing 时保留更极值（high 取大 · low 取小）
    /// 不同 kind 相邻不过滤（高 → 低 是有效结构 · 不算密集）
    static func filterDense(_ points: [SwingPoint], minSpacing: Int) -> [SwingPoint] {
        var kept: [SwingPoint] = []
        for p in points {
            if let last = kept.last, last.kind == p.kind, p.barIndex - last.barIndex < minSpacing {
                if (p.kind == .high && p.price > last.price)
                    || (p.kind == .low && p.price < last.price) {
                    kept[kept.count - 1] = p   // 替换为更极值
                }
                // 否则 last 已更极值 · 跳过 p
            } else {
                kept.append(p)
            }
        }
        return kept
    }
}
