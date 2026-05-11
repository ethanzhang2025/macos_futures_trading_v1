// MainApp · WP-54 模拟训练 · Session 开始/结束控制条（v15.23 batch11）
//
// 职责：
// - 显示当前 session 状态：active / idle
// - 开始训练按钮（弹 sheet · 输入 scenarioName + initialBalance · 默认 100w）
// - 结束训练按钮（active 时显示 · 调 viewModel.endSession 弹评分 sheet）
// - 实时倒数显示（已训练 mm:ss · violations 数）
//
// 设计要点：
// - engine 由父 View 传入 · 调用 setDisciplineRules + currentAccount snapshot 获取 finalBalance
// - 启动训练时把当前启用的规则 push 到 engine（trades 类自动评估开始生效）
// - 结束训练时取 engine.allTrades + engine.currentAccount 作为本次 session 数据

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import TradingCore

struct TrainingControlBar: View {

    @ObservedObject var viewModel: TrainingViewModel
    let engine: SimulatedTradingEngine?

    @State private var showStart: Bool = false
    @State private var pendingScenario: String = "短线训练"
    @State private var pendingBalance: String = "100000"
    @State private var feedback: String? = nil
    @State private var nowTick: Date = Date()
    /// v15.23 batch16 · 选中的预设场景（nil = 自定义）
    @State private var selectedPresetID: UUID? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator

