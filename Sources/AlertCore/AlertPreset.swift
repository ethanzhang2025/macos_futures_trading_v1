// WP-52 v15.19 batch26 · 预警预设模板（trader 一键创建常用预警 · 提升工作流）
//
// 设计取舍：
// - 纯函数 · 输入 instrumentID + lastPrice → 返回 Alert（pre-configured）
// - 6 类常用预设：涨停（+5%）/ 跌停（-5%）/ Donchian 突破上 / Donchian 突破下 / 急动 1% / 成交量异动 3×
// - 名称中文 · trader 一眼看懂 · UI 直接展示
// - cooldown / channels 用合理默认（60s + inApp+systemNotice）

import Foundation
import Shared

public enum AlertPreset: String, Sendable, CaseIterable, Identifiable {
    case limitUp           // 涨停 · 当前价 +5%
    case limitDown         // 跌停 · 当前价 -5%
    case breakoutHighDay   // 突破前 20 根 15m 高
    case breakoutLowDay    // 跌破前 20 根 15m 低
    case priceSpike        // 急动 ≥1% / 60s
    case volumeSpike       // 成交量 ≥3× / 20 根

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .limitUp:         return "涨停预警（+5%）"
        case .limitDown:       return "跌停预警（-5%）"
        case .breakoutHighDay: return "突破前 20 根 15m 高"
        case .breakoutLowDay:  return "跌破前 20 根 15m 低"
        case .priceSpike:      return "急动 ≥1% / 60s"
        case .volumeSpike:     return "成交量 ≥3× / 20 根"
        }
    }

    public var helpText: String {
        switch self {
        case .limitUp:         return "当前价 +5% 触发 · 期货跌停板预警"
        case .limitDown:       return "当前价 -5% 触发 · 期货涨停板预警"
        case .breakoutHighDay: return "Donchian 突破 · trader 顺势启动经典信号"
        case .breakoutLowDay:  return "Donchian 跌破 · 反向趋势启动信号"
        case .priceSpike:      return "1 分钟内价格变化 ≥1% · 黑天鹅捕捉"
        case .volumeSpike:     return "成交量瞬间放大 3 倍以上 · 资金异动"
        }
    }

    /// 生成具体的 Alert 实例
    /// - Parameters:
    ///   - instrumentID: 合约（必填）
    ///   - lastPrice: 当前价（涨停/跌停需要 · 其他可传 0）
    public func makeAlert(instrumentID: String, lastPrice: Decimal) -> Alert {
        let cooldown: TimeInterval = 60
        let channels: Set<NotificationChannelKind> = [.inApp, .systemNotice]
        let condition: AlertCondition
        let name: String
        switch self {
        case .limitUp:
            let target = lastPrice * Decimal(string: "1.05")!
            condition = .priceCrossAbove(target)
            name = "\(instrumentID) 涨停预警"
        case .limitDown:
            let target = lastPrice * Decimal(string: "0.95")!
            condition = .priceCrossBelow(target)
            name = "\(instrumentID) 跌停预警"
        case .breakoutHighDay:
            condition = .priceBreakoutHigh(period: .minute15, lookback: 20)
            name = "\(instrumentID) 突破前 20 根高"
        case .breakoutLowDay:
            condition = .priceBreakoutLow(period: .minute15, lookback: 20)
            name = "\(instrumentID) 跌破前 20 根低"
        case .priceSpike:
            condition = .priceMoveSpike(percentThreshold: Decimal(string: "0.01")!, windowSeconds: 60)
            name = "\(instrumentID) 急动预警"
        case .volumeSpike:
            condition = .volumeSpike(multiple: 3, windowBars: 20)
            name = "\(instrumentID) 成交量异动"
        }
        return Alert(
            name: name,
            instrumentID: instrumentID,
            condition: condition,
            channels: channels,
            cooldownSeconds: cooldown
        )
    }

    /// 批量生成（trader 一键创建多个预警）
    public static func makeAlerts(_ presets: [AlertPreset],
                                   instrumentID: String,
                                   lastPrice: Decimal) -> [Alert] {
        presets.map { $0.makeAlert(instrumentID: instrumentID, lastPrice: lastPrice) }
    }
}
