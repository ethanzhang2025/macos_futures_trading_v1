// MainApp · Shell · v17.2 · 全局命令面板（⌘+K · Bloomberg "GO" 现代化版）
// 国内国外首家 · TradingView 仅 symbol 搜索 · 我们是全局 command palette
//
// 候选源：合约 mock list / PrimaryTab 切换 / Workspace 切换 / 新建 Pane

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellCommandPalette: View {
    @EnvironmentObject var shellVM: ShellViewModel
    /// v17.73 · 独立窗口快速打开（trader 不记 ⌘⌥X 快捷键 · ⌘K 搜功能名直接开）
    @Environment(\.openWindow) private var openWindow
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    filteredCommands.isEmpty
                        ? AnyView(emptyState)
                        : AnyView(commandList)
                }
            }
        }
        .frame(width: 640, height: 480)
        .background(.regularMaterial)
        .onAppear { queryFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索合约 / 功能 / Workspace…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($queryFocused)
                .onSubmit { executeFirst() }
            Button("关闭") { isPresented = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var commandList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredCommands.enumerated()), id: \.element.cmd.id) { _, item in
                commandRow(item.cmd, highlightRange: item.range)
            }
        }
        .padding(.vertical, 4)
    }

    private func commandRow(_ cmd: PaletteCommand, highlightRange: Range<String.Index>?) -> some View {
        Button {
            shellVM.recordPaletteCommandUsage(cmd.title)  // v17.29 · LRU 记录
            cmd.action()
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Text(cmd.emoji).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Self.highlightedTitle(cmd.title, range: highlightRange)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    if let subtitle = cmd.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(cmd.category.label)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(cmd.category.color.opacity(0.18))
                    .foregroundColor(cmd.category.color)
                    .cornerRadius(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { _ in }
    }

    /// v17.69 · matchedRange 内字符 bold + accent 色（无 range 时整段 primary）
    private static func highlightedTitle(_ title: String, range: Range<String.Index>?) -> Text {
        guard let range = range else { return Text(title) }
        let pre = String(title[title.startIndex..<range.lowerBound])
        let mid = String(title[range])
        let post = String(title[range.upperBound..<title.endIndex])
        return Text(pre)
            + Text(mid).bold().foregroundColor(.accentColor)
            + Text(post)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🔍").font(.system(size: 32))
            Text("无匹配结果")
                .font(.callout).foregroundColor(.secondary)
            Text("试试：合约代码 / 模块名 / Workspace 名")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private func executeFirst() {
        if let first = filteredCommands.first {
            shellVM.recordPaletteCommandUsage(first.cmd.title)  // v17.29 · LRU 记录
            first.cmd.action()
            isPresented = false
        }
    }

    // MARK: - 候选汇集

    private var allCommands: [PaletteCommand] {
        var list: [PaletteCommand] = []

        // 一级模块切换
        for tab in PrimaryTab.allCases {
            list.append(PaletteCommand(
                title: "切到 \(tab.displayName)",
                subtitle: "⌘\(tab.shortcutNumber)",
                emoji: tab.emoji,
                category: .module,
                action: {
                    if shellVM.primaryTab != tab {
                        shellVM.primaryTab = tab
                        shellVM.activateFirstWorkspaceOfPrimaryTab()
                    }
                }
            ))
        }

        // Workspace 切换
        for ws in shellVM.workspaces {
            list.append(PaletteCommand(
                title: ws.name,
                subtitle: "\(ws.primaryTab.displayName) · \(ws.paneLayout.displayName) · \(ws.panes.count) Pane",
                emoji: ws.primaryTab.emoji,
                category: .workspace,
                action: { shellVM.activate(ws.id) }
            ))
        }

        // 合约 mock list（v17.x 接 WatchlistStore）
        for sym in mockSymbols {
            list.append(PaletteCommand(
                title: sym.symbol,
                subtitle: sym.name,
                emoji: "📊",
                category: .symbol,
                action: {
                    // 把 symbol 设到当前 active Pane（首个 chart Pane）
                    if let ws = shellVM.activeWorkspace,
                       let chartPane = ws.panes.first(where: { $0.kind == .chart }) {
                        shellVM.setPaneSymbol(paneID: chartPane.id, symbol: sym.symbol)
                    }
                }
            ))
        }

        // 新建 Pane（按 kind）· v17.68 · 接通 ShellViewModel.addPaneToActiveWorkspace
        let popularKinds: [PaneKind] = [.chart, .spread, .option, .review, .training, .formulaEditor]
        for kind in popularKinds {
            list.append(PaletteCommand(
                title: "新建 \(kind.displayName)",
                subtitle: "添加为当前 Workspace 的新 Pane（布局已满会被忽略）",
                emoji: kind.emoji,
                category: .action,
                action: { shellVM.addPaneToActiveWorkspace(kind: kind) }
            ))
        }

        // v17.68 · Workspace 5 预设新建（接 v17.67 WorkspacePreset）
        for preset in WorkspacePreset.allCases {
            list.append(PaletteCommand(
                title: "新建预设：\(preset.displayName)",
                subtitle: preset.subtitle,
                emoji: preset.emoji,
                category: .action,
                action: { shellVM.newWorkspace(from: preset) }
            ))
        }
        list.append(PaletteCommand(
            title: "全部 Workspace 预设…",
            subtitle: "打开预设 picker sheet · 卡片视图浏览全部",
            emoji: "📋",
            category: .action,
            action: { shellVM.showPresetPickerSheet = true }
        ))

        // v17.68 · Workspace 复制 / 删除
        if let ws = shellVM.activeWorkspace {
            list.append(PaletteCommand(
                title: "复制当前 Workspace",
                subtitle: "\(ws.name) → \(ws.name) 副本",
                emoji: "📑",
                category: .action,
                action: { shellVM.duplicateWorkspace(ws.id) }
            ))
            if shellVM.workspaces.count > 1 {
                list.append(PaletteCommand(
                    title: "删除当前 Workspace",
                    subtitle: "\(ws.name) · 此操作不可撤销（至少保留 1 个）",
                    emoji: "🗑",
                    category: .action,
                    action: { shellVM.closeWorkspace(ws.id) }
                ))
            }
        }

        // v17.68 · Pane 布局切换（接 ShellViewModel.setPaneLayout · 6 预设 + 不含 custom）
        for paneLayout in PaneLayout.allCases where paneLayout != .custom {
            list.append(PaletteCommand(
                title: "切布局：\(paneLayout.displayName)",
                subtitle: "当前 Workspace 切到 \(paneLayout.paneCount) Pane（\(paneLayout.emoji)）",
                emoji: paneLayout.emoji,
                category: .action,
                action: { shellVM.setPaneLayout(paneLayout) }
            ))
        }

        // v17.68 · Pane 最大化 / 退出最大化（接 v17.5 toggleMaximize / exitMaximize）
        if shellVM.maximizedPaneID != nil {
            list.append(PaletteCommand(
                title: "退出 Pane 最大化",
                subtitle: "Esc · 恢复多 Pane 布局",
                emoji: "🔲",
                category: .action,
                action: { shellVM.exitMaximize() }
            ))
        } else if let firstPane = shellVM.activeWorkspace?.panes.first {
            list.append(PaletteCommand(
                title: "最大化第一个 Pane",
                subtitle: "\(firstPane.kind.emoji) \(firstPane.kind.displayName) · 双击 PaneHeader 同效",
                emoji: "🔳",
                category: .action,
                action: { shellVM.toggleMaximize(firstPane.id) }
            ))
        }

        // v17.68 · Inspector 切换
        list.append(PaletteCommand(
            title: shellVM.layout.inspectorVisible ? "隐藏右辅助 Inspector" : "显示右辅助 Inspector",
            subtitle: "⌘⌥I · 盘口 5 档 / 分时 mini / Tick 流 / 异动池",
            emoji: "🧭",
            category: .action,
            action: { shellVM.toggleInspector() }
        ))
        // Sidebar 自定义入口暂走右键菜单（@State 在 ShellSidebar 内 · 命令面板入口 v17.69+ 评估）

        // v17.68 · F 键全套（接 v17.57 + v17.61 已有方法）
        list.append(PaletteCommand(
            title: "F6 · 聚焦 Sidebar",
            subtitle: "光标移到左 Sidebar 搜索框",
            emoji: "🔍",
            category: .action,
            action: { shellVM.focusSidebar() }
        ))
        list.append(PaletteCommand(
            title: "F8 · 切换周期",
            subtitle: "当前 active Pane 周期循环（1m→5m→15m→…）",
            emoji: "⏱",
            category: .action,
            action: { shellVM.cyclePeriodOnActivePane() }
        ))
        list.append(PaletteCommand(
            title: "F10 · 合约资料",
            subtitle: "弹出当前 active Pane symbol 资料 sheet",
            emoji: "🪪",
            category: .action,
            action: { shellVM.openInstrumentInfo() }
        ))
        list.append(PaletteCommand(
            title: "F12 · 画线工具提示",
            subtitle: "Pane 内画线工具入口提示",
            emoji: "✏️",
            category: .action,
            action: { shellVM.hintDrawingTool() }
        ))
        list.append(PaletteCommand(
            title: "空格 · 快捷下单",
            subtitle: "Stage A 占位 · v2 接 SimulatedTradingEngine",
            emoji: "⌨️",
            category: .action,
            action: { shellVM.openQuickOrder() }
        ))

        // v17.73 · 独立窗口快速打开（trader 不记 ⌘⌥X 快捷键 · ⌘K 搜功能名直接开）
        let windowEntries: [(id: String, title: String, emoji: String, hint: String)] = [
            ("watchlist",          "打开 自选合约 窗口",     "⭐", "⌘⌥W · 独立窗口模式"),
            ("chart",              "打开 K 线图表 窗口",     "📊", "⌘N · 多图表对照"),
            ("review",             "打开 复盘工作台 窗口",   "📝", "⌘⌥R · 复盘工作台"),
            ("alert",              "打开 预警 窗口",         "🔔", "⌘⌥A · 价格 / 指标预警"),
            ("journal",            "打开 交易日志 窗口",     "📓", "⌘⌥J · 复盘日志"),
            ("trading",            "打开 模拟交易 窗口",     "💼", "⌘⌥T · Stage A 模拟"),
            ("training",           "打开 训练 窗口",         "🎯", "⌘⇧T · 训练模式"),
            ("multichart",         "打开 多图表 窗口",       "📊", "⌘⌥M · 4-Pane"),
            ("formulaEditor",      "打开 公式编辑器 窗口",   "🧮", "⌘⌥F · 麦语言"),
            ("spread",             "打开 跨期套利 窗口",     "💱", "⌘⌥S · 价差分析"),
            ("option",             "打开 期权工作台 窗口",   "📈", "⌘⌥O · 期权链"),
            ("sector",             "打开 板块联动 窗口",     "🗂", "⌘⌥B · 板块"),
            ("heatmap",            "打开 热力地图 窗口",     "🔥", "⌘⌥H · 板块热力"),
            ("position",           "打开 多空持仓 窗口",     "💼", "⌘⌥P · 持仓分析"),
            ("correlation",        "打开 相关性矩阵 窗口",   "🔗", "⌘⌥C · 相关性"),
            ("moneyflow",          "打开 资金流向 窗口",     "💧", "资金流"),
            ("calendarSpread",     "打开 日历套利 窗口",     "💱", "calendar spread"),
            ("instrumentDashboard","打开 品种深度 窗口",     "🧭", "instrument dashboard"),
            ("sessionCompare",     "打开 时段对比 窗口",     "⏱", "session compare"),
            ("anomalyMonitor",     "打开 异常监控 窗口",     "⚠️", "anomaly monitor"),
            ("spreadAlert",        "打开 价差告警 窗口",     "🔔", "spread alert"),
            ("workspace",          "打开 工作空间 窗口",     "🗂", "⌘⌥Y · workspace 管理"),
            ("backtest",           "打开 公式回测 窗口",     "🧪", "⌘⌥K · 回测"),
        ]
        for entry in windowEntries {
            list.append(PaletteCommand(
                title: entry.title,
                subtitle: entry.hint,
                emoji: entry.emoji,
                category: .action,
                action: { openWindow(id: entry.id) }
            ))
        }

        // v17.12 A2.1 · 主题切换
        let current = ChartThemeStore.load() ?? .dark
        let next: ChartTheme = (current == .dark) ? .light : .dark
        list.append(PaletteCommand(
            title: "切换到\(next.displayName)主题",
            subtitle: "当前：\(current.displayName) · 切换后全 Shell + 子窗口跟随",
            emoji: next == .dark ? "🌙" : "☀️",
            category: .action,
            action: { ChartThemeStore.save(next) }
        ))

        return list
    }

    /// v17.69 · 模糊匹配 + 排名 + 高亮 range
    /// 排序：score desc / title.count asc tiebreaker
    /// score: 100 exact / 90 prefix / 70 substring / 50 subsequence / 30 subtitle substring
    private var filteredCommands: [(cmd: PaletteCommand, range: Range<String.Index>?)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            let recents = shellVM.recentPaletteCommands.compactMap { title in
                allCommands.first { $0.title == title }
            }
            let recentTitles = Set(recents.map(\.title))
            let others = allCommands.filter { !recentTitles.contains($0.title) }
            return Array((recents + others).prefix(20)).map { ($0, nil) }
        }
        let matched: [(cmd: PaletteCommand, score: Int, range: Range<String.Index>?)] = allCommands.compactMap { cmd in
            guard let m = Self.matchScore(for: cmd, query: q) else { return nil }
            return (cmd, m.score, m.range)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.cmd.title.count < rhs.cmd.title.count
        }
        return matched.map { ($0.cmd, $0.range) }
    }

    /// v17.69 · 单个 command 的 match score + highlight range（仅连续匹配段 · subsequence 无 range）
    private static func matchScore(for cmd: PaletteCommand, query q: String) -> (score: Int, range: Range<String.Index>?)? {
        let title = cmd.title
        if let r = title.range(of: q, options: .caseInsensitive) {
            let isExact = (r.lowerBound == title.startIndex && r.upperBound == title.endIndex)
            let isPrefix = (r.lowerBound == title.startIndex)
            return (isExact ? 100 : (isPrefix ? 90 : 70), r)
        }
        if Self.isSubsequence(query: q.lowercased(), in: title.lowercased()) {
            return (50, nil)
        }
        if let sub = cmd.subtitle, sub.range(of: q, options: .caseInsensitive) != nil {
            return (30, nil)
        }
        return nil
    }

    /// query 字符按序在 title 中出现即匹配（中间可跳）· "nfd" 匹配 "**N**ew **F**older **D**ialog"
    private static func isSubsequence(query q: String, in lower: String) -> Bool {
        guard !q.isEmpty else { return true }
        var qi = q.startIndex
        for c in lower {
            if c == q[qi] {
                qi = q.index(after: qi)
                if qi == q.endIndex { return true }
            }
        }
        return false
    }
}

// MARK: - Palette command model

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let emoji: String
    let category: Category
    let action: () -> Void

    enum Category {
        case module, workspace, symbol, action

        var label: String {
            switch self {
            case .module:    return "模块"
            case .workspace: return "Workspace"
            case .symbol:    return "合约"
            case .action:    return "操作"
            }
        }

        var color: Color {
            switch self {
            case .module:    return .accentColor
            case .workspace: return .purple
            case .symbol:    return .orange
            case .action:    return .green
            }
        }
    }
}

