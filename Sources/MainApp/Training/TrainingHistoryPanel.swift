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

    private let recentLimit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
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
                                   comparison: viewModel.log.patternComparison(for: session.id))
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
                    Section("CSV 数据（v16.20/v16.24 · 离线分析 + 跨设备同步）") {
                        Button {
                            saveCSVToFile()
                        } label: {
                            Label("导出训练历史 CSV", systemImage: "tablecells")
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

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("暂无历史训练")
                .font(.title3)
            Text("开始第一次模拟训练后，记录与评分会出现在这里")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
            }

            distributionBar

            // v16.16 · 评分趋势 sparkline（最近 30 次按时间序 · trader 看进步曲线）
            scoreTrendSparkline

            // v15.23 batch125 · 形态分布 chip 行（点击 chip 等同选 filter · 视觉看练习偏向）
            patternDistributionRow

            // v16.19 · 弱项加练推荐（≥ 3 次同形态训练 + 均分 < 70 → 一键启动加练）
            weakPatternRecommendRow

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
            Image(systemName: achieved ? "checkmark.seal.fill" : "target")
                .foregroundColor(achieved ? .green : .accentColor)
                .font(.system(size: 11))
            Text("本周 \(thisWeekCount)/\(weeklyGoal) 次")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(achieved ? .green : .secondary)
            ProgressView(value: progress, total: 1.0)
                .frame(width: 100)
                .tint(achieved ? .green : .accentColor)
            // v15.23 batch154 · vs 上周对比（次数 / 平均分 deltas）
            weeklyComparisonChip(thisWeekStart: weekStart, thisWeekCount: thisWeekCount)
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
                        .tooltip("一键加练 \(b.pattern.displayName) · 当前均分 \(b.avg)（\(b.count) 次）")
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
        let recent = viewModel.log.recentSessions(limit: recentLimit)
        // batch122/130 · 形态 + 时间段双重过滤（AND · 任一非 nil 都 filter）
        var filtered: [TrainingSession] = recent
        if let p = filterPattern {
            filtered = filtered.filter { $0.scenarioPattern == p }
        }
        if let cutoff = filterPeriod.cutoff {
            filtered = filtered.filter { $0.startedAt >= cutoff }
        }
        // v15.23 batch136 · 排序（recentSessions 已按日期降序 · 仅非默认时重排）
        switch sortKey {
        case .dateDesc:
            break  // 已是默认顺序
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
        let hasAnyFilter = filterPattern != nil || filterPeriod != .all
        return List {
            if filtered.isEmpty, hasAnyFilter {
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
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }
                .padding()
            }
            ForEach(filtered) { session in
                sessionRow(session)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSessionID = session.id
                    }
                    .contextMenu {
                        Button("查看评分") { selectedSessionID = session.id }
                        // v15.23 batch158 · 单 session 分享（复用 batch133 + batch146）
                        if let score = viewModel.log.score(for: session.id) {
                            Divider()
                            Button {
                                let md = TrainingMarkdownReport.generateSingleSession(
                                    session, score: score)
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(md, forType: .string)
                            } label: {
                                Label("复制单次分析（markdown）", systemImage: "doc.on.doc")
                            }
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.log.removeSession(id: session.id)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        let score = viewModel.log.score(for: session.id)
        return HStack(spacing: 10) {
            Text(score?.grade.emoji ?? "❔")
                .font(.system(size: 18))
                .frame(width: 28)

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
            }
        }
        .padding(.vertical, 3)
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

    // MARK: - v16.20 · CSV 导出（离线 Excel/Numbers 分析）

    private func saveCSVToFile() {
        let panel = NSSavePanel()
        panel.title = L("导出训练历史 CSV")
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "训练历史_\(dateFmt.string(from: Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = TrainingSessionCSVExporter.exportData(viewModel.log)
        try? data.write(to: url, options: .atomic)
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
