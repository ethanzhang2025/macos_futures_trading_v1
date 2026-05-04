// WP-42 · 画线 K 线吸附纯函数（v15.18）
//
// 设计取舍：
// - trader 强需求：画线时关键价位（O/H/L/C）"咬住"K 线 · 替代肉眼对齐
// - 候选价：O / H / L / C / 中点(O+C)/2 · 5 个候选选距 raw 最近
// - 阈值控制：thresholdRatio × visibleSpan · 默认 1.5%（密集 K 线偏严 · 远点不强吸）
// - 抽 Shared 纯函数 · MainApp ChartScene.screenToDataPoint 调用 · Linux 单测覆盖

import Foundation

public enum CandleSnapPolicy {

    /// 画线价格吸附到最近 K 线 OHLC
    /// - Parameters:
    ///   - rawPrice: 屏幕坐标反推的原始价格
    ///   - open / high / low / close: 当前 K 线 OHLC
    ///   - visibleSpan: 当前可视价格区间（hi - lo）· 阈值参考量
    ///   - thresholdRatio: 阈值占 span 的比例（默认 1.5%）
    /// - Returns: 吸附后的价格 · 阈值外保留 raw price
    public static func snapPrice(
        rawPrice: Double,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        visibleSpan: Double,
        thresholdRatio: Double = 0.015
    ) -> Double {
        let mid = (open + close) / 2
        let candidates = [open, high, low, close, mid]
        let threshold = max(0, visibleSpan) * thresholdRatio
        var best = rawPrice
        var bestDist = threshold
        for cand in candidates {
            let d = abs(cand - rawPrice)
            if d <= bestDist {
                bestDist = d
                best = cand
            }
        }
        return best
    }
}