// MARK: - Mock 合约（v17.x 接 WatchlistStore）

private struct SymbolItem { let symbol: String; let name: String }
private let mockSymbols: [SymbolItem] = [
    SymbolItem(symbol: "rb2510", name: "螺纹钢 主力"),
    SymbolItem(symbol: "i2510",  name: "铁矿石 主力"),
    SymbolItem(symbol: "IF2509", name: "沪深300 主力"),
    SymbolItem(symbol: "IC2509", name: "中证500 主力"),
    SymbolItem(symbol: "IH2509", name: "上证50 主力"),
    SymbolItem(symbol: "ag2510", name: "白银 主力"),
    SymbolItem(symbol: "au2510", name: "黄金 主力"),
    SymbolItem(symbol: "MA2510", name: "甲醇 主力"),
    SymbolItem(symbol: "TA2510", name: "PTA 主力"),
    SymbolItem(symbol: "p2509",  name: "棕榈油 主力"),
    SymbolItem(symbol: "y2509",  name: "豆油 主力"),
    SymbolItem(symbol: "m2509",  name: "豆粕 主力"),
    SymbolItem(symbol: "c2509",  name: "玉米 主力"),
    SymbolItem(symbol: "cu2510", name: "沪铜 主力"),
    SymbolItem(symbol: "al2510", name: "沪铝 主力"),
]

#endif
