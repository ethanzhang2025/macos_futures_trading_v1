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
import Shared
import TradingCore

private enum TrainingTab: String, CaseIterable, Identifiable {
    case rules = "规则"
    case live  = "实时"
    case history = "历史"
    var id: String { rawValue }
}

struct TrainingWindow: View {

    @StateObject private var viewModel = TrainingViewModel()
    @State private var tab: TrainingTab = .rules
    @State private var observeTask: Task<Void, Never>? = nil

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
            TrainingScoreSheet(session: wrapper.session, score: wrapper.score) {
                viewModel.dismissLastFinishedSheet()
            }
        }
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
                        Text(t.rawValue)
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
