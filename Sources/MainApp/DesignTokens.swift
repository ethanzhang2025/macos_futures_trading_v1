// MainApp · Design Tokens · v17.204 · 视觉升级 Day 1 地基
//
// 设计基调（v1 · 大众审美阶段 · 2026-05-14 用户拍板）：
// - **目标用户**：散户 / 个人 trader · 不是金融机构
// - **风格参考**：Discord / Notion / 现代消费金融 app · 不是 Bloomberg 信息墙
// - **核心特征**：清爽留白 + 大圆角 + 字号舒适 + 配色克制 + 少 chip 少 badge
// - **信息密度**：中（trader 看得清 · 又不让人窒息）· 不堆"专业感"
//
// v2 · 专业版预留（金融机构定制版 · 后续）：
// - Bloomberg 终端风 · 信息密度极高 · 字号 11pt mono 紧凑 · 配色工业感
// - 跟 v1 走两套 token namespace · 不冲突
// - 见底部 `enum BloombergTokens` 占位
//
// 设计目标（v1 · 大众审美）：
// - 解决「视觉差 / 凌乱 / 不专业」三痛
// - 一套 token 覆盖 5 大组件（Sidebar / PrimaryTabBar / PaneHeader / HUD / 底栏）
// - 不动 K 线 / Metal renderer / 涨跌色语义
//
// 包含 5 类 token：
// 1. Surface 3 层（base / elev1 / elev2）· 卡片层级感来源
// 2. Spacing 8pt grid（xs/sm/md/lg/xl/xxl）· v1 放大版（呼吸优先）
// 3. Radius（sm/md/lg）· v1 大圆角（亲和力）
// 4. Typography（title/body/mono/label/badge/hint）· v1 升档版（13/12pt baseline）
// 5. Status colors（accent/info/success/warning/danger/muted）· 与涨跌色独立
//
// 不做：
// - 不替换 ChartTheme · DesignTokens 是补充（spacing/radius/surface 是 ChartTheme 没有的）
// - 不抽 Shared module（Sidebar 等都在 MainApp · iPadApp 用再抽）
// - 不做用户自定义（v1 跟 ChartTheme dark/light 联动 · 不另开 token 偏好）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

/// 全局视觉 token namespace · 静态常量为主 · 复杂的（surface 跟主题）走 helper
enum DesignTokens {

    // MARK: - Spacing（v1 大众审美 · 呼吸优先 · 比 trader 工业风放大 50-100%）
    //
    // 对比：
    // - v1 大众版：xs=6 / sm=8 / md=12 / lg=16 / xl=20 / xxl=32（本表）
    // - v2 Bloomberg 版（占位）：xs=2 / sm=4 / md=6 / lg=8 / xl=12 / xxl=16（信息密度优先）
    enum Spacing {
        /// 2pt · 极小（chip 内部 / 微调）
        static let xxs: CGFloat = 2
        /// 6pt · 小（label-icon 间距）
        static let xs: CGFloat = 6
        /// 8pt · 行内组件间距（默认 HStack spacing）
        static let sm: CGFloat = 8
        /// 12pt · 默认 padding（行高 / 卡片内边距）
        static let md: CGFloat = 12
        /// 16pt · 中等（section 上下间距）
        static let lg: CGFloat = 16
        /// 20pt · 大（page-level padding · 主分组）
        static let xl: CGFloat = 20
        /// 32pt · 特大（窗口边距 · 顶层分隔）
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius（v1 大众审美 · 大圆角 · 亲和力优先）
    //
    // 对比：
    // - v1 大众版：xs=4 / sm=6 / md=8 / lg=12（圆润现代）
    // - v2 Bloomberg 版（占位）：xs=2 / sm=3 / md=4 / lg=6（更方正硬朗）
    enum Radius {
        /// 4pt · chip / badge / 标记（小元素）
        static let xs: CGFloat = 4
        /// 6pt · 小按钮 / tooltip
        static let sm: CGFloat = 6
        /// 8pt · 中等卡片（默认）
        static let md: CGFloat = 8
        /// 12pt · 大卡片 / 弹层 / sheet
        static let lg: CGFloat = 12
    }