            // v15.23 batch143 · streak chip（≥ 2 才显示 · 与 history panel 同步）
            let streak = viewModel.log.currentStreak
            if streak.count >= 2 {
                HStack(spacing: 3) {
                    Text(streak.isWinning ? "🔥" : "💧")
                        .font(.system(size: 12))
                    Text("\(streak.isWinning ? "连胜" : "连败")\(streak.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(streak.isWinning ? .red : .blue)
                }
                .tooltip(streak.isWinning
                      ? "连胜 \(streak.count) 次 · 别飘 · 守纪律"
                      : "连败 \(streak.count) 次 · 状态可能不对 · 考虑休息")
            }

            if viewModel.isSessionActive {
                // v16.52 · 暂停时 elapsed 灰色化（与 v16.42 暂停状态视觉强化）
                Text("⏱ \(elapsedText)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(viewModel.isSessionPaused ? .secondary : .accentColor)
                    .opacity(viewModel.isSessionPaused ? 0.6 : 1.0)
                    .frame(minWidth: 70, alignment: .leading)

                // v15.23 batch138 · 推荐时长进度条（仅 preset session · 自定义无）
                if let rec = viewModel.sessionRecommendedMinutes, rec > 0 {
                    let elapsedMin = elapsedSeconds / 60
                    let progress = min(Double(elapsedMin) / Double(rec), 1.5)  // 超时 1.5x cap
                    let isOvertime = elapsedMin > rec
                    HStack(spacing: 4) {
                        ProgressView(value: min(progress, 1.0), total: 1.0)
                            .frame(width: 80)
                            .tint(isOvertime ? .orange : .accentColor)
                        Text(isOvertime
                             ? "\(elapsedMin)/\(rec)分 ⚠超时"
                             : "\(elapsedMin)/\(rec)分")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isOvertime ? .orange : .secondary)
                    }
                    .tooltip("推荐时长 \(rec) 分钟 · 已练 \(elapsedMin) 分 · 超时表示可结束")
                }

                Text("违规 \(errorCount) · 警告 \(warningCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(violationColor)
            } else {
                // v15.23 batch147 · idle 时显示今日已练（次数 + 总时长）替代单一 idleHint
                // v16.76 · 加最近 7 天活动 mini bar（trader 看连续训练习惯 · 类 GitHub contributions）
                // v16.79 · 加连训天数 streak chip（鼓励保持习惯）
                let today = todayTally
                if today.count > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("今日已练 \(today.count) 次 · \(today.minutes) 分")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        todayVsYesterdayChip
                        consecutiveDaysChip
                        sevenDayMiniBar
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(idleHint)
                            .font(.caption)
                            .foregroundColor(idleHintColor)
                        // v16.194 · 启用率 mini progress（仅 X < Y 时显示 · 全启用不显示 vs v16.166 文本）
                        // v16.204 · tooltip 加详细 X 启用 / Y 禁用 + 跳 RulesPanel hint
                        if viewModel.book.rules.count > viewModel.book.enabledRules.count
                           && viewModel.book.rules.count >= 3 {
                            let total = viewModel.book.rules.count
                            let enabled = viewModel.book.enabledRules.count
                            let disabled = total - enabled
                            let ratio = Double(enabled) / Double(total)
                            ProgressView(value: ratio, total: 1.0)
                                .frame(width: 36, height: 4)
                                .tint(.accentColor)
                                .tooltip("启用率 \(Int(ratio * 100))%\n\(enabled) 启用 / \(disabled) 禁用 · 共 \(total) 条\n点击右侧 ⚙️ 打开 RulesPanel 编辑")
                        }
                        // v16.177 · ⚙️ 规则 chip 点击 → 跳 RulesPanel tab（与 v16.46 mostViolated 同模式）
                        Button {
                            viewModel.pendingJumpToRulesTab = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .tooltip("打开纪律规则面板（编辑/启用/导入）")
                        todayVsYesterdayChip
                        consecutiveDaysChip
                        sevenDayMiniBar
                    }
                }
            }

            Spacer()

            if viewModel.isSessionActive {
                // v16.42 · 暂停/继续（trader 训练中接电话/上厕所 · ⌘⇧P）
                Button {
                    if viewModel.isSessionPaused {
                        viewModel.resumeSession()
                    } else {
                        viewModel.pauseSession()
                    }
                } label: {
                    Label(viewModel.isSessionPaused ? "继续" : "暂停",
                          systemImage: viewModel.isSessionPaused ? "play.circle" : "pause.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .tooltip(viewModel.isSessionPaused
                         ? "继续训练（⌘⇧P · 计时恢复）"
                         : "暂停训练（⌘⇧P · 计时停 · 接电话/上厕所用）")
                Button(role: .destructive) {
                    Task { await endSession() }
                } label: {
                    Label("结束训练 · 评分", systemImage: "stop.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .tooltip("结束训练并评分（⌘⇧E）")
            } else {
                Button {
                    showStart = true
                } label: {
                    Label("开始训练", systemImage: "play.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .tooltip("开始模拟训练（⌘⇧S）")
            }

            if let f = feedback {
                Text(f).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(timer) { _ in nowTick = Date() }
        .sheet(isPresented: $showStart) {
            startSheet
        }
        // v15.23 batch132 · 监听 viewModel.pendingRetrainPattern · 找匹配 preset · 弹 startSheet
        .onChange(of: viewModel.pendingRetrainPattern) { newPattern in
            guard let pattern = newPattern else { return }
            // 找该形态的第一个内置 preset · 命中则 applyPreset · 否则仅打开 sheet（trader 自定义）
            if let preset = TrainingScenarios.defaultPresets.first(where: { $0.pattern == pattern }) {
                applyPreset(preset)
            }
            showStart = true
            // 立即清回 nil 防止重复触发
            DispatchQueue.main.async { viewModel.pendingRetrainPattern = nil }
        }
    }

    // MARK: - 状态指示

    @ViewBuilder
    private var statusIndicator: some View {
        if viewModel.isSessionActive {
            HStack(spacing: 6) {
                // v16.42 · 暂停时灯泡橙色 + 文案变"已暂停"
                Circle().fill(viewModel.isSessionPaused ? Color.orange : Color.green)
                    .frame(width: 9, height: 9)
                Text(viewModel.isSessionPaused ? "已暂停" : "训练中")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(viewModel.isSessionPaused ? .orange : .green)
            }
        } else {
            HStack(spacing: 6) {
                Circle().fill(Color.gray.opacity(0.5)).frame(width: 9, height: 9)
                Text("待机")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 开始 sheet

    private var startSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("开始模拟训练")
                .font(.title3).fontWeight(.semibold)

            // v15.23 batch16 · 推荐场景 picker（一键填充 scenarioName + initialBalance）
            HStack {
                Text("预设").frame(width: 70, alignment: .leading)
                Menu {
                    Button("自定义（不用预设）") {
                        selectedPresetID = nil
                    }
                    Divider()
                    ForEach(TrainingScenario.Difficulty.allCases, id: \.self) { difficulty in
                        let scenarios = TrainingScenarios.presets(of: difficulty)
                        if !scenarios.isEmpty {
                            Section(difficulty.emoji + " " + difficulty.displayName) {
                                ForEach(scenarios) { s in
                                    // v15.23 batch121 · 形态 emoji 前缀（〰️📈📉✓🚀↪️⚡️🌙🎯）
                                    Button("\(s.pattern.emoji) \(s.name)") {
                                        applyPreset(s)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedPresetLabel)
                            .foregroundColor(selectedPresetID == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // 选中预设时显示场景描述卡
            if let preset = selectedPreset {
                presetDescription(preset)
            }

            HStack {
                Text("场景名").frame(width: 70, alignment: .leading)
                TextField("如：螺纹钢急涨急跌 2020-08-12", text: $pendingScenario)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("初始资金").frame(width: 70, alignment: .leading)
                TextField("", text: $pendingBalance)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("元").foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.green)
                Text("启用 \(viewModel.book.enabledRules.count) 条纪律规则（实时评估）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("取消") { showStart = false }
                    .keyboardShortcut(.cancelAction)
                Button("开始") {
                    Task { await startSession() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parsedBalance == nil || viewModel.book.enabledRules.isEmpty)
            }
        }
        .padding(20)
        // batch116 · 加 K 线 thumbnail 后 preset 卡略高 · 460→500 给 thumbnail 喘息空间
        .frame(width: 500, height: selectedPreset == nil ? 280 : 410)
    }

    // MARK: - v15.23 batch16 · 预设场景操作

    private var selectedPreset: TrainingScenario? {
        guard let id = selectedPresetID else { return nil }
        return TrainingScenarios.defaultPresets.first { $0.id == id }
    }

    private var selectedPresetLabel: String {
        if let preset = selectedPreset {
            // batch121 · 难度 + 形态双 emoji 前缀
            return "\(preset.difficulty.emoji)\(preset.pattern.emoji) \(preset.name)"
        }
        return "自定义训练"
    }

    private func applyPreset(_ scenario: TrainingScenario) {
        selectedPresetID = scenario.id
        pendingScenario = scenario.name
        pendingBalance = String(format: "%.0f", (scenario.initialBalance as NSDecimalNumber).doubleValue)
    }

    private func presetDescription(_ scenario: TrainingScenario) -> some View {
        // v15.23 batch116 · 顶部 HStack：左边描述+chip · 右边 K 线 thumbnail
        let seed = UInt64(bitPattern: Int64(scenario.id.hashValue))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(scenario.description)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        metricChip(label: "合约", value: scenario.instrumentID, color: .accentColor)
                        metricChip(label: "时长", value: scenario.durationDescription, color: .blue)
                        metricChip(label: "建议训练", value: "\(scenario.recommendedDurationMinutes) 分", color: .orange)
                    }
                    Text("形态：\(scenario.pattern.displayName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                TrainingScenarioThumbnail(pattern: scenario.pattern,
                                          seed: seed,
                                          size: CGSize(width: 110, height: 50))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    private func metricChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
        }
    }

    // MARK: - 业务

    private func startSession() async {
        guard let balance = parsedBalance else { return }
        if let engine {
            await engine.setDisciplineRules(viewModel.book.enabledRules)
        }
        viewModel.startSession(initialBalance: balance,
                               scenarioName: pendingScenario,
                               scenarioPattern: selectedPreset?.pattern,
                               recommendedMinutes: selectedPreset?.recommendedDurationMinutes)
        showStart = false
        flash("训练已开始 · 实时纪律评估生效")
    }

    private func endSession() async {
        guard let engine else {
            // 无 engine 也允许结束 · 用 0 作为 finalBalance（测试态）
            viewModel.endSession(finalBalance: 0, trades: [])
            return
        }
        let account = await engine.currentAccount()
        let trades = await engine.allTrades()
        viewModel.endSession(finalBalance: account.balance, trades: trades)
        await engine.setDisciplineRules([])  // 训练结束后清空 engine 规则
        flash("训练已结束 · 评分已生成")
    }

    private func flash(_ msg: String) {
        feedback = msg
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { feedback = nil }
        }
    }

    // MARK: - Helpers

    private var parsedBalance: Decimal? {
        guard let d = Double(pendingBalance.trimmingCharacters(in: .whitespaces)) else { return nil }
        guard d.isFinite, d > 0 else { return nil }
        return Decimal(d)
    }

    /// v15.23 batch147 · 今日训练 tally（次数 + 总分钟数）· idle 时 ControlBar 显示
    private var todayTally: (count: Int, minutes: Int) {
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: Date())
        let todays = viewModel.log.sessions.filter { $0.startedAt >= startOfToday }
        let mins = todays.map { $0.durationMinutes }.reduce(0, +)
        return (todays.count, mins)
    }

    private var elapsedSeconds: Int {
        guard let start = viewModel.sessionStartedAt else { return 0 }
        // v16.42 · 扣减暂停时长（累积 + 当前正在暂停的部分）
        let total = nowTick.timeIntervalSince(start)
        var pause = viewModel.sessionAccumulatedPause
        if let pausedAt = viewModel.sessionPausedAt {
            pause += nowTick.timeIntervalSince(pausedAt)
        }
        return max(0, Int(total - pause))
    }

    private var elapsedText: String {
        let secs = elapsedSeconds
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var errorCount: Int {
        viewModel.liveViolations.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        viewModel.liveViolations.filter { $0.severity == .warning }.count
    }

    private var violationColor: Color {
        if errorCount > 0 { return .red }
        if warningCount > 0 { return .orange }
        return .secondary
    }

    private var idleHint: String {
        if viewModel.book.enabledRules.isEmpty {
            return "⚠️ 先启用至少 1 条纪律规则才能开始训练"
        }
        // v16.166 · 显示 "已启用 X / 共 Y" 格式（trader 看启用占比）
        let enabled = viewModel.book.enabledRules.count
        let total = viewModel.book.rules.count
        let countText = enabled == total ? "全部 \(total) 条" : "\(enabled) / \(total) 条"
        var hint = "✅ 已启用 \(countText)规则 · 准备就绪"
        // v16.132 · 上次训练距今（trader 看间隔 · 避免长时间不练）
        // v16.159 · > 24h 加 🔔 / > 72h 加 ⏰ 警示（提醒重新开始）
        if let last = viewModel.log.sessions.map(\.endedAt).max() {
            let secs = Date().timeIntervalSince(last)
            let prefix: String
            if secs > 72 * 3600 { prefix = " · ⏰ 上次 " }       // 3 天 +
            else if secs > 24 * 3600 { prefix = " · 🔔 上次 " }  // 24h +
            else { prefix = " · 上次 " }
            hint += prefix + timeSinceText(last)
        }
        return hint
    }

    /// v16.159 · idleHint 颜色（长时间未训练 → 警示色 · 帮助 trader 注意到该回来训练）
    private var idleHintColor: Color {
        guard let last = viewModel.log.sessions.map(\.endedAt).max() else { return .secondary }
        let secs = Date().timeIntervalSince(last)
        if secs > 72 * 3600 { return .red }       // > 3 天
        if secs > 24 * 3600 { return .orange }    // > 24h
        return .secondary
    }

    /// v16.132 · 友好时间差（"刚刚" / "N 分钟前" / "N 小时前" / "N 天前"）
    private func timeSinceText(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return "刚刚" }
        if secs < 3600 { return "\(Int(secs / 60)) 分钟前" }
        if secs < 86400 { return "\(Int(secs / 3600)) 小时前" }
        return "\(Int(secs / 86400)) 天前"
    }

    /// v16.104 · 今日 vs 昨日次数对比 chip（与 weekly/monthly 同模式 · ControlBar 短时反馈）
    /// 仅昨日有训练时显示 · 与 streak chip 并列
    @ViewBuilder
    private var todayVsYesterdayChip: some View {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else {
            EmptyView()
            return
        }
        let todayCount = viewModel.log.sessions.filter { $0.startedAt >= today }.count
        let yesterdayCount = viewModel.log.sessions.filter {
            $0.startedAt >= yesterday && $0.startedAt < today
        }.count
        if yesterdayCount > 0 {
            let delta = todayCount - yesterdayCount
            let (icon, color): (String, Color) = {
                if delta > 0 { return ("arrow.up.right", .red) }
                if delta < 0 { return ("arrow.down.right", .green) }
                return ("equal", .secondary)
            }()
            // v16.151 · 点击跳 history tab + filter today（与 streak chip 同模式）
            Button {
                viewModel.pendingHistoryFilterToToday = true
                viewModel.pendingJumpToHistoryTab = true
            } label: {
                HStack(spacing: 1) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundColor(color)
                    Text("vs 昨 \(delta >= 0 ? "+" : "")\(delta)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .tooltip("今日 \(todayCount) 次 vs 昨日 \(yesterdayCount) 次 · 点击查看今日训练")
        }
    }

    /// v16.79/v16.80 · 连续训练天数 streak chip · 算法提到 TrainingSessionLog.consecutiveTrainingDays
    /// v16.83 · milestone emoji 升级：🔥 (≥2) → 🔥🔥 (≥7) → 🚀 (≥14) → 🏆 (≥30)
    /// v16.89 · 加 personal best 对比 · 当前 ≥ 历史最长 → "🎉 新纪录"
    /// v16.101 · 点击跳 history tab（trader 看 streak 趋势 + 完整历史）
    /// ≥ 2 才显示（1 天不算 streak · 避免噪音）
    @ViewBuilder
    private var consecutiveDaysChip: some View {
        let streak = viewModel.log.consecutiveTrainingDays()
        if streak >= 2 {
            let best = viewModel.log.longestStreakEver()
            let isNewRecord = streak >= best
            let (emoji, hint): (String, String) = {
                switch streak {
                case 30...:  return ("🏆", "月级习惯（≥30 天）")
                case 14...:  return ("🚀", "两周习惯（≥14 天）")
                case 7...:   return ("🔥🔥", "周级习惯（≥7 天）")
                default:     return ("🔥", "起步阶段（2-6 天）")
                }
            }()
            // v16.139 · 接近下一 milestone（≤ 2 天）时显示鼓励
            let nextMilestone: (days: Int, label: String)? = {
                if streak < 7 { return (7, "🔥🔥 周级") }
                if streak < 14 { return (14, "🚀 两周") }
                if streak < 30 { return (30, "🏆 月级") }
                return nil
            }()
            let nearHint = nextMilestone.flatMap { ms -> String? in
                let remaining = ms.days - streak
                return remaining <= 2 ? " · 再 \(remaining) 天达 \(ms.label)" : nil
            }
            Button {
                viewModel.pendingJumpToHistoryTab = true
            } label: {
                HStack(spacing: 2) {
                    Text(isNewRecord ? "🎉" : emoji)
                        .font(.system(size: 11))
                    Text("连训 \(streak) 天")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                    if !isNewRecord, best > streak {
                        Text("/最长 \(best)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.10))
                .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .tooltip(isNewRecord
                     ? "🎉 新纪录！连续 \(streak) 天每天 ≥ 1 次训练 · \(hint) · 超越历史！点击跳历史 tab 看完整趋势\(nearHint ?? "")"
                     : "连续 \(streak) 天每天 ≥ 1 次训练 · \(hint) · 历史最长 \(best) 天 · 点击跳历史 tab\(nearHint ?? "")")
        }
    }

    /// v16.76 · 最近 7 天活动 mini bar（类 GitHub contributions · trader 看连训习惯）
    /// v16.101 · 点击跳 history tab · 与 streak chip 同效
    /// 高度按当天 session 数比例 · 今天柱 accent 色 · 其他 secondary
    private var sevenDayMiniBar: some View {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let days: [(date: Date, count: Int)] = (0...6).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let nextDay = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let count = viewModel.log.sessions.filter {
                $0.startedAt >= day && $0.startedAt < nextDay
            }.count
            return (day, count)
        }
        let maxCount = max(1, days.map(\.count).max() ?? 1)
        let totalWeek = days.map(\.count).reduce(0, +)
        return Button {
            viewModel.pendingJumpToHistoryTab = true
        } label: {
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(0..<days.count, id: \.self) { i in
                    let d = days[i]
                    let isToday = i == days.count - 1
                    let h = max(2, CGFloat(d.count) / CGFloat(maxCount) * 14)
                    Rectangle()
                        .fill(d.count == 0
                              ? Color.secondary.opacity(0.18)
                              : (isToday ? Color.accentColor : Color.secondary.opacity(0.55)))
                        .frame(width: 4, height: h)
                        .cornerRadius(1)
                }
            }
            .frame(height: 14)
        }
        .buttonStyle(.plain)
        .tooltip("最近 7 天训练：共 \(totalWeek) 次（今日 \(days.last?.count ?? 0) 次 · 最高 \(maxCount) 次/天）· 点击跳历史 tab")
    }
}

#endif
