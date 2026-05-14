// MainApp · WP-54 模拟训练独立窗口（v15.23 batch14 · M5 节点 UI 闭环）
//
// 入口：⌘⇧T · 工具菜单"模拟训练"
//
// 布局：
// - 顶部：TrainingControlBar（开始/结束训练 · 计时 · 违规计数）
// - 下方：3 Tab
//   · 规则（TrainingRulesPanel · 5 类纪律 CRUD + 推荐导入）
//   · 实时（TrainingViolationFeed · 当前 session live violations）
//   · 历史（TrainingHistoryPanel · sessions + stats + 等级分布）
// - 评分 sheet：endSession 后自动弹（来自 viewModel.lastFinishedSession）
//
// 引擎集成：
// - 订阅 engine.observe() · 过滤 .disciplineViolation → viewModel.pushLiveViolation
// - startSession 时把 enabledRules push 到 engine.setDisciplineRules
// - endSession 时取 engine.currentAccount + allTrades 作为 session 数据

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import AppKit
import Shared
import TradingCore

private enum TrainingTab: String, CaseIterable, Identifiable {
    case rules = "规则"
    case live  = "实时"
    case history = "历史"
    var id: String { rawValue }
    var displayName: String { L(rawValue) }
}

struct TrainingWindow: View {

    @StateObject private var viewModel = TrainingViewModel()
    @State private var tab: TrainingTab = .rules
    @State private var observeTask: Task<Void, Never>? = nil
    /// v15.23 batch63 · 帮助面板（⌘⇧? · 三大新窗口 UX 一致）
    @State private var showHelpSheet: Bool = false

    @Environment(\.simulatedTradingEngine) private var engine: SimulatedTradingEngine?
    /// v17.6 · Shell 嵌入模式（TrainingWindow 已是 panel 风 · 无冗余 toolbar 需隐藏）
    @Environment(\.isHostedInShell) private var isHostedInShell