    // MARK: - Typography（v1 大众审美 · 字号舒适 · 比 trader 工业风升 1-2pt）
    //
    // 对比：
    // - v1 大众版：title 14 / body 13 / mono 12 / badge 10（本表 · 易读）
    // - v2 Bloomberg 版（占位）：title 12 / body 11 / mono 11 / badge 9（紧凑信息墙）
    //
    // 命名约定：
    // - title / body / hint / label = 比例字体（中文 / 文字 / 提示）
    // - mono / monoBold / monoSm = 等宽字体（数字 · 价格 / 涨跌 / PnL）
    // - badge = 小 chip 用
    enum Typography {
        /// 14pt medium · section title / 主标签（"自选" "板块"）
        static let title = Font.system(size: 14, weight: .medium)
        /// 13pt regular · 正文（合约名 / 行内文字 · 非数字）
        static let body = Font.system(size: 13)
        /// 12pt mono · 数字主显示（价格 / 涨跌 / PnL）
        static let mono = Font.system(size: 12, design: .monospaced)
        /// 12pt mono semibold · 强调数字（hover / 高亮 / 总浮盈）
        static let monoBold = Font.system(size: 12, design: .monospaced).weight(.semibold)
        /// 11pt mono · 数字次显示（百分比 / 副数据 / 数量）
        static let monoSm = Font.system(size: 11, design: .monospaced)
        /// 11pt regular · 标签 / 次级文字（icon 旁说明）
        static let label = Font.system(size: 11)
        /// 10pt semibold · chip / badge 专用（不再 bold mono 工业风）
        static let badge = Font.system(size: 10, weight: .semibold)
        /// 10pt mono · 时间戳 / 备注（最弱）
        static let hint = Font.system(size: 10, design: .monospaced)
    }

    // MARK: - Color · Status（语义色 · 与涨跌色独立 · 不被 CandleColorMode 影响）
    //
    // 用途：badge / chip / icon · 跟"涨/跌"无关的语义
    // 涨跌色仍走 ChartTheme.candleUp/Down + chartProfit/LossColor mode-aware
    enum StatusColor {
        /// TradingView 招牌蓝 · accent / 主交互色（链接 / hover / 选中）
        static let accent = Color(red: 0.16, green: 0.38, blue: 1.00)   // #2962FF
        /// 信息蓝 · 普通信息提示（"真" chip 等）
        static let info = Color(red: 0.30, green: 0.65, blue: 1.00)     // #4DA6FF
        /// 成功绿 · 数据真实 / 系统正常（独立于涨跌绿）
        static let success = Color(red: 0.20, green: 0.78, blue: 0.45)  // #33C772
        /// 警告橙 · 异动 / 注意
        static let warning = Color(red: 1.00, green: 0.62, blue: 0.16)  // #FF9E29
        /// 危险红 · 预警触发 / 错误（独立于涨跌红）
        static let danger = Color(red: 1.00, green: 0.35, blue: 0.38)   // #FF5961
        /// 紫 · 训练 / 持仓 等中性强调
        static let purple = Color(red: 0.72, green: 0.50, blue: 1.00)   // #B780FF
        /// 弱化文字（次要 label / 时间戳）
        static let muted = Color.white.opacity(0.55)
        /// 极弱（占位 / 禁用）
        static let dimmed = Color.white.opacity(0.35)
    }

    // MARK: - Surface（3 层卡片背景 · 跟主题 dark/light 联动）
    //
    // 层级感来源：base → elev1 → elev2 亮度递增 · trader 一眼看出"卡片浮在背景上"
    // 深色：#11141A → #1A1E27 → #232834
    // 浅色：#F5F6F8 → #FFFFFF → #ECEEF1（轻微反色）
    enum Surface {
        /// 主背景（窗口底色 · 与 ChartTheme.background 对齐）
        static func base(_ theme: ChartTheme) -> Color {
            switch theme {
            case .dark:  return Color(red: 0.067, green: 0.078, blue: 0.102)  // #11141A
            case .light: return Color(red: 0.960, green: 0.965, blue: 0.972)  // #F5F6F8
            }
        }
        /// 一级卡片（section 容器 · 比 base 亮 5%）
        static func elev1(_ theme: ChartTheme) -> Color {
            switch theme {
            case .dark:  return Color(red: 0.102, green: 0.118, blue: 0.153)  // #1A1E27
            case .light: return Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
            }
        }
        /// 二级 hover / selected（行高亮 · 比 elev1 亮 5%）
        static func elev2(_ theme: ChartTheme) -> Color {
            switch theme {
            case .dark:  return Color(red: 0.137, green: 0.157, blue: 0.204)  // #232834
            case .light: return Color(red: 0.925, green: 0.932, blue: 0.945)  // #ECEEF1
            }
        }
        /// 分隔线（hairline · 弱化分组）
        static func divider(_ theme: ChartTheme) -> Color {
            switch theme {
            case .dark:  return Color.white.opacity(0.08)
            case .light: return Color.black.opacity(0.10)
            }
        }
    }

