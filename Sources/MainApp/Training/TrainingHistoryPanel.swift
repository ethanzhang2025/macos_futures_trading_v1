// MainApp · WP-54 模拟训练 · 历史 Panel + 统计（v15.23 batch13）
//
// 职责：
// - 上方统计卡：sessionCount / averageScore / bestScore + 等级分布横条
// - 中部最近 50 次 session 列表（日期 / 场景 / grade / total / pnl%）
// - 点击行 → 弹历史评分 sheet 复用 TrainingScoreSheet
// - 顶部清空全部按钮（带确认）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import TradingCore

struct TrainingHistoryPanel: View {

    @ObservedObject var viewModel: TrainingViewModel
    @State private var selectedSessionID: TrainingSession.ID? = nil
    @State private var showClearConfirm: Bool = false
    /// v15.23 batch144 · 本周训练目标（次数 · 默认 5）· 持久化
    @AppStorage("viewState.v1.training.weeklyGoal") private var weeklyGoal: Int = 5
    /// v15.23 batch122 · 形态筛选（nil = 全部 · 选中后只显示该形态训练）
    @State private var filterPattern: TrainingScenarioPattern? = nil
    /// v15.23 batch130 · 时间段筛选（默认全部 · 与形态 filter 互补 · 同时 AND）
    @State private var filterPeriod: PeriodFilter = .all
    /// v15.23 batch136 · 排序键（默认日期降序 · 与原行为一致）
    @State private var sortKey: SortKey = .dateDesc
    /// v16.26 · 场景名搜索（与形态/时段 filter 同时 AND · 大小写不敏感）
    @State private var searchText: String = ""
    /// v16.55 · 增量分页 limit · 默认 50 · "加载更多" 每次 +50 · 切 filter/sort/search 自动 reset
    @State private var visibleLimit: Int = 50
    private let pageSize: Int = 50
    /// v16.58 · 高亮新加 session（dismiss sheet 后 5s · 与 viewModel.recentlyAddedSessionID 同步）
    @State private var highlightedSessionID: UUID? = nil
    @State private var highlightClearTask: Task<Void, Never>? = nil
    /// v16.64 · 删除 session 5s undo · banner 显示 · trader 误删保护
    @State private var pendingUndoSession: TrainingSession? = nil
    @State private var undoClearTask: Task<Void, Never>? = nil

    /// v15.23 batch136 · 排序枚举
    enum SortKey: String, CaseIterable {
        case dateDesc = "日期 ↓"
        case scoreDesc = "总分 ↓"
        case scoreAsc = "总分 ↑"
        case pnlDesc = "盈亏 ↓"
        case pnlAsc = "盈亏 ↑"

        var icon: String {
            switch self {
            case .dateDesc: return "clock"
            case .scoreDesc, .scoreAsc: return "star"
            case .pnlDesc, .pnlAsc: return "dollarsign.circle"
            }
        }
    }

    /// v15.23 batch130 · 时间段过滤枚举
    enum PeriodFilter: String, CaseIterable, Hashable {
        case all = "全部"
        case today = "今天"
        case week = "本周"
        case month = "本月"
        case year = "本年"

        /// 起始时间戳（all 返回 nil = 不过滤）
        var cutoff: Date? {
            let cal = Calendar(identifier: .gregorian)
            switch self {
            case .all:   return nil
            case .today: return cal.startOfDay(for: Date())
            case .week:  return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .month, value: -1, to: Date())
            case .year:  return cal.date(byAdding: .year, value: -1, to: Date())
            }
        }

