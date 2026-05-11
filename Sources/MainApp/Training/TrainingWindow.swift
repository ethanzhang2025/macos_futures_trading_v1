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

    var body: some View {
        VStack(spacing: 0) {
            TrainingControlBar(viewModel: viewModel, engine: engine)
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 540, idealHeight: 680)
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
            ("HistoryPanel 同步显示", "statsCard 🔥 连训 chip 同 ControlBar"),
            ("月报 overview 章节 (v16.86/91)", "markdown 月报含 streak + 新纪录提示"),
        ]),
        ("📋 RulesPanel · JSON 导入/导出 (v16.99)", [
            ("⋯ Menu → 导出当前规则集为 JSON", "trader 分享 / 备份"),
            ("⋯ Menu → 导入规则集 JSON", "从文件加载 · 覆盖当前"),
            ("4 套模板 (v16.43)", "🎯 保守 / ⚡ 激进 / 📈 波段 / 🌱 极简"),
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
