// v17.189 · 多合约 chart overlay 归一化核心（RB vs HC 同图叠加 normalized close · 国际派必备）
//
// 用途：主图叠加 secondary instrument 的 close 曲线 · 让两条线起点重合或同坐标系比对走势
// 模式：
//   firstBaseline · 按 secondary[0] 为基线 · 百分比变化映射到 primary[0] 的"虚拟价格"（trader 直观看相对涨跌）
//   minMax · 把 secondary 的 [min, max] 线性缩放到 primary 的 [min, max]（趋势比对 · 忽略起点）
//
// 时间对齐：alignByOpenTime · 按 primary 时间序对每根 bar 找 secondary 中 ≤ 该时刻的最近一根（最近邻 hold-last）
// 不做：异步加载（caller 走 storeManager.kline.load） · UI 渲染（caller 走 ChartScene overlay）

import Foundation
import Shared

public enum MultiInstrumentNormalizer {

    public enum Mode: String, Sendable, Codable, CaseIterable {
        case firstBaseline   // secondary[0] 对齐 primary[0] · 之后按百分比变化映射 · trader 看"相对涨跌"
        case minMax          // secondary [min,max] 线性缩放到 primary [min,max] · trader 看"趋势同向性"

        public var displayName: String {
            switch self {
            case .firstBaseline: return "起点对齐"
            case .minMax:        return "区间对齐"
            }
        }
    }

    /// 把 secondary 价格序列归一化到 primary 的价格刻度
    /// - Parameters:
    ///   - primary: 主合约 close 序列（保留原值参考）
    ///   - secondary: 副合约 close 序列（待归一化）
    ///   - mode: 归一化模式
    /// - Returns: 同 secondary 长度 · 已映射到 primary 价格刻度的虚拟价格序列
    public static func normalizeToPrimaryScale(
        primary: [Decimal],
        secondary: [Decimal],
        mode: Mode = .firstBaseline
    ) -> [Decimal] {
        guard !primary.isEmpty, !secondary.isEmpty else { return [] }
        let primaryBase = primary[0]
        switch mode {
        case .firstBaseline:
            let secondaryBase = secondary[0]
            guard secondaryBase > 0 else {
                return Array(repeating: primaryBase, count: secondary.count)
            }
            return secondary.map { s in
                primaryBase * (1 + (s - secondaryBase) / secondaryBase)
            }
        case .minMax:
            guard let pmin = primary.min(), let pmax = primary.max(),
                  let smin = secondary.min(), let smax = secondary.max(),
                  pmax > pmin, smax > smin else {
                return Array(repeating: primaryBase, count: secondary.count)
            }
            let primaryRange = pmax - pmin
            let secondaryRange = smax - smin
            return secondary.map { s in
                pmin + (s - smin) * primaryRange / secondaryRange
            }
        }
    }

    /// 按 primary 时间序对齐 secondary（最近邻 hold-last · 节假日/停盘缺口时用上一根 secondary）
    /// - Returns: secondary 按 primary 长度对齐 · primary 原样回传方便链式
    public static func alignByOpenTime(
        primary: [KLine],
        secondary: [KLine]
    ) -> (primary: [KLine], secondary: [KLine]) {
        guard !primary.isEmpty, !secondary.isEmpty else { return (primary, []) }
        let secondaryTimes = secondary.map(\.openTime)
        var aligned: [KLine] = []
        aligned.reserveCapacity(primary.count)
        for p in primary {
            let pT = p.openTime
            // 二分找 ≤ pT 的最大 idx · 若 pT 早于 secondary[0] 退回 secondary[0]
            if pT < secondaryTimes[0] {
                aligned.append(secondary[0])
                continue
            }
            var lo = 0
            var hi = secondaryTimes.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if secondaryTimes[mid] <= pT { lo = mid } else { hi = mid - 1 }
            }
            aligned.append(secondary[lo])
        }
        return (primary, aligned)
    }
}