        var icon: String {
            switch self {
            case .all:   return "infinity"
            case .today: return "sun.max"
            case .week:  return "calendar.badge.clock"
            case .month: return "calendar"
            case .year:  return "calendar.circle"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // v16.48 · ⌘⌥K 直接启动最弱形态训练（与 v16.31 ScoreSheet 同设计 · 跨 panel 快捷键一致）
            .background(
                Button("") {
                    if let weakest = viewModel.log.weakestPattern() {
                        viewModel.pendingRetrainPattern = weakest
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .opacity(0)
            )
            // v16.64 · 删除 session undo banner（5s 自动清 · trader 误删保护）
            if let s = pendingUndoSession {
                undoBanner(for: s)
            }
            if viewModel.log.sessions.isEmpty {
                emptyState
            } else {
                statsCard
                Divider()
                sessionList
            }
        }
        .sheet(item: selectedSessionBinding) { session in
            if let score = viewModel.log.score(for: session.id) {
                TrainingScoreSheet(session: session,
                                   score: score,
                                   onDismiss: { selectedSessionID = nil },
                                   onRetrain: { pattern in
                                       viewModel.pendingRetrainPattern = pattern
                                   },
                                   comparison: viewModel.log.patternComparison(for: session.id),
                                   weakestPattern: viewModel.log.weakestPattern())
            }
        }
        .alert("清空全部历史？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { viewModel.log.clear() }
        } message: {
            Text("将永久删除 \(viewModel.log.sessionCount) 次训练记录与评分 · 不可恢复")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("📚 训练历史")
                .font(.headline)
            Text("\(viewModel.log.sessionCount) 次")
                .font(.caption)
                .foregroundColor(.secondary)
            // v16.127 · header 加 streak hint（trader 第一眼看连训习惯）· ≥ 2 才显示
            let dayStreak = viewModel.log.consecutiveTrainingDays()
            if dayStreak >= 2 {
                Text("· 🔥 连训 \(dayStreak) 天")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.red)
            }
            Spacer()
            // v15.23 batch126 · 月报导出（剪贴板 / .md 文件 · 只在有 session 时显示）
            // v15.23 batch197 · 加周报子菜单（与 ReviewWindow 周报对齐）
            if !viewModel.log.sessions.isEmpty {
                Menu {
                    Section("月报（应用 filter）") {
                        Button {
                            copyReportToPasteboard()
                        } label: {
                            Label("复制到剪贴板", systemImage: "doc.on.doc")
                        }
                        Button {
                            saveReportToFile()
                        } label: {
                            Label("保存为 .md 文件", systemImage: "square.and.arrow.down")
                        }
                    }
                    Section("周报（最近 7 天 · v15.23 batch197）") {
                        Button {
                            copyWeeklyReportToPasteboard()
                        } label: {
                            Label("复制周报到剪贴板", systemImage: "doc.on.doc")
                        }
                        Button {
                            saveWeeklyReportToFile()
                        } label: {
                            Label("保存周报为 .md 文件", systemImage: "square.and.arrow.down")
                        }
                    }
                    Section("📊 5 维平均（v16.138 · IM 简短分享）") {
                        Button {
                            copyFiveDimMarkdownToPasteboard()
                        } label: {
                            Label("复制 5 维平均 markdown", systemImage: "tablecells")
                        }
                        .tooltip("仅本 panel 的 5 维平均表 · IM 一键分享 trader 倾向")
                    }
                    Section("CSV 数据（v16.20/v16.24 · 离线分析 + 跨设备同步）") {
                        Button {
                            saveCSVToFile(filtered: false)
                        } label: {
                            Label("导出训练历史 CSV（全部）", systemImage: "tablecells")
                        }
                        // v16.72 · 加 filter 后子集导出（trader 月度/形态筛选后只导出可见子集）
                        if filterPattern != nil || filterPeriod != .all || !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                saveCSVToFile(filtered: true)
                            } label: {
                                Label("导出筛选后子集 CSV", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        }
                        Button {
                            importCSVFromFile()
                        } label: {
                            Label("导入训练历史 CSV", systemImage: "square.and.arrow.down.on.square")
                        }
                    }
                } label: {
                    Label("导出报告", systemImage: "square.and.arrow.up")
                }
                .tooltip("生成 markdown 月报 / 周报 / CSV 数据（trader 双节奏复盘 + 离线分析）")
            }
            // v15.23 batch130 · 时间段筛选 Menu（只在有 session 时显示）
            if !viewModel.log.sessions.isEmpty {
                Menu {
                    ForEach(PeriodFilter.allCases, id: \.self) { p in
                        let isOn = filterPeriod == p
                        Button("\(isOn ? "✓ " : "")\(p.rawValue)") { filterPeriod = p }
                    }
                } label: {
                    Label(filterPeriod.rawValue, systemImage: filterPeriod.icon)
                }
                .tooltip("按时间段筛选历史训练（与形态筛选互补 · 同时 AND）")
                // v15.23 batch136 · 排序 Menu
                Menu {
                    ForEach(SortKey.allCases, id: \.self) { k in
                        let isOn = sortKey == k
                        Button("\(isOn ? "✓ " : "")\(k.rawValue)") { sortKey = k }
                    }
                } label: {
                    Label(sortKey.rawValue, systemImage: sortKey.icon)
                }
                .tooltip("排序 · 5 选（日期降序默认 / 总分升降 / 盈亏升降）")
            }
            // v15.23 batch122 · 形态筛选 Menu（只在有 session 时显示）
            if !viewModel.log.sessions.isEmpty {
                Menu {
                    Button(filterPattern == nil ? "✓ 全部形态" : "全部形态") {
                        filterPattern = nil
                    }
                    Divider()
                    ForEach(TrainingScenarioPattern.allCases, id: \.self) { pat in
                        let isOn = (filterPattern == pat)
                        Button("\(pat.emoji) \(pat.displayName) \(isOn ? "✓" : "")") {
                            filterPattern = isOn ? nil : pat
                        }
                    }
                } label: {
                    if let p = filterPattern {
                        Label("\(p.emoji) \(p.displayName)",
                              systemImage: "line.3.horizontal.decrease.circle.fill")
                    } else {
                        Label("筛选形态",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                .tooltip("按形态筛选历史训练（看自己在哪类行情成绩好/弱）")
                // v16.26 · 场景名搜索框（与 filter Menu 同时 AND · trader 历史多时快速定位）
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("搜索场景名", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 120)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.10))
                .cornerRadius(4)
                .tooltip("按场景名搜索（大小写不敏感 · 与形态/时段筛选同时 AND）")
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .tooltip("清空全部历史训练记录")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - v16.128 · session emoji 摘要（contextMenu 复制用）

    private func miniEmojiSummary(session: TrainingSession, score: TrainingScore) -> String {
        var parts: [String] = []
        parts.append("\(score.grade.emoji) \(score.totalScore) 分 · 等级 \(score.grade.displayName)")
        if let pat = session.scenarioPattern {
            parts.append("\(pat.emoji) \(pat.displayName)")
        }
        let errorCount = session.violations.filter { $0.severity == .error }.count
        let warningCount = session.violations.filter { $0.severity == .warning }.count
        if errorCount + warningCount > 0 {
            parts.append("⚠️ \(errorCount + warningCount) 违规")
        } else {
            parts.append("✨ 0 违规")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - v16.64 · 删除 undo banner

    /// 删除 session 时先存到 pendingUndoSession + 启动 5s 自动清任务
    private func deleteSessionWithUndo(_ session: TrainingSession) {
        // 先 fetch score 备份（addSession 会重算 · 但配对/score 一致）
        viewModel.log.removeSession(id: session.id)
        pendingUndoSession = session
        undoClearTask?.cancel()
        undoClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                pendingUndoSession = nil
            }
        }
    }

    /// 撤销删除：重新 add · 触发评分缓存（与原 score 等价 · TrainingScorer 纯函数）
    private func undoDelete() {
        guard let s = pendingUndoSession else { return }
        viewModel.log.addSession(s)
        undoClearTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingUndoSession = nil
        }
    }

    /// 立即关闭 banner（不撤销）· 与"清空"按钮分开 · trader 看一眼后主动关闭
    private func dismissUndoBanner() {
        undoClearTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingUndoSession = nil
        }
    }

    /// undo banner UI · 5s 内一键撤销 · 删除任何 session 都触发
    private func undoBanner(for session: TrainingSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("已删除：\(session.scenarioName.isEmpty ? "未命名训练" : session.scenarioName)")
                .font(.system(size: 12))
            Spacer()
            Button {
                undoDelete()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut("z", modifiers: [.command])
            .tooltip("撤销删除（⌘Z · 5s 内有效）")
            Button {
                dismissUndoBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .tooltip("关闭（不撤销）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.orange.opacity(0.35)),
            alignment: .bottom
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("暂无历史训练")
                .font(.title3)
            Text("开始第一次模拟训练后，记录与评分会出现在这里")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            // v16.53 · 引导新 trader 一键开始（与 v15.23 batch16 推荐场景配合）
            // 触发 ⌘⇧S 即弹 ControlBar startSheet（pendingRetrainPattern 留 nil → 自定义模式）
            Text("提示：⌘⇧S 开始训练 · ⌘⇧T 切回此面板看历史")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 统计卡

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                statLine("总训练", value: "\(viewModel.log.sessionCount)", color: .primary)
                statLine("平均分", value: String(format: "%.1f", viewModel.log.averageScore),
                         color: averageColor)
                if let best = viewModel.log.bestScore {
                    statLine("最佳",
                             value: "\(best.totalScore) (\(best.grade.displayName))",
                             color: .accentColor)
                } else {
                    statLine("最佳", value: "—", color: .secondary)
                }
                // v15.23 batch135 · 连胜/连败 streak（≥ 2 才显示 · 心理学指标）
                let st = viewModel.log.currentStreak
                if st.count >= 2 {
                    statLine(st.isWinning ? "🔥 连胜" : "💧 连败",
                             value: "\(st.count) 次",
                             color: st.isWinning ? .red : .blue)
                }
                // v16.49 · 累计训练时长（鼓励高频 · 与 v15.23 batch144 weeklyGoalRow 互补）
                // v16.108 · 加平均每次时长（trader 看专注度 · 太短 = 试探 / 太长 = 拖延）
                // v16.122 · milestone emoji 升级（小时数突破鼓励）
                let totalMinutes = viewModel.log.sessions.map { $0.durationMinutes }.reduce(0, +)
                if totalMinutes > 0 {
                    let n = max(1, viewModel.log.sessionCount)
                    let avgMin = totalMinutes / n
                    let hours = Double(totalMinutes) / 60.0
                    let milestone: String = {
                        switch hours {
                        case 1000...:  return "🌟"   // 1000h 大师
                        case 500...:   return "👑"   // 500h 资深
                        case 100...:   return "🏆"   // 100h 高手
                        case 50...:    return "🚀"   // 50h 进阶
                        case 10...:    return "🎯"   // 10h 起步
                        default:       return "⏱"
                        }
                    }()
                    // v16.145 · 接近下一 milestone（剩 ≤ 5h）显示 "再 Xh 达成 N"
                    let nextMilestone: Double? = {
                        if hours < 10 { return 10 }
                        if hours < 50 { return 50 }
                        if hours < 100 { return 100 }
                        if hours < 500 { return 500 }
                        if hours < 1000 { return 1000 }
                        return nil
                    }()
                    let value: String = {
                        let base = totalMinutes >= 60
                                    ? String(format: "%.1f h · 均 %d 分/次", hours, avgMin)
                                    : "\(totalMinutes) min · 均 \(avgMin) 分/次"
                        if let next = nextMilestone, next - hours <= 5 {
                            return base + String(format: " · 距 %.0fh 还差 %.1fh", next, next - hours)
                        }
                        return base
                    }()
                    // v16.157 · 点击切月 filter（trader 看本月时长贡献来源）
                    // v16.187 · tooltip 加按月时长分布（trader 看哪月最专注）
                    let monthlyTooltip = buildMonthlyDurationTooltip(milestone: milestone, hours: hours)
                    Button {
                        filterPeriod = .month
                    } label: {
                        statLine("\(milestone) 累计",
                                 value: value,
                                 color: hours >= 50 ? .purple : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .tooltip(monthlyTooltip)
                }
                // v16.80 · 连训天数（与 ControlBar 🔥 chip 同算法 · ≥ 2 才显示）
                // v16.84 · 同步 milestone emoji 升级（与 ControlBar v16.83 一致）
                // v16.90 · 当前 < 历史最长 → 显示 "X / 最长 Y" · 当前 ≥ 历史 → 🎉
                let dayStreak = viewModel.log.consecutiveTrainingDays()
                if dayStreak >= 2 {
                    let best = viewModel.log.longestStreakEver()
                    let isNewRecord = dayStreak >= best
                    let emoji: String = {
                        if isNewRecord { return "🎉" }
                        switch dayStreak {
                        case 30...:  return "🏆"
                        case 14...:  return "🚀"
                        case 7...:   return "🔥🔥"
                        default:     return "🔥"
                        }
                    }()
                    let label = isNewRecord ? "\(emoji) 新纪录" : "\(emoji) 连训"
                    let value = isNewRecord || best == dayStreak
                                ? "\(dayStreak) 天"
                                : "\(dayStreak)/\(best) 天"
                    statLine(label, value: value, color: .red)
                }
                // v16.90 · 显示历史最长（当前无连训 · 但有训练记录时鼓励重启）
                else if dayStreak < 2 && viewModel.log.longestStreakEver() >= 3 {
                    statLine("🏅 历史最长",
                             value: "\(viewModel.log.longestStreakEver()) 天",
                             color: .secondary)
                }
            }

            distributionBar

            // v16.16 · 评分趋势 sparkline（最近 30 次按时间序 · trader 看进步曲线）
            scoreTrendSparkline

            // v15.23 batch125 · 形态分布 chip 行（点击 chip 等同选 filter · 视觉看练习偏向）
            patternDistributionRow

            // v16.62 · 5 维平均 chip 行（trader 月度五维倾向 · 与 v16.61 CSV 五维列配套）
            fiveDimAverageRow

            // v16.19 · 弱项加练推荐（≥ 3 次同形态训练 + 均分 < 70 → 一键启动加练）
            weakPatternRecommendRow

            // v16.114 · 最强形态展示（≥ 3 次 + 均分 ≥ 80 · 鼓励 + trader 自信形态）
            strongPatternShowcaseRow

            // v16.45 · 累积最常违反规则 chip（与 v16.41 ScoreSheet 单 session chip 配套 · 月度视角）
            mostViolatedRulesRow

            // v15.23 batch144 · 本周目标进度（鼓励 trader 维持训练频率）
            weeklyGoalRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// v16.16 · 评分趋势 sparkline · 最近 30 次按时间升序 · 折线 + 70 分参考线
    private var scoreTrendSparkline: some View {
        let recent = viewModel.log.sessions
            .sorted { $0.endedAt < $1.endedAt }   // 时间升序（左旧右新）
            .suffix(30)
        let scores = recent.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
        return HStack(spacing: 8) {
            Text("📈 趋势")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .leading)
            if scores.count < 2 {
                Text("需 ≥ 2 次训练才显示趋势")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .opacity(0.6)
                Spacer()
            } else {
                Canvas { ctx, size in
                    drawSparkline(ctx: ctx, size: size, scores: scores)
                }
                .frame(height: 36)
                Text("\(scores.last!)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(scoreColor(scores.last!))
                    .frame(width: 26, alignment: .trailing)
                trendDeltaChip(scores: scores)
            }
        }
    }

    private func drawSparkline(ctx: GraphicsContext, size: CGSize, scores: [Int]) {
        guard scores.count >= 2 else { return }
        let xStep = size.width / CGFloat(scores.count - 1)
        // y 映射：0-100 → bottom..top（留 2pt 边距）
        func yFor(_ s: Int) -> CGFloat {
            let clamped = max(0, min(100, s))
            return size.height - 2 - (size.height - 4) * CGFloat(clamped) / 100.0
        }
        // 70 分参考线（B 级合格线）· 虚线
        var ref = Path()
        let refY = yFor(70)
        ref.move(to: CGPoint(x: 0, y: refY))
        ref.addLine(to: CGPoint(x: size.width, y: refY))
        ctx.stroke(ref, with: .color(.secondary.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        // 折线
        var path = Path()
        for (i, s) in scores.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * xStep, y: yFor(s))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        ctx.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        // 端点圆点（最后一笔加大）
        for (i, s) in scores.enumerated() {
            let pt = CGPoint(x: CGFloat(i) * xStep, y: yFor(s))
            let r: CGFloat = (i == scores.count - 1) ? 3 : 1.5
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                with: .color(.accentColor)
            )
        }
    }

    /// 最近 5 次 vs 之前均值的 delta chip（提升/下降/持平）
    private func trendDeltaChip(scores: [Int]) -> some View {
        let n = scores.count
        let recentN = min(5, max(1, n / 3))
        let recent = scores.suffix(recentN)
        let prior = scores.prefix(n - recentN)
        let recentAvg = recent.isEmpty ? 0 : recent.reduce(0, +) / recent.count
        let priorAvg = prior.isEmpty ? recentAvg : prior.reduce(0, +) / prior.count
        let delta = recentAvg - priorAvg
        let (emoji, color): (String, Color) = {
            if abs(delta) < 3 { return ("→", .secondary) }
            return delta > 0 ? ("↑", .green) : ("↓", .red)
        }()
        let label = delta > 0 ? "+\(delta)" : "\(delta)"
        return HStack(spacing: 1) {
            Text(emoji).font(.system(size: 11)).foregroundColor(color)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(color)
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 90...:   return .green
        case 80..<90: return .blue
        case 70..<80: return .orange
        default:      return .red
        }
    }

    /// v15.23 batch144 · 本周训练目标进度（达到目标 → 绿色 ✓ · 未达成 → 进度条）
    private var weeklyGoalRow: some View {
        let cal = Calendar(identifier: .gregorian)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let thisWeekCount = viewModel.log.sessions.filter { $0.startedAt >= weekStart }.count
        let progress = min(Double(thisWeekCount) / Double(max(1, weeklyGoal)), 1.0)
        let achieved = thisWeekCount >= weeklyGoal
        return HStack(spacing: 6) {
            // v16.167 · "本周 N/M 次" + progress bar 一起包 Button · 点击 filter 本周
            Button {
                filterPeriod = .week
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: achieved ? "checkmark.seal.fill" : "target")
                        .foregroundColor(achieved ? .green : .accentColor)
                        .font(.system(size: 11))
                    Text("本周 \(thisWeekCount)/\(weeklyGoal) 次")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(achieved ? .green : .secondary)
                    ProgressView(value: progress, total: 1.0)
                        .frame(width: 100)
                        .tint(achieved ? .green : .accentColor)
                }
            }
            .buttonStyle(.plain)
            .tooltip("本周 \(thisWeekCount) / \(weeklyGoal) 次 · 点击 filter 本周查看")
            // v16.143 · 距周末 N 天提示（trader 周末前赶达标）
            if let weekEnd = cal.dateInterval(of: .weekOfYear, for: Date())?.end {
                let daysLeft = max(0, cal.dateComponents([.day], from: Date(), to: weekEnd).day ?? 0)
                if daysLeft > 0 && !achieved {
                    Text("⏳\(daysLeft)d")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .tooltip("距本周结束还有 \(daysLeft) 天")
                }
            }
            // v16.81 · 未达标时显示"再 N 次"hint · 达标显示"✓ 超额 M 次"
            // v16.115 · 差 1 次冲刺鼓励 + 达标超额按数量分级
            if achieved {
                let extra = thisWeekCount - weeklyGoal
                if extra > 0 {
                    let medal: String = {
                        switch extra {
                        case 5...:  return "🏆"   // 超额 5+
                        case 2...:  return "🎯"   // 超额 2-4
                        default:    return "✓"   // 超额 1
                        }
                    }()
                    Text("\(medal) 超额 +\(extra)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.green)
                }
            } else {
                let remaining = weeklyGoal - thisWeekCount
                let prefix = remaining == 1 ? "🎯 冲刺" : "再"
                Text("\(prefix) \(remaining) 次")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.orange)
            }
            // v15.23 batch154 · vs 上周对比（次数 / 平均分 deltas）
            weeklyComparisonChip(thisWeekStart: weekStart, thisWeekCount: thisWeekCount)
            // v16.67 · vs 上月对比 chip（trader 长期反馈 · 与 weeklyComparisonChip 同模式）
            monthlyComparisonChip()
            Spacer()
            Menu {
                ForEach([3, 5, 7, 10, 15], id: \.self) { n in
                    let isOn = (weeklyGoal == n)
                    Button("\(isOn ? "✓ " : "")\(n) 次/周") { weeklyGoal = n }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .tooltip("调整本周训练目标（3/5/7/10/15 次）")
        }
    }

    /// v15.23 batch154 · 本周 vs 上周对比 chip（仅有上周数据时显示）
    @ViewBuilder
    private func weeklyComparisonChip(thisWeekStart: Date, thisWeekCount: Int) -> some View {
        let cal = Calendar(identifier: .gregorian)
        let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? thisWeekStart
        let lastWeekSessions = viewModel.log.sessions.filter {
            $0.startedAt >= lastWeekStart && $0.startedAt < thisWeekStart
        }
        if !lastWeekSessions.isEmpty {
            let countDelta = thisWeekCount - lastWeekSessions.count
            let lastWeekAvg = lastWeekSessions.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
                .reduce(0, +) / max(1, lastWeekSessions.count)
            let thisWeekScores = viewModel.log.sessions
                .filter { $0.startedAt >= thisWeekStart }
                .compactMap { viewModel.log.score(for: $0.id)?.totalScore }
            let thisWeekAvg = thisWeekScores.isEmpty ? 0 : thisWeekScores.reduce(0, +) / thisWeekScores.count
            let scoreDelta = thisWeekAvg - lastWeekAvg
            HStack(spacing: 2) {
                Image(systemName: countDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9))
                    .foregroundColor(countDelta >= 0 ? .red : .green)
                Text("vs 上周 \(countDelta >= 0 ? "+" : "")\(countDelta)次 \(scoreDelta >= 0 ? "+" : "")\(scoreDelta)分")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .tooltip("本周 \(thisWeekCount) 次（平均 \(thisWeekAvg) 分） vs 上周 \(lastWeekSessions.count) 次（平均 \(lastWeekAvg) 分）")
        }
    }

    /// v16.67 · 本月 vs 上月对比 chip（trader 长期反馈 · 与 weeklyComparisonChip 同模式）
    /// 仅当上月有数据时显示 · 月历日历起始（dateInterval of .month）
    @ViewBuilder
    private func monthlyComparisonChip() -> some View {
        let cal = Calendar(identifier: .gregorian)
        guard let thisMonthStart = cal.dateInterval(of: .month, for: Date())?.start,
              let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) else {
            EmptyView()
            return
        }
        let lastMonthSessions = viewModel.log.sessions.filter {
            $0.startedAt >= lastMonthStart && $0.startedAt < thisMonthStart
        }
        if !lastMonthSessions.isEmpty {
            let thisMonthSessions = viewModel.log.sessions.filter { $0.startedAt >= thisMonthStart }
            let countDelta = thisMonthSessions.count - lastMonthSessions.count
            let lastMonthAvg = lastMonthSessions.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
                .reduce(0, +) / max(1, lastMonthSessions.count)
            let thisMonthScores = thisMonthSessions.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
            let thisMonthAvg = thisMonthScores.isEmpty ? 0 : thisMonthScores.reduce(0, +) / thisMonthScores.count
            let scoreDelta = thisMonthAvg - lastMonthAvg
            HStack(spacing: 2) {
                Image(systemName: countDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9))
                    .foregroundColor(countDelta >= 0 ? .red : .green)
                Text("vs 上月 \(countDelta >= 0 ? "+" : "")\(countDelta)次 \(scoreDelta >= 0 ? "+" : "")\(scoreDelta)分")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .tooltip("本月 \(thisMonthSessions.count) 次（平均 \(thisMonthAvg) 分） vs 上月 \(lastMonthSessions.count) 次（平均 \(lastMonthAvg) 分）")
        }
    }

    /// v16.142 · 强项 chip tooltip · 加最近 3 次该形态分数（与 v16.141 弱项同模式）
    private func buildStrongPatternTooltip(pattern: TrainingScenarioPattern,
                                            avg: Int, count: Int) -> String {
        let recentScores = viewModel.log.sessions
            .filter { $0.scenarioPattern == pattern }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(3)
            .compactMap { viewModel.log.score(for: $0.id)?.totalScore }
        var tip = "\(pattern.displayName) · 均分 \(avg)（\(count) 次）· 你的强项！· 点击过滤回顾"
        if !recentScores.isEmpty {
            tip += "\n最近 \(recentScores.count) 次：\(recentScores.map { "\($0)" }.joined(separator: " · "))"
        }
        return tip
    }

    /// v16.141 · 弱项 chip tooltip · 加最近 3 次该形态分数（trader 看趋势）
    private func buildWeakPatternTooltip(pattern: TrainingScenarioPattern,
                                          avg: Int, count: Int) -> String {
        let recentScores = viewModel.log.sessions
            .filter { $0.scenarioPattern == pattern }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(3)
            .compactMap { viewModel.log.score(for: $0.id)?.totalScore }
        var tip = "一键加练 \(pattern.displayName) · 当前均分 \(avg)（\(count) 次）"
        if !recentScores.isEmpty {
            tip += "\n最近 \(recentScores.count) 次：\(recentScores.map { "\($0)" }.joined(separator: " · "))"
        }
        return tip
    }

    /// v16.135 · 累积违规 chip tooltip · 加最近 5 次违反 session 名
    private func buildViolationChipTooltip(kind: DisciplineRuleKind, count: Int, isWorst: Bool) -> String {
        let recentSessions = viewModel.log.sessions
            .filter { $0.violations.contains { $0.ruleKind == kind } }
            .sorted { $0.endedAt > $1.endedAt }
            .prefix(5)
        var base = isWorst
            ? "累积最常违反 · \(kind.displayName) 共 \(count) 次 · 点击跳规则面板调阈值"
            : "\(kind.displayName) 累积违反 \(count) 次 · 点击跳规则面板"
        if !recentSessions.isEmpty {
            let names = recentSessions.map { $0.scenarioName.isEmpty ? "(未命名)" : $0.scenarioName }
            base += "\n最近 \(recentSessions.count) 次：\n" + names.map { "· \($0)" }.joined(separator: "\n")
        }
        return base
    }

    /// v16.62 · 全部 sessions 5 维平均 chip 行（trader 月度五维倾向）
    /// v16.73 · tooltip 加 min/max/N · trader hover 看 spread
    /// 数据源：log.scores subScores · 仅含 v2 评分的 session（老 session 缺 subScores 跳过）
    /// 最低维度橙色高亮 · trader 一眼看月度最弱
    private var fiveDimAverageRow: some View {
        struct DimStat { let dim: TrainingSubScores.Dimension; let avg: Int; let min: Int; let max: Int }
        let subs = viewModel.log.sessions.compactMap {
            viewModel.log.score(for: $0.id)?.subScores
        }
        return Group {
            if subs.isEmpty {
                EmptyView()
            } else {
                let n = subs.count
                func stat(_ dim: TrainingSubScores.Dimension, _ values: [Int]) -> DimStat {
                    DimStat(
                        dim: dim,
                        avg: Int(round(Double(values.reduce(0, +)) / Double(n))),
                        min: values.min() ?? 0,
                        max: values.max() ?? 0
                    )
                }
                let stats: [DimStat] = [
                    stat(.pnl,       subs.map(\.pnl)),
                    stat(.discipline, subs.map(\.discipline)),
                    stat(.winRate,   subs.map(\.winRate)),
                    stat(.risk,      subs.map(\.risk)),
                    stat(.efficiency, subs.map(\.efficiency)),
                ]
                let worstAvg = stats.min(by: { $0.avg < $1.avg })?.avg ?? 0
                // v16.133 · 全部 5 维 ≥ 80 → 完美状态 ✨（trader 全面均衡）
                // v16.134 · 全 ≥ 90 → 🌟 大师级（更高阶）
                let allBalanced = stats.allSatisfy { $0.avg >= 80 }
                let allMaster = stats.allSatisfy { $0.avg >= 90 }
                let labelEmoji: String = {
                    if allMaster { return "🌟" }
                    if allBalanced { return "✨" }
                    return "🔬"
                }()
                HStack(spacing: 6) {
                    Text("\(labelEmoji) 五维")
                        .font(.system(size: 10))
                        .foregroundColor(allBalanced ? .purple : .secondary)
                        .frame(width: 38, alignment: .leading)
                    ForEach(stats, id: \.dim) { d in
                        let isWeakest = d.avg == worstAvg && !allBalanced
                        HStack(spacing: 2) {
                            Text(d.dim.emoji).font(.system(size: 11))
                            Text("\(d.avg)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(isWeakest ? .orange : scoreColor(d.avg))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((isWeakest ? Color.orange : (allBalanced ? Color.purple : Color.secondary)).opacity(0.10))
                        .cornerRadius(3)
                        .tooltip("\(d.dim.displayName)：\(n) 次 v2 评分 · 平均 \(d.avg) · 最低 \(d.min) · 最高 \(d.max) · spread \(d.max - d.min)\((d.max - d.min) > 30 ? " ⚠️ 起伏大" : "")")
                    }
                    Spacer()
                }
            }
        }
    }

    /// v15.23 batch125 · 形态分布 chip（9 形态 emoji + 计数 · 点击切 filter）
    /// v16.19 · 弱项加练推荐
    /// 触发条件：某 pattern 已练 ≥ 3 次 + 均分 < 70（待巩固/薄弱）
    /// 排序：均分升序（最弱优先）
    /// 显示：emoji + pattern + 均分 + 一键再练 button（→ pendingRetrainPattern · 与 score sheet 同机制）
    private var weakPatternRecommendRow: some View {
        struct WeakBucket { let pattern: TrainingScenarioPattern; let avg: Int; let count: Int }
        var buckets: [WeakBucket] = []
        let grouped = Dictionary(grouping: viewModel.log.sessions.filter { $0.scenarioPattern != nil },
                                 by: { $0.scenarioPattern! })
        for (pat, sessions) in grouped {
            guard sessions.count >= 3 else { continue }
            let scores = sessions.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
            guard !scores.isEmpty else { continue }
            let avg = scores.reduce(0, +) / scores.count
            if avg < 70 {
                buckets.append(WeakBucket(pattern: pat, avg: avg, count: sessions.count))
            }
        }
        buckets.sort { $0.avg < $1.avg }
        return Group {
            if buckets.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    Text("⚠️ 加练")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .frame(width: 38, alignment: .leading)
                    ForEach(buckets.prefix(3), id: \.pattern) { b in
                        Button {
                            viewModel.pendingRetrainPattern = b.pattern
                        } label: {
                            HStack(spacing: 3) {
                                Text(b.pattern.emoji)
                                Text(b.pattern.displayName)
                                    .font(.system(size: 10))
                                Text("\(b.avg)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(b.avg < 60 ? .red : .orange)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.10))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .tooltip(buildWeakPatternTooltip(pattern: b.pattern, avg: b.avg, count: b.count))
                    }
                    Spacer()
                }
            }
        }
    }

    /// v16.114 · 最强形态展示（与 v16.19 弱项加练互补 · 鼓励 trader 自信形态）
    /// 条件：≥ 3 次同形态 + 均分 ≥ 80 · 降序均分排列 · 顶 3 个
    private var strongPatternShowcaseRow: some View {
        struct StrongBucket { let pattern: TrainingScenarioPattern; let avg: Int; let count: Int }
        var buckets: [StrongBucket] = []
        let grouped = Dictionary(grouping: viewModel.log.sessions.filter { $0.scenarioPattern != nil },
                                 by: { $0.scenarioPattern! })
        for (pat, sessions) in grouped {
            guard sessions.count >= 3 else { continue }
            let scores = sessions.compactMap { viewModel.log.score(for: $0.id)?.totalScore }
            guard !scores.isEmpty else { continue }
            let avg = scores.reduce(0, +) / scores.count
            if avg >= 80 {
                buckets.append(StrongBucket(pattern: pat, avg: avg, count: sessions.count))
            }
        }
        buckets.sort { $0.avg > $1.avg }
        return Group {
            if buckets.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    Text("🏆 强项")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .frame(width: 38, alignment: .leading)
                    ForEach(buckets.prefix(3), id: \.pattern) { b in
                        // v16.124 · 点击 chip 过滤该形态（trader 回顾强项）
                        Button {
                            filterPattern = b.pattern
                        } label: {
                            HStack(spacing: 3) {
                                Text(b.pattern.emoji)
                                Text(b.pattern.displayName)
                                    .font(.system(size: 10))
                                Text("\(b.avg)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(b.avg >= 90 ? .purple : .green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.10))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .tooltip(buildStrongPatternTooltip(pattern: b.pattern, avg: b.avg, count: b.count))
                    }
                    Spacer()
                }
            }
        }
    }

    /// v16.45 · 累积最常违反规则 chip · 全部 sessions 聚合 · count 降序 · 顶 3 个
    /// 与 v16.41 ScoreSheet 单 session chip 配套 · 月度视角看累积最弱规则
    private var mostViolatedRulesRow: some View {
        let allViolations = viewModel.log.sessions.flatMap { $0.violations }
        let grouped = Dictionary(grouping: allViolations, by: { $0.ruleKind })
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return Group {
            if grouped.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    Text("📛 累积")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .frame(width: 38, alignment: .leading)
                    ForEach(Array(grouped.prefix(3).enumerated()), id: \.offset) { idx, item in
                        let isWorst = (idx == 0)
                        // v16.46 · 点击 chip → 跳 rules panel 调该规则阈值（与 viewModel 闭环）
                        // v16.135 · tooltip 加最近 5 次违规 session 名（trader 一眼看哪些 session 触发）
                        Button {
                            viewModel.pendingJumpToRulesTab = true
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.kind.displayName)
                                    .font(.system(size: 10))
                                Text("×\(item.count)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((isWorst ? Color.red : Color.secondary).opacity(0.12))
                            .foregroundColor(isWorst ? .red : .primary)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .tooltip(buildViolationChipTooltip(kind: item.kind, count: item.count, isWorst: isWorst))
                    }
                    Spacer()
                }
            }
        }
    }

    private var patternDistributionRow: some View {
        let counts = Dictionary(grouping: viewModel.log.sessions.compactMap { $0.scenarioPattern }, by: { $0 })
            .mapValues { $0.count }
        return HStack(spacing: 4) {
            ForEach(TrainingScenarioPattern.allCases, id: \.self) { pat in
                let n = counts[pat] ?? 0
                let isActive = (filterPattern == pat)
                Button {
                    filterPattern = isActive ? nil : pat
                } label: {
                    HStack(spacing: 2) {
                        Text(pat.emoji)
                            .font(.system(size: 11))
                        Text("\(n)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isActive
                                ? Color.accentColor.opacity(0.25)
                                : (n > 0 ? Color.secondary.opacity(0.10) : Color.clear))
                    .cornerRadius(3)
                    .opacity(n == 0 ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .tooltip("\(pat.displayName) · \(n) 次")
            }
        }
    }

    private func statLine(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    /// 等级分布横条（5 段 · S A B C D · 宽度按计数比例 · 0 计数显示极窄）
    private var distributionBar: some View {
        let dist = viewModel.log.gradeDistribution
        let total = max(1, dist.values.reduce(0, +))
        return VStack(alignment: .leading, spacing: 4) {
            Text("等级分布")
                .font(.caption)
                .foregroundColor(.secondary)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(TrainingScore.Grade.allCases, id: \.self) { grade in
                        let count = dist[grade] ?? 0
                        let width = geo.size.width * CGFloat(count) / CGFloat(total)
                        Rectangle()
                            .fill(gradeColor(grade))
                            .frame(width: max(2, width))
                            .overlay(
                                Text(count > 0 ? "\(grade.displayName) \(count)" : "")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .frame(height: 22)
            .cornerRadius(3)
        }
    }

    // MARK: - 列表

    private var sessionList: some View {
        // v16.55 · 全集 filter + sort · 最后 prefix(visibleLimit) · trader 100+ session 性能
        // 旧实现先 recentSessions(50) 再 filter · filter 命中少时看不到第 51+ 条匹配
        var filtered: [TrainingSession] = viewModel.log.sessions
        if let p = filterPattern {
            filtered = filtered.filter { $0.scenarioPattern == p }
        }
        if let cutoff = filterPeriod.cutoff {
            filtered = filtered.filter { $0.startedAt >= cutoff }
        }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty {
            filtered = filtered.filter {
                $0.scenarioName.localizedCaseInsensitiveContains(trimmedSearch)
            }
        }
        switch sortKey {
        case .dateDesc:
            filtered.sort { $0.endedAt > $1.endedAt }
        case .scoreDesc:
            filtered.sort { (viewModel.log.score(for: $0.id)?.totalScore ?? 0)
                          > (viewModel.log.score(for: $1.id)?.totalScore ?? 0) }
        case .scoreAsc:
            filtered.sort { (viewModel.log.score(for: $0.id)?.totalScore ?? 0)
                          < (viewModel.log.score(for: $1.id)?.totalScore ?? 0) }
        case .pnlDesc:
            filtered.sort { $0.pnl > $1.pnl }
        case .pnlAsc:
            filtered.sort { $0.pnl < $1.pnl }
        }
        let totalMatched = filtered.count
        let visible = Array(filtered.prefix(visibleLimit))
        let remaining = max(0, totalMatched - visible.count)
        let hasAnyFilter = filterPattern != nil || filterPeriod != .all || !trimmedSearch.isEmpty
        return ScrollViewReader { proxy in
            List {
                if visible.isEmpty, hasAnyFilter {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 24)).foregroundColor(.secondary)
                            Text("没有匹配的训练记录")
                                .font(.callout).foregroundColor(.secondary)
                            Button("清空筛选") {
                                filterPattern = nil
                                filterPeriod = .all
                                searchText = ""
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                    .padding()
                }
                // v16.148 · 按月分组 separator（仅 sortKey 按时间时显示 · 其他排序无月份逻辑意义）
                let showMonthDividers = (sortKey == .dateDesc)
                let monthCounts: [String: Int] = showMonthDividers
                    ? Dictionary(grouping: visible, by: monthKey).mapValues { $0.count }
                    : [:]
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, session in
                    if showMonthDividers {
                        let curKey = monthKey(session)
                        let prevKey = idx > 0 ? monthKey(visible[idx - 1]) : nil
                        if curKey != prevKey {
                            monthDivider(key: curKey, count: monthCounts[curKey] ?? 0)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    sessionRow(session)
                        .id(session.id)   // v16.58 · ScrollViewReader anchor
                        .listRowBackground(
                            highlightedSessionID == session.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSessionID = session.id
                        }
                        .contextMenu {
                            Button("查看评分") { selectedSessionID = session.id }
                            // v16.112 · 一键再练该形态（与 ScoreSheet 再练同形态 同效 · 不必打开 sheet）
                            if let pattern = session.scenarioPattern {
                                Button {
                                    viewModel.pendingRetrainPattern = pattern
                                } label: {
                                    Label("再练同形态 \(pattern.emoji) \(pattern.displayName)",
                                          systemImage: "arrow.clockwise")
                                }
                            }
                            // v15.23 batch158 · 单 session 分享（复用 batch133 + batch146）
                            if let score = viewModel.log.score(for: session.id) {
                                Divider()
                                // v16.128 · emoji 摘要（轻量 · IM 一行分享 · 与 ScoreSheet v16.50 同模式）
                                Button {
                                    let summary = miniEmojiSummary(session: session, score: score)
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(summary, forType: .string)
                                } label: {
                                    Label("复制 emoji 摘要", systemImage: "text.bubble")
                                }
                                Button {
                                    let md = TrainingMarkdownReport.generateSingleSession(
                                        session, score: score)
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(md, forType: .string)
                                } label: {
                                    Label("复制单次分析（markdown）", systemImage: "doc.on.doc")
                                }
                                // v16.155 · 导出 5 维雷达 PNG（仅 v2 subScores 非 nil 时显示）
                                if score.subScores != nil {
                                    Button {
                                        exportSessionRadarPNG(session: session, score: score)
                                    } label: {
                                        Label("导出 5 维雷达 PNG", systemImage: "scope")
                                    }
                                }
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                deleteSessionWithUndo(session)
                            }
                        }
                }
                // v16.55 · 分页底部行（仅剩余 > 0 时显示）
                if remaining > 0 {
                    loadMoreRow(remaining: remaining, totalMatched: totalMatched, shown: visible.count)
                }
            }
            .listStyle(.inset)
            // v16.55 · filter/sort/search 任一变化 → 自动 reset 到第一页（macOS 13 单参数 onChange）
            .onChange(of: filterPattern) { _ in visibleLimit = pageSize }
            .onChange(of: filterPeriod) { _ in visibleLimit = pageSize }
            .onChange(of: sortKey) { _ in visibleLimit = pageSize }
            .onChange(of: searchText) { _ in visibleLimit = pageSize }
            // v16.58 · 训练结束 sheet dismiss · viewModel 推 recentlyAddedSessionID · 高亮 5s + scroll
            .onChange(of: viewModel.recentlyAddedSessionID) { newID in
                handleRecentlyAdded(newID, proxy: proxy)
            }
            // v16.151 · ControlBar today vs yesterday chip 点击 → set filterPeriod = .today + 清旗
            .onChange(of: viewModel.pendingHistoryFilterToToday) { newVal in
                if newVal {
                    filterPeriod = .today
                    DispatchQueue.main.async { viewModel.pendingHistoryFilterToToday = false }
                }
            }
        }
    }

    /// v16.58 · 处理新加 session 接力：清不匹配 filter → highlight → scroll → 5s 自动清
    private func handleRecentlyAdded(_ newID: UUID?, proxy: ScrollViewProxy) {
        guard let id = newID,
              let s = viewModel.log.session(id: id) else { return }
        // 当前 filter 是否会把它筛掉？若会 · 清掉让 trader 一定看见
        if !sessionMatchesFilters(s) {
            filterPattern = nil
            filterPeriod = .all
            searchText = ""
        }
        // 默认日期降序时新 session 必定在 visible 内 · 其他排序需要 reset 分页保证可见
        visibleLimit = pageSize
        highlightedSessionID = id
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
        highlightClearTask?.cancel()
        highlightClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                highlightedSessionID = nil
            }
            viewModel.recentlyAddedSessionID = nil
        }
    }

    /// v16.148 · session 月份 key（"yyyy-MM" 形式 · 用于分组 separator）
    private func monthKey(_ s: TrainingSession) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: s.endedAt)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    /// v16.148 · 月份分隔条（"📅 2026 年 5 月 · N 次"）· List row 形态
    private func monthDivider(key: String, count: Int) -> some View {
        let parts = key.split(separator: "-")
        let year = parts.count >= 1 ? String(parts[0]) : ""
        let month = parts.count >= 2 ? String(Int(parts[1]) ?? 0) : ""
        return HStack(spacing: 6) {
            Text("📅 \(year) 年 \(month) 月")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text("· \(count) 次")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(4)
    }

    /// v16.58 · 检查 session 是否被当前 filter/search 覆盖
    private func sessionMatchesFilters(_ s: TrainingSession) -> Bool {
        if let p = filterPattern, s.scenarioPattern != p { return false }
        if let cutoff = filterPeriod.cutoff, s.startedAt < cutoff { return false }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty,
           !s.scenarioName.localizedCaseInsensitiveContains(trimmed) {
            return false
        }
        return true
    }

    /// v16.55 · 列表底部 "加载更多 / 展开全部" 行
    private func loadMoreRow(remaining: Int, totalMatched: Int, shown: Int) -> some View {
        HStack(spacing: 12) {
            Text("显示 \(shown) / 共 \(totalMatched)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                visibleLimit += pageSize
            } label: {
                Label("加载更多 +\(min(pageSize, remaining))", systemImage: "chevron.down.circle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .tooltip("一次加载 \(pageSize) 条 · 剩余 \(remaining) 条")
            if remaining > pageSize {
                Button {
                    visibleLimit = totalMatched
                } label: {
                    Label("全部展开", systemImage: "arrow.down.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .tooltip("一次加载全部 \(totalMatched) 条 · 200+ 时可能卡顿")
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        let score = viewModel.log.score(for: session.id)
        return HStack(spacing: 10) {
            Text(score?.grade.emoji ?? "❔")
                .font(.system(size: 18))
                .frame(width: 28)
                // v16.179 · grade emoji hover tooltip 显示总分 + 5 维 + violations
                .tooltip(gradeEmojiTooltip(session: session, score: score))

            // v15.23 batch118 · 场景 mini thumbnail（pattern 非 nil 时显示 · 32×20pt）
            if let pattern = session.scenarioPattern {
                let seed = UInt64(bitPattern: Int64(session.id.hashValue))
                TrainingScenarioThumbnail(pattern: pattern,
                                          seed: seed,
                                          size: CGSize(width: 36, height: 22))
            } else {
                Color.clear.frame(width: 36, height: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.scenarioName.isEmpty ? "未命名训练" : session.scenarioName)
                    .font(.system(size: 13, weight: .medium))
                Text(dateText(session.endedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(score?.totalScore ?? 0)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(score.map { gradeColor($0.grade) } ?? .secondary)
                Text(String(format: "%+.2f%%", (session.pnlPercent as NSDecimalNumber).doubleValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(session.pnl >= 0 ? .green : .red)
                // v16.150 · mini 5 维 dots（visual 一眼看 5 维形状 · 老 log 跳过）
                if let sub = score?.subScores {
                    miniSubDotsRow(sub)
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// v16.150 · session 行内 mini 5 维 dots · 顺序 pnl/disc/win/risk/eff · 颜色按各维分数
    private func miniSubDotsRow(_ sub: TrainingSubScores) -> some View {
        let entries = sub.ordered  // [(dimension, score)] 5 元 · 与 ScoreSheet 同序
        let tip = entries.map { "\($0.dimension.emoji) \($0.score)" }.joined(separator: " / ")
        return HStack(spacing: 2) {
            ForEach(entries, id: \.dimension) { e in
                Circle()
                    .fill(subDotColor(e.score))
                    .frame(width: 5, height: 5)
            }
        }
        .tooltip(tip)
    }

    /// v16.155 · 单 session 5 维雷达图 PNG 导出（context menu 触发 · 不必打开 ScoreSheet）
    /// 复用 v16.155 共享 FiveDimRadarChart view + ImageRenderer · 简化 share card
    @MainActor
    private func exportSessionRadarPNG(session: TrainingSession, score: TrainingScore) {
        guard let sub = score.subScores else { return }
        let card = VStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                Text(session.scenarioName.isEmpty ? "训练评分" : session.scenarioName)
                    .font(.title3.bold())
                Text("\(score.grade.emoji) \(score.totalScore)/100 · \(score.grade.displayName) 级")
                    .font(.caption.bold())
                    .foregroundColor(gradeColor(score.grade))
            }
            FiveDimRadarChart(sub: sub)
                .frame(width: 260, height: 260)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sub.ordered, id: \.dimension) { entry in
                    HStack(spacing: 6) {
                        Text(entry.dimension.emoji).font(.system(size: 12))
                        Text(entry.dimension.displayName)
                            .font(.system(size: 11))
                            .frame(width: 50, alignment: .leading)
                        Text("\(entry.score)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(subDotColor(entry.score))
                        if entry.dimension == sub.weakest {
                            Text("← 最弱")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .frame(width: 200, alignment: .leading)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            Toast.errorBody("导出失败", "雷达图渲染失败")
            return
        }
        let panel = NSSavePanel()
        panel.title = "保存 5 维雷达图 PNG"
        panel.allowedContentTypes = [.png]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        let scenarioPart = session.scenarioName.isEmpty ? "训练" : session.scenarioName
        panel.nameFieldStringValue = "雷达_\(scenarioPart)_\(score.totalScore)分_\(dateFmt.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            Toast.info("导出成功", "已保存 \(url.lastPathComponent)")
        } catch {
            Toast.error("保存失败", error)
        }
    }

    /// v16.187 · 累计时长 chip tooltip · 顶部 base 信息 + 按月时长分布（最近 3 月）
    private func buildMonthlyDurationTooltip(milestone: String, hours: Double) -> String {
        var lines: [String] = []
        lines.append("\(milestone) 累计训练 \(String(format: "%.1f h", hours))")
        lines.append("点击 filter 本月查看时长来源")
        // 按月聚合（最近 3 月）
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        var monthly: [(label: String, mins: Int)] = []
        for offset in 0..<3 {
            guard let start = cal.date(byAdding: .month, value: -offset, to: now),
                  let interval = cal.dateInterval(of: .month, for: start) else { continue }
            let mins = viewModel.log.sessions
                .filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
                .map { $0.durationMinutes }
                .reduce(0, +)
            if mins > 0 {
                let comp = cal.dateComponents([.year, .month], from: start)
                let label = String(format: "%04d-%02d", comp.year ?? 0, comp.month ?? 0)
                monthly.append((label, mins))
            }
        }
        if !monthly.isEmpty {
            lines.append("")
            lines.append("按月分布：")
            for m in monthly {
                let h = Double(m.mins) / 60.0
                lines.append("· \(m.label): \(String(format: "%.1f h", h))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// v16.179 · session row grade emoji tooltip · 总分 + 5 维 + violations 速览
    private func gradeEmojiTooltip(session: TrainingSession, score: TrainingScore?) -> String {
        guard let sc = score else { return "❔ 未评分" }
        var parts: [String] = []
        parts.append("\(sc.grade.emoji) \(sc.grade.displayName) 级 · 总分 \(sc.totalScore)")
        if let sub = sc.subScores {
            let line = sub.ordered.map { "\($0.dimension.emoji)\($0.score)" }.joined(separator: " ")
            parts.append(line)
        }
        let errors = session.violations.filter { $0.severity == .error }.count
        let warns = session.violations.filter { $0.severity == .warning }.count
        if errors > 0 || warns > 0 {
            parts.append("⚠️ \(errors) error / \(warns) warning")
        } else {
            parts.append("✓ 0 违规")
        }
        return parts.joined(separator: "\n")
    }

    /// v16.150 · 5 维 dot 颜色（与 ScoreSheet subScoreColor 同阶梯 · 视觉一致）
    private func subDotColor(_ s: Int) -> Color {
        switch s {
        case 80...100: return .green
        case 60..<80:  return .blue
        case 40..<60:  return .orange
        default:       return .red
        }
    }

    // MARK: - Helpers

    private var selectedSessionBinding: Binding<TrainingSession?> {
        Binding(
            get: {
                guard let id = selectedSessionID else { return nil }
                return viewModel.log.session(id: id)
            },
            set: { newValue in
                selectedSessionID = newValue?.id
            }
        )
    }

    private var averageColor: Color {
        let avg = viewModel.log.averageScore
        if avg >= 80 { return .green }
        if avg >= 60 { return .blue }
        return .orange
    }

    private func gradeColor(_ grade: TrainingScore.Grade) -> Color {
        switch grade {
        case .S: return .purple
        case .A: return .green
        case .B: return .blue
        case .C: return .orange
        case .D: return .red
        }
    }

    /// v15.23 batch162 · 友好时间格式（"刚刚" / "X 小时前" / "今天 HH:mm" / "昨天" / "N 天前" / "MM-dd HH:mm"）
    private func dateText(_ d: Date) -> String {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let secs = now.timeIntervalSince(d)
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(Int(secs / 60)) 分钟前" }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return "今天 \(timeFmt.string(from: d))" }
        if cal.isDateInYesterday(d) { return "昨天 \(timeFmt.string(from: d))" }
        let days = cal.dateComponents([.day], from: d, to: now).day ?? 0
        if days < 7 { return "\(days) 天前 \(timeFmt.string(from: d))" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    // MARK: - v15.23 batch126 · 月报导出

    /// v15.23 batch131 · 当前 filter 拼成 label（用于报告标题后缀）
    private var filterLabel: String? {
        var parts: [String] = []
        if filterPeriod != .all { parts.append(filterPeriod.rawValue) }
        if let p = filterPattern { parts.append("\(p.emoji) \(p.displayName)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func generateMarkdown() -> String {
        TrainingMarkdownReport.generate(
            viewModel.log,
            filterPattern: filterPattern,
            filterCutoff: filterPeriod.cutoff,
            filterLabel: filterLabel
        )
    }

    private func copyReportToPasteboard() {
        let md = generateMarkdown()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    private func saveReportToFile() {
        let panel = NSSavePanel()
        panel.title = L("保存训练月报")
        panel.allowedContentTypes = [.plainText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "训练月报_\(dateFmt.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = generateMarkdown()
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - v15.23 batch197 · 周报导出（最近 7 天 · 不应用 filter · 与 ReviewWindow 节奏对齐）

    private func copyWeeklyReportToPasteboard() {
        let md = TrainingMarkdownReport.generateWeekly(viewModel.log)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    private func saveWeeklyReportToFile() {
        let panel = NSSavePanel()
        panel.title = L("保存训练周报")
        panel.allowedContentTypes = [.plainText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "训练周报_\(dateFmt.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = TrainingMarkdownReport.generateWeekly(viewModel.log)
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - v16.138 · 5 维平均 markdown（IM 分享）

    private func copyFiveDimMarkdownToPasteboard() {
        let subs = viewModel.log.sessions.compactMap {
            viewModel.log.score(for: $0.id)?.subScores
        }
        guard !subs.isEmpty else {
            Toast.errorBody("无数据", "尚未有 v2 评分的 session")
            return
        }
        let n = subs.count
        let avgPnl = subs.map(\.pnl).reduce(0, +) / n
        let avgDisc = subs.map(\.discipline).reduce(0, +) / n
        let avgWin = subs.map(\.winRate).reduce(0, +) / n
        let avgRisk = subs.map(\.risk).reduce(0, +) / n
        let avgEff = subs.map(\.efficiency).reduce(0, +) / n
        let items: [(emoji: String, name: String, score: Int)] = [
            ("💰", "盈亏", avgPnl), ("🛡️", "纪律", avgDisc),
            ("🎯", "胜率", avgWin), ("⚠️", "风险", avgRisk),
            ("⚡", "效率", avgEff),
        ]
        let worst = items.min(by: { $0.score < $1.score })!.name
        var md = "# 5 维平均（\(n) 次 v2 评分）\n\n"
        md += "| 维度 | 均分 |\n|------|------|\n"
        for it in items {
            let marker = it.name == worst ? " ⚠ 最弱" : ""
            md += "| \(it.emoji) \(it.name) | \(it.score)\(marker) |\n"
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
        Toast.info("复制成功", "5 维平均 markdown · \(md.count) 字符 · 已粘到剪贴板")
    }

    // MARK: - v16.20 · CSV 导出（离线 Excel/Numbers 分析）
    // v16.72 · filtered=true 时仅导出当前 filter/search 后子集

    private func saveCSVToFile(filtered: Bool) {
        let panel = NSSavePanel()
        panel.title = L(filtered ? "导出筛选后子集 CSV" : "导出训练历史 CSV")
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = filtered
            ? "训练历史_筛选_\(dateFmt.string(from: Date())).csv"
            : "训练历史_\(dateFmt.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let logForExport: TrainingSessionLog = filtered
            ? buildFilteredLog()
            : viewModel.log
        let data = TrainingSessionCSVExporter.exportData(logForExport)
        try? data.write(to: url, options: .atomic)
    }

    /// v16.72 · 应用当前 filter/search 构建子集 log（仅含匹配 session · 评分缓存自然带上）
    private func buildFilteredLog() -> TrainingSessionLog {
        var sub = TrainingSessionLog()
        for s in viewModel.log.sessions where sessionMatchesFilters(s) {
            sub.addSession(s)
        }
        return sub
    }

    // MARK: - v16.24 · CSV 导入（跨设备同步 / 备份恢复）

    private func importCSVFromFile() {
        let panel = NSOpenPanel()
        panel.title = L("导入训练历史 CSV")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let csv = String(data: data, encoding: .utf8) else { return }
        let imported = TrainingSessionCSVImporter.parse(csv)
        guard !imported.isEmpty else { return }
        // 合并：addSession 已自带同 id 覆盖语义 · 但 CSV 重生成的 session 是新 id · 直接 append
        for s in imported {
            viewModel.log.addSession(s)
        }
    }
}

#endif
