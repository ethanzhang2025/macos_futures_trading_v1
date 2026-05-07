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
                .help(streak.isWinning
                      ? "连胜 \(streak.count) 次 · 别飘 · 守纪律"
                      : "连败 \(streak.count) 次 · 状态可能不对 · 考虑休息")
            }

            if viewModel.isSessionActive {
                Text("⏱ \(elapsedText)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.accentColor)
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
                    .help("推荐时长 \(rec) 分钟 · 已练 \(elapsedMin) 分 · 超时表示可结束")
                }

                Text("违规 \(errorCount) · 警告 \(warningCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(violationColor)
            } else {
                Text(idleHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.isSessionActive {
                Button(role: .destructive) {
                    Task { await endSession() }
                } label: {
                    Label("结束训练 · 评分", systemImage: "stop.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help("结束训练并评分（⌘⇧E）")
            } else {
                Button {
                    showStart = true
                } label: {
                    Label("开始训练", systemImage: "play.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("开始模拟训练（⌘⇧S）")
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
                Circle().fill(Color.green).frame(width: 9, height: 9)
                Text("训练中")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
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

    private var elapsedSeconds: Int {
        guard let start = viewModel.sessionStartedAt else { return 0 }
        return Int(nowTick.timeIntervalSince(start))
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
            return "先启用至少 1 条纪律规则才能开始训练"
        }
        return "已启用 \(viewModel.book.enabledRules.count) 条规则 · 准备就绪"
    }
}

#endif