    // MARK: - 边框（hover 描边 / focus 描边）
    enum Border {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
    }
}

// MARK: - Chip 风格统一（v17.204 · Sidebar 3 种 chip 收一种）
//
// 历史：「真」「F6」「方向 多/空」3 种 chip 各写各 padding / radius / 字号
// 现在：统一 .chipStyle(color:) modifier · 9pt bold mono · 4h/2v padding · 3 radius

extension View {
    /// 标准 chip 风格（"F6"/"多"/"空"等小标记 · 10pt semibold · 4radius · 圆润现代）
    /// - Parameters:
    ///   - foreground: 文字色（默认白）
    ///   - background: 背景色（带 opacity）
    ///
    /// 注意（v1 大众审美原则）：
    /// - 少用 chip · 能用 icon 着色或文字色就不用 chip
    /// - chip 出现 = 该信息"必须标记出来"（如 F6 临时高亮、持仓方向）
    /// - 不堆"真/假"标签等元数据 chip · 大众审美不需要
    func chipStyle(
        foreground: Color = .white,
        background: Color
    ) -> some View {
        self
            .font(DesignTokens.Typography.badge)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(DesignTokens.Radius.xs)
    }
}

// MARK: - Section header 风格（v17.204 · Sidebar 6 section header 统一字号字色）
//
// 历史：6 section header 每个挑一种 system 色（橙/蓝/紫/红/橙/绿）· 像彩虹
// 现在：用 Label 自带 icon + 13pt medium · icon 色保留区分 · 文字 primary 不再 6 色

extension View {
    /// Sidebar section header 标准样式（13pt medium · 文字 primary）
    /// icon 色由调用方传入 Label(systemImage:) 决定 · 不强制
    func sidebarSectionHeader() -> some View {
        self.font(DesignTokens.Typography.title)
    }
}

// MARK: - Card 容器（v17.204 · 后续 PaneHeader / HUD 复用）
//
// 标准卡片：elev1 背景 + md radius + 内 padding md
// 用法：VStack { ... }.cardSurface(theme: chartTheme)

extension View {
    func cardSurface(theme: ChartTheme = .dark, padding: CGFloat = DesignTokens.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(DesignTokens.Surface.elev1(theme))
            .cornerRadius(DesignTokens.Radius.md)
    }
}

// MARK: - v2 Bloomberg 专业版 token 占位（金融机构定制版 · 后续）
//
// 现状：v1 大众审美阶段 · 上方 DesignTokens 全套已就位
// 未来：当用户要求出"专业机构定制版"时 · 启用本 namespace · 不动 v1
// 切换方式：由调用方决定（如 ChartSettingsStore 加 visualPreset enum {.casual, .pro}）
//
// 设计差异（vs v1 大众版）：
// - Typography：title 14→12 / body 13→11 / mono 12→11 / badge 10→9（信息密度优先）
// - Spacing：md 12→6 / lg 16→8（紧凑）
// - Radius：md 8→4 / lg 12→6（方正硬朗）
// - 多 chip 多 badge 多分隔线（专业感）
// - 配色更"工业感"（accent 走 Bloomberg 橙 #FF8800 而非现代蓝）
//
// 实装时机：用户主动提"出专业版" · 或 stage B 机构客户接入 · 现在仅占位

enum BloombergTokens {
    enum Spacing {
        static let xxs: CGFloat = 1
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
    }
    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 3
        static let md: CGFloat = 4
        static let lg: CGFloat = 6
    }
    enum Typography {
        static let title = Font.system(size: 12, weight: .semibold, design: .monospaced)
        static let body = Font.system(size: 11)
        static let mono = Font.system(size: 11, design: .monospaced)
        static let monoBold = Font.system(size: 11, design: .monospaced).weight(.bold)
        static let monoSm = Font.system(size: 10, design: .monospaced)
        static let label = Font.system(size: 10)
        static let badge = Font.system(size: 9, weight: .bold, design: .monospaced)
        static let hint = Font.system(size: 9, design: .monospaced)
    }
    enum StatusColor {
        /// Bloomberg 招牌橙
        static let accent = Color(red: 1.00, green: 0.53, blue: 0.00)   // #FF8800
        // 其余复用 DesignTokens.StatusColor
    }
}

#endif