    var body: some View {
        VStack(spacing: 0) {
            TrainingControlBar(viewModel: viewModel, engine: engine)
            Divider()
            tabBar
            Divider()
            tabContent
        }
        // v17.207 · Shell 嵌入时移除 min 约束（避免撑大 Pane 挤出 PrimaryTabBar）
        .frame(
            minWidth: isHostedInShell ? 0 : 720,
            idealWidth: 880,
            minHeight: isHostedInShell ? 0 : 540,
            idealHeight: 680
        )
        .task {
            startObserving()
        }
        .onDisappear {
            observeTask?.cancel()
            observeTask = nil
        }
        .sheet(item: scoreSheetBinding) { wrapper in
            TrainingScoreSheet(session: wrapper.session,
                               score: wrapper.score,
                               onDismiss: { viewModel.dismissLastFinishedSheet() },
                               onRetrain: { pattern in
                                   viewModel.pendingRetrainPattern = pattern
                               },
                               comparison: viewModel.log.patternComparison(for: wrapper.session.id),
                               weakestPattern: viewModel.log.weakestPattern())
        }
        .sheet(isPresented: $showHelpSheet) {
            helpSheet
        }
        // v16.46 · history panel mostViolatedRules chip 点击 → 切到 rules tab
        .onChange(of: viewModel.pendingJumpToRulesTab) { newVal in
            if newVal {
                tab = .rules
                DispatchQueue.main.async { viewModel.pendingJumpToRulesTab = false }
            }
        }
        // v16.58 · 训练结束 sheet 关闭后自动切 history tab（HistoryPanel 接力高亮 + scroll）
        .onChange(of: viewModel.recentlyAddedSessionID) { newID in
            if newID != nil { tab = .history }
        }
        // v16.101 · ControlBar streak chip / 7 天 mini bar 点击 → 跳 history tab
        .onChange(of: viewModel.pendingJumpToHistoryTab) { newVal in
            if newVal {
                tab = .history
                DispatchQueue.main.async { viewModel.pendingJumpToHistoryTab = false }
            }
        }
        .background(
            Group {
                Button("") { showHelpSheet = true }
                    .keyboardShortcut("?", modifiers: [.command, .shift])
                    .opacity(0)
                // v15.23 batch151 · ⌘1/⌘2/⌘3 切 tab
                Button("") { tab = .rules }
                    .keyboardShortcut("1", modifiers: [.command])
                    .opacity(0)
                Button("") { tab = .live }
                    .keyboardShortcut("2", modifiers: [.command])
                    .opacity(0)
                Button("") { tab = .history }
                    .keyboardShortcut("3", modifiers: [.command])
                    .opacity(0)
                // v15.23 batch200 · ⌘E 月报 / ⌘⌥E 周报快捷键（仅 history tab · 复制到剪贴板）
                Button("") {
                    if tab == .history {
                        copyTrainingReport(weekly: false)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .opacity(0)
                Button("") {
                    if tab == .history {
                        copyTrainingReport(weekly: true)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .opacity(0)
            }
        )
    }

    /// v15.23 batch200 · 训练月报 / 周报复制到剪贴板（⌘E / ⌘⌥E · 与 ReviewWindow 模式一致）
    private func copyTrainingReport(weekly: Bool) {
        let md = weekly
            ? TrainingMarkdownReport.generateWeekly(viewModel.log)
            : TrainingMarkdownReport.generate(viewModel.log)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        Toast.info(weekly ? "已复制训练周报" : "已复制训练月报", "\(md.count) 字 · 直接粘贴")
    }

    // MARK: - v15.23 batch63 · 帮助面板

    private static let helpGroups: [(String, [(String, String)])] = [
        ("⏱ Session 控制", [
            ("⌘⇧S", "开始训练（弹 sheet · 选场景 + 设资金）"),
            ("⌘⇧E", "结束训练 + 评分（active 时）"),
            ("Esc", "取消开始 sheet（在 sheet 中按）"),
            ("⌘1 / ⌘2 / ⌘3", "切 Tab（规则 / 实时 / 历史 · v15.23 batch151）"),
        ]),
        ("📋 规则 Tab（7+ 操作）", [
            ("加号按钮", "添加新规则（5 类纪律 · 阈值 + 备注）"),
            ("⋯ 菜单 → 一键导入推荐", "trader 首次启用 · 5 条推荐配置"),
            ("⋯ 菜单 → 清空所有", "重新开始"),
            ("Toggle 开关", "启用 / 停用单条规则（不删）"),
            ("✎ 编辑按钮 / 右键编辑", "改阈值 / 备注"),
            ("右键 → 启用/停用", "快速 toggle"),
            ("右键 → 删除", "永久移除"),
        ]),
        ("⚡ 实时 Tab", [
            ("session active", "顶部计时 mm:ss + 违规/警告计数"),
            ("严重度颜色", "🔴 error / 🟡 warning + 时间戳"),
            ("清空 feed 按钮", "仅清当前显示 · 不影响 session 评分"),
        ]),
        ("📚 历史 Tab", [
            ("等级分布横条", "5 段 S/A/B/C/D · 宽度按 session 数"),
            ("默认 50 列表", "点击行 → 弹评分 sheet 回看（v16.55 加载更多 +50 / 全部展开）"),
            ("右键 → 删除", "5s 内可⌘Z 撤销（v16.64 误删保护 banner）"),
            ("清空全部", "永久删除所有历史（带确认）"),
            ("⌘E (batch200)", "复制训练月报 markdown 到剪贴板（仅 history tab）"),
            ("⌘⌥E (batch200)", "复制训练周报（最近 7 天 · 与 ReviewWindow 周报对齐）"),
            ("⌘⌥K (v16.48)", "直接启动历史最弱形态训练"),
            ("📛 累积违规 chip (v16.46)", "点击跳 RulesPanel 调阈值"),
            ("🔬 五维 chip (v16.62)", "全部 v2 评分 session 5 维平均 · 最弱橙色"),
        ]),
        ("🎯 评分系统", [
            ("总分 0-100", "盈亏 50 + 纪律 50"),
            ("等级阶梯", "S(≥90) / A(≥80) / B(≥70) / C(≥60) / D(<60)"),
            ("盈亏子分", ">5%=50 / >2%=40 / >0=30 / =0=20 / >-2%=10 / <-2%=0"),
            ("纪律子分", "50 - error×10 - warning×3（clamp 0-50）"),
            ("5 维 hover 公式 (v16.51)", "ScoreSheet 五维主分 hover 显示计算公式"),
            ("5 维 ↑↓ drilldown (v16.65/85)", "ScoreSheet 5 维主分点击/键盘展开本次具体数据 + actionFeedback 提示"),
            ("⌘⌥C 复制摘要 (v16.50)", "1 行 emoji 摘要分享到 IM"),
            ("⌘⌥R 雷达图 PNG (v16.87)", "ScoreSheet 5 维雷达图独立导出 · 朋友圈分享"),
            ("ESC 关闭 sheet (v16.82)", "替代 ⏎ 关闭按钮"),
        ]),
        ("🔥 训练习惯（streak 体系 v16.79-91）", [
            ("ControlBar 连训 chip", "🔥 (≥2) → 🔥🔥 (≥7) → 🚀 (≥14) → 🏆 (≥30) → 🎉 新纪录"),
            ("最近 7 天 mini bar (v16.76)", "类 GitHub contributions · idle 状态可视化"),
            ("personal best (v16.89)", "当前 vs 历史最长 streak · 超越自我鼓励"),
            ("点击跳 history (v16.101)", "ControlBar streak chip / 7 天 bar 点击切 history tab"),
            ("今日 vs 昨日 (v16.104)", "ControlBar idle 短时反馈对比"),
            ("HistoryPanel 同步显示", "statsCard 🔥 连训 + ⏱ 累计时长 + milestone"),
            ("累计时长 milestone (v16.122)", "⏱ → 🎯 10h → 🚀 50h → 🏆 100h → 👑 500h → 🌟 1000h"),
            ("月报 overview 章节 (v16.86/91/123)", "markdown 月报含 streak + 累计时长 + milestone"),
            ("月报时长分布 (v16.118)", "短/中/长 3 段 + 建议"),
        ]),
        ("📋 RulesPanel · JSON / Markdown 导入导出 (v16.99/106/121)", [
            ("⋯ Menu → 复制 JSON 到剪贴板", "v16.106 IM 即时分享"),
            ("⋯ Menu → 复制 markdown 表格", "v16.121 笔记/wiki/邮件可读"),
            ("⋯ Menu → 导出 JSON 为文件", "v16.99 团队分享 / 备份"),
            ("⋯ Menu → 粘贴/文件导入", "v16.99/106 · v16.117 覆盖确认"),
            ("4 套模板 (v16.43)", "🎯 保守 / ⚡ 激进 / 📈 波段 / 🌱 极简"),
        ]),
        ("🏆 历史 Panel polish (v16.55-138)", [
            ("增量分页 (v16.55)", "默认 50 + 加载更多 +50 + 全部展开"),
            ("删除 ⌘Z undo (v16.64)", "5s 内可撤销 banner"),
            ("月度 vs 上月对比 (v16.67)", "weekly + monthly 长期反馈"),
            ("⚠️ 弱项加练 / 🏆 强项展示 (v16.19/114)", "≥3 次 + 均分 <70 弱 / ≥80 强 · 点击过滤"),
            ("📛 累积违规 chip (v16.45/46/135)", "顶 3 跳 RulesPanel · tooltip 含最近 5 session"),
            ("🔬 5 维平均 chip (v16.62/73/116/133/134)", "spread/min/max/spread 警示 · ≥80 ✨ / ≥90 🌟"),
            ("再练同形态 contextMenu (v16.112)", "右键一键重练"),
            ("复制 emoji 摘要 (v16.128)", "session 右键 IM 一行分享"),
            ("CSV filter 后子集 (v16.72)", "trader 月度/形态筛选后导出"),
            ("5 维 markdown 复制 (v16.138)", "导出 Menu IM 分享 trader 倾向"),
            ("weekly goal 冲刺鼓励 (v16.115)", "🎯 差 1 次 / ✓🎯🏆 超额分级"),
            ("header streak hint (v16.127)", "第一眼看 🔥 连训 X 天"),
            ("累计时长 milestone (v16.122)", "⏱→🎯→🚀→🏆→👑→🌟"),
        ]),
        ("📋 RulesPanel polish (v16.130-136)", [
            ("每条规则 ⚠️ 违规 badge (v16.130)", "0 不显示 · 1 灰 · 2-4 橙 · 5+ 红"),
            ("badge tooltip 最近 session (v16.136)", "hover 看哪些 session 触发"),
            ("Markdown 表格导出 (v16.121)", "可读性优先 vs JSON · 笔记 wiki 友好"),
            ("覆盖确认 dialog (v16.117)", "import 防误覆盖现有规则"),
        ]),
        ("🚀 ControlBar idle 信息密度 (v16.76-204)", [
            ("today vs yesterday (v16.104)", "短时对比 · ↑/↓/= 三态 · v16.151 点击跳 history today filter"),
            ("🔥 streak chip (v16.79/83/89/101/139)", "milestone 4 级 · personal best · 点击跳 history · 接近升级鼓励"),
            ("7 天 mini bar (v16.76/101)", "类 GitHub · 点击跳 history"),
            ("上次训练距今 (v16.132)", "刚刚 / N 分钟前 / N 小时前 / N 天前 · v16.159 > 24h 🔔 > 72h ⏰ 警示色"),
            ("⚙️ 规则 chip 跳 RulesPanel (v16.177)", "点击直跳 · 与 streak/today 同模式"),
            ("启用 X/Y 条规则 (v16.166)", "显示启用占比 · 全部启用时简化文案"),
            ("启用率 mini progress (v16.194/204)", "ProgressView 36×4pt · tooltip X 启用 / Y 禁用"),
        ]),
        ("📊 ScoreSheet 改进 plan + 快捷键 (v16.147-178)", [
            ("5 步改进 plan (v16.147)", "5 维×5 步 = 25 句具体行动 · 复用月报"),
            ("智能默认展开 (v16.156)", "弱项 < 70 自动展 · 强项保持折叠"),
            ("emoji 序号 1️⃣-5️⃣ (v16.162)", "视觉强化 · IM 复制也带 emoji"),
            ("⌘⌥P 复制 plan (v16.175)", "快捷键 · 与 contextMenu 互补"),
            ("⌘C 复制 drilldown (v16.207)", "展开维度时 · 复制本维度详情"),
            ("数字键 1-5 直跳 (v16.168)", "drilldown 跳维度 · 与 ↑↓ wraparound 互补"),
            ("行号 chip (v16.197)", "row 左侧 1-5 · 与数字键配套"),
            ("(N/5) 位置 chip (v16.178)", "header 常驻 · 与 v16.85 flash 互补"),
            ("展开行蓝底高亮 (v16.200)", "当前展开维度 · 整数节点纪念"),
            ("⌨️ 1-5 / ↑↓ / ⌘⌥P 提示 (v16.184)", "header 一眼看键盘控制"),
            ("↑↓ wraparound (v16.186)", "5 → 1 / 1 → 5 循环切 · 不再越界关闭"),
            ("公式 hint 右键复制 (v16.163)", "5 维公式 hover 即学 · 右键保存"),
            ("雷达 / 截图 双导出 (v16.103/120)", "Menu 复制剪贴板 / 保存文件"),
        ]),
        ("📚 月报增强（v16.118-206）21+ 章节", [
            ("目录 TOC (v16.169/186/189/193/196)", "16 锚点 · markdown 渲染器自动跳转"),
            ("改进 plan 章节 (v16.153)", "复用 v16.147 · 最弱维度 5 步行动"),
            ("本月最强 (v16.161) / 最弱 (v16.165)", "对比学习 · 找差异沉淀成功模式"),
            ("单笔盈利冠军 (v16.172)", "pnl% 最大 · 与 score 最大互补"),
            ("最常违反规则 Top 3 (v16.188)", "🥇🥈🥉 + 复盘建议"),
            ("时长分布章节 (v16.118/144)", "短 / 中 / 长 3 段 + 智能建议"),
            ("30 天 emoji 日历 (v16.164)", "GitHub 风 · ⬜🟦🟩🟧🟥 5 级"),
            ("14 天每日均分 sparkline (v16.191)", "▁▃▅▇█ + · 无训练 · 与 30 天次数互补"),
            ("每周分布 (v16.170)", "周一-周日 + 🔥 最活跃日"),
            ("最佳训练时段 (v16.185)", "凌晨/上午/下午/夜晚 4 桶 + ⭐"),
            ("总分 sparkline (v16.176)", "最近 20 次 ▁▃▅▇█ + 趋势"),
            ("本月 vs 上月 (v16.183)", "次数 + 总分 + 5 维 delta"),
            ("本月 vs 全期 (v16.195)", "🚀📈📉⚠️ 4 阶梯趋势"),
            ("最近训练 5 维 dots + rank (v16.198/203)", "🥇🥈🥉 + 🟢🔵🟠🔴 dots"),
            ("形态分布 rank (v16.206)", "按次数 desc + 🥇🥈🥉"),
            ("footer 数据来源 (v16.180)", "本地不上云 + v1/v2 评分说明"),
        ]),
        ("📜 HistoryPanel polish (v16.147-209)", [
            ("月度分组 separator (v16.148)", "📅 2026 年 5 月 · N 次 · 仅 dateDesc"),
            ("月度 separator 复制摘要 (v16.202)", "右键 → 复制本月 markdown 摘要"),
            ("mini 5 维 dots (v16.150)", "5 圆点 · tooltip 详情 · 老 log 跳过"),
            ("累计时长 chip 跳本月 (v16.157)", "点击 filter month"),
            ("累计时长 tooltip 月分布 (v16.187/199)", "最近 3 月时长 + 本月 vs 上月 ↑↓"),
            ("weekly 进度跳本周 (v16.167)", "点击 filter week"),
            ("session contextMenu 雷达 PNG (v16.155)", "不必开 sheet · 直接导出"),
            ("session contextMenu filter 同形态 (v16.208)", "右键即过滤 · 与再练同形态互补"),
            ("grade emoji tooltip (v16.179/209)", "总分 + 5 维 + violations + vs 本月均"),
            ("弱/强项 chip 复制 markdown (v16.190)", "右键复制弱项/强项详情 + 最近 3 次"),
            ("FiveDimRadarChart 抽离 (v16.155)", "ScoreSheet + HistoryPanel 共享 view"),
        ]),
        ("🔍 ReviewWindow zoomedCard (v16.149)", [
            ("⌘⇧C 复制单图 markdown", "含 base64 PNG · 邮件/IM 可见图"),
            ("⌘S 导出 PNG", "全屏视图保存为文件"),
            ("← / → 切前后图", "循环边界 · v15.21 既有"),
        ]),
    ]

    @ViewBuilder
    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("⌨️ 模拟训练全功能").font(.title2).bold()
                Spacer()
                Button("关闭") { showHelpSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.helpGroups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.0).font(.headline)
                            ForEach(group.1, id: \.0) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(item.0)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.accentColor)
                                        .frame(width: 180, alignment: .leading)
                                    Text(item.1).font(.system(size: 12))
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 540, idealWidth: 640, minHeight: 480, idealHeight: 600)
    }

    // MARK: - Tab 切换栏

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TrainingTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 6) {
                        Text(emojiFor(t))
                        Text(t.displayName)
                            .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                        if t == .live, !viewModel.liveViolations.isEmpty {
                            Text("\(viewModel.liveViolations.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.red))
                                .foregroundColor(.white)
                        }
                        if t == .history, viewModel.log.sessionCount > 0 {
                            Text("\(viewModel.log.sessionCount)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.3)))
                                .foregroundColor(.primary)
                        }
                        // v15.23 batch151 · 规则数 badge（已配置纪律数）
                        if t == .rules, viewModel.book.rules.count > 0 {
                            Text("\(viewModel.book.rules.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.7)))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(tab == t ? Color.accentColor.opacity(0.18) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .rules:   TrainingRulesPanel(viewModel: viewModel)
        case .live:    TrainingViolationFeed(viewModel: viewModel)
        case .history: TrainingHistoryPanel(viewModel: viewModel)
        }
    }

    // MARK: - Engine 订阅

    private func startObserving() {
        guard let engine, observeTask == nil else { return }
        observeTask = Task { @MainActor in
            for await event in await engine.observe() {
                if case .disciplineViolation(let v) = event {
                    viewModel.pushLiveViolation(v)
                }
            }
        }
    }

    // MARK: - Sheet binding

    private struct ScoreSheetData: Identifiable {
        let id: UUID
        let session: TrainingSession
        let score: TrainingScore
    }

    private var scoreSheetBinding: Binding<ScoreSheetData?> {
        Binding(
            get: {
                guard let s = viewModel.lastFinishedSession,
                      let sc = viewModel.lastFinishedScore else { return nil }
                return ScoreSheetData(id: s.id, session: s, score: sc)
            },
            set: { newValue in
                if newValue == nil { viewModel.dismissLastFinishedSheet() }
            }
        )
    }

    private func emojiFor(_ t: TrainingTab) -> String {
        switch t {
        case .rules:   return "📋"
        case .live:    return "⚡"
        case .history: return "📚"
        }
    }
}

#endif
