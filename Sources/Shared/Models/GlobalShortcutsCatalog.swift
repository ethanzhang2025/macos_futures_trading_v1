// v17.141 · 全工程快捷键速查 catalog
// 数据驱动的总览：trader 在任何窗口按 ⌘⇧/ 都能看到全工程快捷键 + 当前窗口高亮
//
// 数据来源（手工梳理 · 后续加新快捷键时同步加）：
// - 全局菜单（FuturesTerminalApp.commands）：开窗 / 主题 / 工具
// - ChartScene shortcutsHelpOverlay：周期 / 视口 / 测距 / 显隐 / 主题 / 帮助 7 大类
// - WatchlistWindow / FormulaEditorWindow 等局部快捷键
//
// 设计取舍（Karpathy "避免过度复杂"）：
// - 静态数据 · 不读 SwiftUI runtime（KeyEquivalent 在 Linux 编译不友好）
// - 字符串 (key, description) 配对 · 中文化 description
// - WindowScope 枚举 · "current scope" 概念让 sheet 可以高亮当前窗口

import Foundation

/// 快捷键作用域（窗口分组）
public enum ShortcutWindowScope: String, CaseIterable, Sendable, Identifiable {
    case global         // 全局（任何窗口可触发：开窗 / 主题 / 帮助）
    case chart          // 主图（K 线图表）
    case watchlist      // 自选合约
    case journal        // 交易日志
    case review         // 复盘工作台
    case alert          // 预警面板
    case workspace      // 工作区模板
    case multichart     // 多图表
    case formulaEditor  // 公式编辑器
    case trading        // 模拟交易
    case sheet          // 通用 sheet（return/esc）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .global:        return "全局（任何窗口）"
        case .chart:         return "主图（K 线图表）"
        case .watchlist:     return "自选合约"
        case .journal:       return "交易日志"
        case .review:        return "复盘工作台"
        case .alert:         return "预警面板"
        case .workspace:     return "工作区模板"
        case .multichart:    return "多图表"
        case .formulaEditor: return "公式编辑器"
        case .trading:       return "模拟交易"
        case .sheet:         return "通用 Sheet（确认 / 取消）"
        }
    }
}

/// 单条快捷键记录
public struct ShortcutEntry: Sendable, Equatable {
    public let key: String          // "⌘N" / "⌘⇧D" / "⌘⌥M"
    public let description: String  // 中文功能说明
    public init(_ key: String, _ description: String) {
        self.key = key
        self.description = description
    }
}

/// 一组快捷键（同一 scope 下的若干分类小标题 · 与原 ChartScene 7 大类风格一致）
public struct ShortcutGroup: Sendable, Equatable {
    public let title: String          // 小标题（"周期切换" / "视口操作"）
    public let entries: [ShortcutEntry]
    public init(_ title: String, _ entries: [ShortcutEntry]) {
        self.title = title
        self.entries = entries
    }
}

/// 一个 scope 的全部快捷键（scope + 多个 group）
public struct ShortcutSection: Sendable, Equatable {
    public let scope: ShortcutWindowScope
    public let groups: [ShortcutGroup]
    public init(scope: ShortcutWindowScope, groups: [ShortcutGroup]) {
        self.scope = scope
        self.groups = groups
    }
}

/// 全工程快捷键速查
public enum GlobalShortcutsCatalog {

