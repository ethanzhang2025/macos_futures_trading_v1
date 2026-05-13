// v17.172 · 跨合约联动预警（期货套利核心 · M6 卖点）
//
// 场景：
//   trader 配置规则："螺纹 RB 涨停 → 检查热卷 HC 是否跟涨"
//   规则触发时 · 反馈是否符合预期联动（"跟涨"达预期 / "背离"未达 / "未触发"）
//
// 用途：
//   - 期货品种联动套利（RB-HC / 大豆-豆粕-豆油 / 铁矿-焦煤-焦炭）
//   - 跨市场背离套利（如沪深 300 与 IF 主力的基差 outliers）
//
// v1 简单 · 纯数据评估 ·  UI/notification 集成 v2 接 AlertCore
//
// 不做：
// - 实时 tick 流处理（caller 自己定时调 evaluate）
// - 多腿组合（>2 instrument）· 留 v3

import Foundation

/// 触发条件类型
public enum CrossLinkageTriggerKind: String, Sendable, Codable, CaseIterable {
    /// 上涨 ≥ threshold%（相对前一日收盘 / 开盘 · caller 提供基准）
    case riseAtLeast
    /// 下跌 ≥ threshold%
    case fallAtLeast
    /// 涨停（特殊：threshold 由 caller 标定为合约涨停板百分比 · 如 RB 7%）
    case limitUp
    /// 跌停
    case limitDown

    public var displayName: String {
        switch self {
        case .riseAtLeast: return "上涨≥阈值"
        case .fallAtLeast: return "下跌≥阈值"
        case .limitUp:     return "涨停"
        case .limitDown:   return "跌停"
        }
    }
}

/// 期望联动方向（trigger 触发时 · watch 应该如何动）
public enum CrossLinkageExpectation: String, Sendable, Codable, CaseIterable {
    /// 跟涨（同向）· watch 涨幅 ≥ watchThresholdPct
    case followUp
    /// 跟跌（同向）· watch 跌幅 ≥ watchThresholdPct
    case followDown
    /// 背离（反向）· watch 与 trigger 方向相反 且变动 ≥ watchThresholdPct
    case divergeOpposite
    /// 未动（套利信号）· watch 变动 ≤ watchThresholdPct（trigger 动了 · watch 没动）
    case lagBehind

    public var displayName: String {
        switch self {
        case .followUp:        return "跟涨"
        case .followDown:      return "跟跌"
        case .divergeOpposite: return "背离"
        case .lagBehind:       return "滞后"
        }
    }
}

/// 一条联动规则（trader 配置 · v1 内存 · v2 持久化 + UI 编辑）
public struct CrossInstrumentLinkageRule: Sendable, Codable, Equatable {
    public var ruleID: String
    public var triggerInstrument: String
    public var triggerKind: CrossLinkageTriggerKind
    /// 触发阈值百分比（riseAtLeast/fallAtLeast 用；limitUp/Down 用涨停板百分比如 7.0）
    public var triggerThresholdPct: Double
    public var watchInstrument: String
    public var expectation: CrossLinkageExpectation
    /// watch 判定阈值百分比（跟涨/跟跌 = 至少 N% · 滞后 = 至多 N%）
    public var watchThresholdPct: Double
    public var enabled: Bool

    public init(
        ruleID: String,
        triggerInstrument: String,
        triggerKind: CrossLinkageTriggerKind,
        triggerThresholdPct: Double,
        watchInstrument: String,
        expectation: CrossLinkageExpectation,
        watchThresholdPct: Double,
        enabled: Bool = true
    ) {
        self.ruleID = ruleID
        self.triggerInstrument = triggerInstrument
        self.triggerKind = triggerKind
        self.triggerThresholdPct = triggerThresholdPct
        self.watchInstrument = watchInstrument
        self.expectation = expectation
        self.watchThresholdPct = watchThresholdPct
        self.enabled = enabled
    }
}

/// 评估时输入的合约快照（caller 用最新价 / 基准价构造）
public struct CrossLinkageSnapshot: Sendable, Equatable {
    public let instrument: String
    public let lastPrice: Double
    /// 基准价（一般 = 昨日结算 / 当日开盘 / 涨跌幅起算价）
    public let basePrice: Double

    public init(instrument: String, lastPrice: Double, basePrice: Double) {
        self.instrument = instrument
        self.lastPrice = lastPrice
        self.basePrice = basePrice
    }

