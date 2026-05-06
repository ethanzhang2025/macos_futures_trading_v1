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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator

            if viewModel.isSessionActive {
                Text("⏱ \(elapsedText)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 70, alignment: .leading)

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

            HStack {
                Text("场景").frame(width: 70, alignment: .leading)
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
        .frame(width: 400, height: 220)
    }

    // MARK: - 业务

    private func startSession() async {
        guard let balance = parsedBalance else { return }
        if let engine {
            await engine.setDisciplineRules(viewModel.book.enabledRules)
        }
        viewModel.startSession(initialBalance: balance, scenarioName: pendingScenario)
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

    private var elapsedText: String {
        guard let start = viewModel.sessionStartedAt else { return "00:00" }
        let secs = Int(nowTick.timeIntervalSince(start))
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
