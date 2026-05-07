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
    /// v15.23 batch122 · 形态筛选（nil = 全部 · 选中后只显示该形态训练）
    @State private var filterPattern: TrainingScenarioPattern? = nil
    /// v15.23 batch130 · 时间段筛选（默认全部 · 与形态 filter 互补 · 同时 AND）
    @State private var filterPeriod: PeriodFilter = .all

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
                                   })
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
            if !viewModel.log.sessions.isEmpty {
                Menu {
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
                } label: {
                    Label("导出报告", systemImage: "square.and.arrow.up")
                }
                .help("生成 markdown 月报告（含统计 + 等级分布 + 形态分布 + 最近 30 次表格）")
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
                .help("按时间段筛选历史训练（与形态筛选互补 · 同时 AND）")
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
                .help("按形态筛选历史训练（看自己在哪类行情成绩好/弱）")
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .help("清空全部历史训练记录")
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

            // v15.23 batch125 · 形态分布 chip 行（点击 chip 等同选 filter · 视觉看练习偏向）
            patternDistributionRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// v15.23 batch125 · 形态分布 chip（9 形态 emoji + 计数 · 点击切 filter）
    private var patternDistributionRow: some View {
        let counts = Dictionary(grouping: viewModel.log.sessions.compactMap { $0.scenarioPattern })
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
                .help("\(pat.displayName) · \(n) 次")
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

    private func dateText(_ d: Date) -> String {
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
        panel.title = "保存训练月报"
        panel.allowedContentTypes = [.plainText]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "训练月报_\(dateFmt.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = generateMarkdown()
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}

#endif