    /// 全部 sections（按 scope 顺序排列 · global 在最前）
    public static let sections: [ShortcutSection] = [
        // MARK: - global（任何窗口可触发 · 开窗 / 主题 / 帮助）
        ShortcutSection(scope: .global, groups: [
            ShortcutGroup("帮助", [
                ShortcutEntry("⌘⇧/", "全局快捷键速查（本浮窗）"),
            ]),
            ShortcutGroup("窗口管理", [
                ShortcutEntry("⌘N", "新建主图窗口"),
                ShortcutEntry("⌘L", "打开自选合约"),
                ShortcutEntry("⌘R", "打开复盘工作台"),
                ShortcutEntry("⌘B", "打开预警面板"),
                ShortcutEntry("⌘J", "打开交易日志"),
                ShortcutEntry("⌘K", "打开工作区模板"),
                ShortcutEntry("⌘T", "打开模拟交易"),
                ShortcutEntry("⌘⇧T", "打开模拟训练"),
            ]),
            ShortcutGroup("分析窗口（⌘⌥ 系列）", [
                ShortcutEntry("⌘⌥M", "多图表"),
                ShortcutEntry("⌘⌥S", "套利分析"),
                ShortcutEntry("⌘⌥O", "期权工作台"),
                ShortcutEntry("⌘⌥B", "板块联动"),
                ShortcutEntry("⌘⌥H", "行情热力图"),
                ShortcutEntry("⌘⌥P", "多空持仓"),
                ShortcutEntry("⌘⌥C", "关联性矩阵"),
                ShortcutEntry("⌘⌥N", "资金流向"),
                ShortcutEntry("⌘⌥X", "跨期套利"),
                ShortcutEntry("⌘⌥I", "品种深度分析"),
                ShortcutEntry("⌘⌥T", "时段对比"),
                ShortcutEntry("⌘⌥A", "异常品种监控"),
                ShortcutEntry("⌘⌥W", "价差套利 alert"),
                ShortcutEntry("⌘⌥K", "公式回测"),
                ShortcutEntry("⌘⌥F", "公式编辑器"),
            ]),
            ShortcutGroup("主题与导入", [
                ShortcutEntry("⌘⇧D", "切换主题（深色 / 浅色 · 全局生效）"),
                ShortcutEntry("⌘⇧I", "导入文华公式（.wh）"),
            ]),
        ]),

        // MARK: - chart（K 线图表 · ChartScene shortcutsHelpOverlay 完整迁移）
        ShortcutSection(scope: .chart, groups: [
            ShortcutGroup("周期切换", [
                ShortcutEntry("⌘1-6", "主图周期 1m/5m/15m/30m/1h/D"),
                ShortcutEntry("⌥1-9", "全 9 周期 1/3/5/15/30/60/4h/D/W"),
            ]),
            ShortcutGroup("视口操作", [
                ShortcutEntry("⌘= / ⌘-", "缩放 放大 / 缩小"),
                ShortcutEntry("⌘0", "重置缩放（最近 120 根）"),
                ShortcutEntry("← / →", "平移 5 根 K 线"),
                ShortcutEntry("⇧← / ⇧→", "平移 25 根 K 线"),
                ShortcutEntry("⌘End / ⌘→", "跳到最新 K 线"),
                ShortcutEntry("⌘⌥1-6", "时间范围预设 1D/1W/1M/3M/6M/1Y（v17.138）"),
            ]),
            ShortcutGroup("测距 / 标注", [
                ShortcutEntry("⌘⇧M", "测距三态 起 → 终 → 退出"),
                ShortcutEntry("⌘⇧X", "复制测距详情到剪贴板"),
                ShortcutEntry("⌘⇧W", "Swing High/Low 显隐"),
                ShortcutEntry("⌘⇧P", "形态识别 overlay 显隐（v17.164 头肩顶/底 + 双顶/底）"),
                ShortcutEntry("⌘⇧L", "形态识别清单 sheet（v17.165 当前 K 线全部检出形态）"),
                ShortcutEntry("⌘⇧S", "支撑阻力 overlay 显隐（v17.166 ZigZag pivot 聚类水平线）"),
                ShortcutEntry("⌘⇧Y", "多周期共振 overlay 显隐（v17.170 当前周期 → 高周期 MACD/EMA 金叉死叉）"),
            ]),
            ShortcutGroup("显隐切换", [
                ShortcutEntry("⌘.", "副图 显隐"),
                ShortcutEntry("⌘\\", "画线 overlay 显隐"),
                ShortcutEntry("⌘⇧H", "HUD 显隐"),
            ]),
            ShortcutGroup("截图", [
                ShortcutEntry("⌘P", "导出主图截图 PNG"),
                ShortcutEntry("⌘⇧P", "复制主图截图到剪贴板"),
            ]),
            ShortcutGroup("帮助", [
                ShortcutEntry("⌘/", "切换主图快捷键浮窗（细分版）"),
                ShortcutEntry("⌘⇧?", "切换主图快捷键浮窗（与本速查互补）"),
            ]),
        ]),

        // MARK: - watchlist（自选合约）
        ShortcutSection(scope: .watchlist, groups: [
            ShortcutGroup("通用", [
                ShortcutEntry("⌘W", "关闭窗口（macOS 系统级）"),
                ShortcutEntry("⌘F", "搜索过滤（如有 search 框）"),
                ShortcutEntry("Return", "确认（sheet 内）"),
                ShortcutEntry("Esc", "取消（sheet 内）"),
            ]),
        ]),

        // MARK: - formulaEditor（公式编辑器）
        ShortcutSection(scope: .formulaEditor, groups: [
            ShortcutGroup("编辑", [
                ShortcutEntry("⌘/", "注释 / 取消注释当前行（多行选区批量注释 · v15.22 batch15/23）"),
                ShortcutEntry("⌘S", "保存当前公式"),
                ShortcutEntry("⌘B", "构建（编译当前公式）"),
            ]),
        ]),

        // MARK: - sheet（通用 SwiftUI sheet 标准约定）
        ShortcutSection(scope: .sheet, groups: [
            ShortcutGroup("通用 sheet 行为", [
                ShortcutEntry("Return", "默认按钮（确认 / 提交）"),
                ShortcutEntry("Esc", "取消按钮（关闭 sheet）"),
            ]),
        ]),
    ]

    /// 按 scope 检索 section · 用于 sheet "当前窗口"过滤模式
    public static func section(for scope: ShortcutWindowScope) -> ShortcutSection? {
        sections.first { $0.scope == scope }
    }

    /// 全部快捷键条目数（用于单测覆盖度防回归）
    public static var totalEntries: Int {
        sections.reduce(0) { $0 + $1.groups.reduce(0) { $0 + $1.entries.count } }
    }
}