    /// 相对 base 的百分比变动（+/- · 0 = 无变动）
    public var changePct: Double {
        guard basePrice != 0 else { return 0 }
        return (lastPrice - basePrice) / basePrice * 100
    }
}

/// 评估结果（一次 evaluate 调用的产出 · trader / UI / 告警系统决定怎么用）
public struct CrossLinkageObservation: Sendable, Equatable {
    public enum Verdict: String, Sendable, Codable, Equatable {
        case notTriggered       // trigger 未达条件 · 不评估 watch
        case matched            // trigger 触发 · watch 也符合预期
        case mismatched         // trigger 触发 · watch 不符合预期（套利机会）
    }
    public let ruleID: String
    public let verdict: Verdict
    public let triggerChangePct: Double
    public let watchChangePct: Double
    /// 人类可读 message（弹窗 / log 用）
    public let message: String
}

public enum CrossInstrumentLinkage {

    /// 评估一条规则 · trigger 是否触发 + watch 是否符合预期
    /// 调用方约定：trigger / watch 必须分别对应 rule.triggerInstrument / rule.watchInstrument
    public static func evaluate(
        rule: CrossInstrumentLinkageRule,
        trigger: CrossLinkageSnapshot,
        watch: CrossLinkageSnapshot
    ) -> CrossLinkageObservation {
        guard rule.enabled else {
            return CrossLinkageObservation(
                ruleID: rule.ruleID, verdict: .notTriggered,
                triggerChangePct: trigger.changePct, watchChangePct: watch.changePct,
                message: "规则未启用"
            )
        }
        let triggerFired = isTriggerFired(rule: rule, trigger: trigger)
        guard triggerFired else {
            return CrossLinkageObservation(
                ruleID: rule.ruleID, verdict: .notTriggered,
                triggerChangePct: trigger.changePct, watchChangePct: watch.changePct,
                message: "trigger 未达条件"
            )
        }

        let watchOK = isExpectationMet(rule: rule, watch: watch)
        let verdict: CrossLinkageObservation.Verdict = watchOK ? .matched : .mismatched
        let msg = String(
            format: "%@ %@ %.2f%% · %@ %.2f%% → %@",
            rule.triggerInstrument, rule.triggerKind.displayName, trigger.changePct,
            rule.watchInstrument, watch.changePct,
            watchOK ? "符合\(rule.expectation.displayName)预期" : "不符\(rule.expectation.displayName)预期（套利机会）"
        )
        return CrossLinkageObservation(
            ruleID: rule.ruleID, verdict: verdict,
            triggerChangePct: trigger.changePct, watchChangePct: watch.changePct,
            message: msg
        )
    }

    /// 一次评估多条规则 · 批量返回（caller 一般定时跑）
    public static func evaluateAll(
        rules: [CrossInstrumentLinkageRule],
        snapshots: [String: CrossLinkageSnapshot]
    ) -> [CrossLinkageObservation] {
        rules.compactMap { rule in
            guard let trigger = snapshots[rule.triggerInstrument],
                  let watch = snapshots[rule.watchInstrument] else { return nil }
            return evaluate(rule: rule, trigger: trigger, watch: watch)
        }
    }

    // MARK: - helpers

    private static func isTriggerFired(rule: CrossInstrumentLinkageRule, trigger: CrossLinkageSnapshot) -> Bool {
        let pct = trigger.changePct
        switch rule.triggerKind {
        case .riseAtLeast: return pct >= rule.triggerThresholdPct
        case .fallAtLeast: return pct <= -rule.triggerThresholdPct
        case .limitUp:     return pct >= rule.triggerThresholdPct - 0.001  // 浮点容差
        case .limitDown:   return pct <= -(rule.triggerThresholdPct - 0.001)
        }
    }

    private static func isExpectationMet(rule: CrossInstrumentLinkageRule, watch: CrossLinkageSnapshot) -> Bool {
        let pct = watch.changePct
        switch rule.expectation {
        case .followUp:        return pct >= rule.watchThresholdPct
        case .followDown:      return pct <= -rule.watchThresholdPct
        case .divergeOpposite:
            switch rule.triggerKind {
            case .riseAtLeast, .limitUp:     return pct <= -rule.watchThresholdPct
            case .fallAtLeast, .limitDown:   return pct >= rule.watchThresholdPct
            }
        case .lagBehind:       return abs(pct) <= rule.watchThresholdPct
        }
    }
}
