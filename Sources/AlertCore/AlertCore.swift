// AlertCore · 条件预警中心
// WP-24 占位骨架 · 后续 WP-52 填充；评估器可复用 Legacy TradingEngine/ConditionalOrder
// 职责：价格 / 画线 / 波动率成交量异常预警；App 内 + macOS 通知 + 声音；历史回看
// 禁做：不遗漏应触发的预警；不在低优先级线程跑触发判断（延迟影响体验）

import Foundation
import Shared
import DataCore
import IndicatorCore

public enum AlertCoreModule {
    public static let version = "0.1.0-skeleton"
}
