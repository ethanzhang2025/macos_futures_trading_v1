// TradingCore · CTP 下单与条件单框架
// WP-30 迁入 Legacy Sources/TradingEngine/ConditionalOrder/*（止损/止盈/追踪/OCO/括号单）
// Stage A 不激活到 App 层；Stage B WP-220 起作为 CTP Bridge 的上游
// 职责：订单领域模型、条件单评估器（价格触发 / 追踪止损 / OCO 二选一 / 括号联动）
// 禁做：不把 CTP 原始回调暴露给 UI 层；安全模式未对账不允许下单

import Foundation
import Shared
import DataCore

public enum TradingCoreModule {
    public static let version = "0.1.0-legacy-import"
}
