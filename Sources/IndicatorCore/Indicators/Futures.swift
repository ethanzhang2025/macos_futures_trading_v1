// WP-41 第二批 · 期货特有类（除 OpenInterest 已在独立文件）
//
// 真实实现 1 个：OIDelta（ΔOI 持仓量变化）
//
// 占位说明（不实现，Stage A 输入结构无法支持；留给后续 WP 扩展输入后做）：
//   · 主力合约切换（MainContractShift）   —— 需合约连续接续（多合约数据）· 归 WP-21 CTP PoC 后补
//   · 涨跌停板线（LimitPriceLines）        —— 需每日涨跌停（合约规格，K 线不自带）· 归 FuturesContext 输入扩展
//   · 夜盘/日盘分界（SessionDivider）      —— 需每根 K 线的交易时段元数据 · 归 KLineSeries 扩时间字段后做
//   · 交割日倒计时（DeliveryCountdown）     —— 需合约交割日（合约规格）· 归 FuturesContext
//   · 结算价线（SettlementPriceLine）       —— 需每日结算价（行情 API 需提供）· 归 WP-21 数据扩展
//   · 多空力量（LongShortForce）            —— 需 Tick 级主动买/卖量 · 归 Tick 级数据通道（Stage B）
//   · 成交密度（VolumeDensity）             —— 需 Tick 级分布 · 同上
//   · 价差线（Spread）                      —— 需多合约同步数据 · 归 Stage B 多合约订阅
//   · 基差线（Basis）                       —— 需现货价格输入 · 归 Stage B 现货数据源
//   · 强弱对比（RelativeStrength）          —— 需两合约相对收益率 · 归 Stage B 多合约
//
// Stage A 的"期货特有 12 个指标"实际可支持 2 个（OI / ΔOI）；剩余 10 项在 WP-41 文档里标为"待后续 WP 扩展输入结构后完成"
// 这是 Karpathy 手术式决定：占位 stub + 抛 notImplemented 会让调用方误以为"已实现只是有问题"，直接不暴露 Swift 类型更干净

import Foundation
import Shared

// MARK: - OIDelta · 持仓量变化（持仓变动监测）
//
// WP-41 v3 第 14 批：OIDelta 实现 IncrementalIndicator · diff 模式（同 PVT 第 1 根=0 · 无周期）

public enum OIDelta: Indicator {
    public static let identifier = "DOI"
    public static let category: IndicatorCategory = .futures
    public static let parameters: [IndicatorParameter] = []

    public static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries] {
        let count = kline.count
        var out = [Decimal?](repeating: nil, count: count)
        guard count > 0 else { return [IndicatorSeries(name: "DOI", values: out)] }
        out[0] = 0
        for i in 1..<count {
            out[i] = Decimal(kline.openInterests[i] - kline.openInterests[i - 1])
        }
        return [IndicatorSeries(name: "DOI", values: out)]
    }
}

// MARK: - WP-41 v3 第 14 批 · OIDelta 增量 API（diff 模式 · 同 PVT 第 1 根=0 · 无周期）

extension OIDelta: IncrementalIndicator {

    /// state：prevOI（diff 计算 · 第 1 根 nil → 输出 0 与 calculate out[0]=0 一致）
    /// 类型 Decimal? 而非 Int?：因为 KLine.openInterest 是 Decimal（而 KLineSeries.openInterests 是 [Int]
    /// 历史不一致 · 增量内部统一用 Decimal · makeIncrementalState 把 Int 转 Decimal 传入）
    public struct IncrementalState: Sendable {
        public var prevOI: Decimal?
    }

    public static func makeIncrementalState(kline: KLineSeries, params: [Decimal]) throws -> IncrementalState {
        var state = IncrementalState(prevOI: nil)
        for oi in kline.openInterests {
            _ = processStep(state: &state, openInterest: Decimal(oi))
        }
        return state
    }

    public static func stepIncremental(state: inout IncrementalState, newBar: KLine) -> [Decimal?] {
        [processStep(state: &state, openInterest: newBar.openInterest)]
    }

    /// 第 1 根：prevOI=nil → 输出 0（与 calculate out[0]=0 一致 · diff 无前值参考）
    /// 第 2 根起：输出 OI - prev（与 calculate `out[i] = Decimal(oi[i] - oi[i-1])` 等价 · Decimal 减法精确）
    private static func processStep(state: inout IncrementalState, openInterest: Decimal) -> Decimal? {
        let result: Decimal = state.prevOI.map { openInterest - $0 } ?? 0
        state.prevOI = openInterest
        return result
    }
}
