// WP-23 模块 1 · Feature Flag 枚举命名空间
// D2 §2 设计原则：所有功能门控统一通过 FeatureFlagService 读取，业务层不散落 if flag.xxx
//
// 命名空间组织：
// - subscription / import / replay / alert / experimental
// rawValue 与远程 JSON key 一一对齐（驼峰命名，便于 JSON 序列化）

import Foundation

/// 全部功能 flag 的命名空间 · 编译期类型安全
public enum FeatureFlag: String, Sendable, Codable, CaseIterable, Equatable, Hashable {

    // MARK: - 订阅 / 商业化（subscription.*）
    /// 订阅墙是否启用（M5 末上线决策；默认关闭）
    case subscriptionPaywall = "subscription.paywall"
    /// Pro 7 天免费试用（默认关闭，避免暗扣）
    case subscriptionFreeTrial = "subscription.freeTrial"

    // MARK: - 数据导入（import.*）
    /// 文华格式 CSV 导入（已实现，默认开）
    case importWenhua = "import.wenhua"
    /// 通用格式 CSV 导入（默认开）
    case importGeneric = "import.generic"

    // MARK: - 复盘 / 回放（review.* / replay.*）
    /// K 线回放（已实现 WP-51，默认开）
    case replayMode = "replay.mode"
    /// 复盘 8 张图（已实现 WP-50，默认开）
    case reviewCharts = "review.charts"

    // MARK: - 预警（alert.*）
    /// 条件预警中心（已实现 WP-52，默认开）
    case alertCenter = "alert.center"
    /// 系统通知中心（macOS UserNotifications，留 Mac 切机；默认关）
    case alertSystemNotification = "alert.systemNotification"
    /// 声音提醒（默认关，避免打扰）
    case alertSound = "alert.sound"

    // MARK: - 实验性（experimental.*）
    /// 麦语言完整模式（Stage B；默认关）
    case experimentalFormulaCompleteMode = "experimental.formulaCompleteMode"
    /// AI 辅助分析（Stage B 后；默认关）
    case experimentalAIAssist = "experimental.aiAssist"

    /// 默认值（远程 + 本地都未设置时的兜底）
    public var defaultValue: Bool {
        switch self {
        // 已实现 + 安全的功能默认开
        case .importWenhua, .importGeneric, .replayMode, .reviewCharts, .alertCenter:
            return true
        // 商业化 / 通知 / 实验性默认关
        case .subscriptionPaywall, .subscriptionFreeTrial,
             .alertSystemNotification, .alertSound,
             .experimentalFormulaCompleteMode, .experimentalAIAssist:
            return false
        }
    }

    /// 命名空间前缀（用于远程 JSON 分组渲染 / UI 设置面板分组）
    public var namespace: String {
        String(rawValue.prefix(while: { $0 != "." }))
    }
}
