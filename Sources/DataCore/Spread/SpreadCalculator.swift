// 价差时序计算器（v15.27 · WP-套利分析 V1）
//
// 输入：两腿的 K 线序列（KLine[]）+ 价差对（SpreadPair）
// 输出：[SpreadValue]（按 openTime 内连接 · 仅时间戳吻合的 bar 计入）
//
// 设计要点：
//   - 时间戳对齐：用 openTime Hash 表交集（避免 O(n²) 双层循环）
//   - 价差公式：value = leg1Close × ratio1 + leg2Close × ratio2（ratio 带符号）
//   - 跳过两腿任意 close = 0 / nil 的 bar（异常数据保护）

import Foundation
import Shared

public enum SpreadCalculator {

    /// 计算两腿价差时序
    /// - Parameters:
    ///   - pair: 价差对定义
    ///   - leg1Bars: 第 1 腿 K 线序列（按 openTime 升序 · 长度任意）
    ///   - leg2Bars: 第 2 腿 K 线序列（按 openTime 升序 · 长度任意）
    /// - Returns: 价差时序 · 按时间升序 · 只含两腿都有数据的时刻
    public static func calculate(
        pair: SpreadPair,
        leg1Bars: [KLine],
        leg2Bars: [KLine]
    ) -> [SpreadValue] {
        // 用 openTime（毫秒精度足够）建索引
        let leg2Map = Dictionary(uniqueKeysWithValues: leg2Bars.map { ($0.openTime, $0) })

        var result: [SpreadValue] = []
        result.reserveCapacity(min(leg1Bars.count, leg2Bars.count))

        let r1 = Decimal(pair.leg1.ratio)
        let r2 = Decimal(pair.leg2.ratio)

        for bar1 in leg1Bars {
            guard let bar2 = leg2Map[bar1.openTime] else { continue }
            // 异常数据保护：close ≤ 0 跳过
            guard bar1.close > 0 && bar2.close > 0 else { continue }
            let spread = bar1.close * r1 + bar2.close * r2
            result.append(SpreadValue(
                openTime: bar1.openTime,
                value: spread,
                leg1Close: bar1.close,
                leg2Close: bar2.close
            ))
        }
        return result
    }
}
