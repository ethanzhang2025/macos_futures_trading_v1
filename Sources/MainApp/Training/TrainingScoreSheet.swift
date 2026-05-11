// MainApp · WP-54 模拟训练 · 评分 Sheet（v15.23 batch12 / v16.6 评分 v2）
//
// 职责：
// - 训练结束 / 历史回看时弹此 sheet
// - 上方：grade emoji 大字 + totalScore 百分制
// - 中部：v1 主分 2 子条（盈亏/纪律 0-50）· 4 metric · v2 五维子条（0-100）+ weakness 提示
// - 下方：summary 中文文案 + 违规折叠列表
// - 底部：关闭按钮（dismiss 触发 viewModel.dismissLastFinishedSheet 由 caller 处理）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import AppKit
import Foundation
import TradingCore

struct TrainingScoreSheet: View {

    let session: TrainingSession
    let score: TrainingScore
    let onDismiss: () -> Void
    /// v15.23 batch132 · 「再练同形态」回调（pattern 非 nil 时显示按钮）
    var onRetrain: ((TrainingScenarioPattern) -> Void)? = nil
    /// v16.13 · 同形态历史对比（caller 传 viewModel.log.patternComparison(for:) · 无历史时为 nil 不显示）
    var comparison: PatternComparison? = nil
    /// v16.27 · 全局最弱 pattern（caller 传 viewModel.log.weakestPattern() · 无满足时 nil 不显示按钮）
    var weakestPattern: TrainingScenarioPattern? = nil

    @State private var showViolations: Bool = false
    /// v15.23 batch150 · 复制/截图反馈提示（3 秒自动清空）
    @State private var actionFeedback: String? = nil
    /// v15.23 batch152 · grade emoji 放大动画起始 scale（0.5 → 1.0 弹簧）
    @State private var emojiScale: CGFloat = 0.5
    /// v16.56 · 5 维主分点击展开 drilldown · nil = 全部折叠 · 单选模式
    @State private var expandedDim: TrainingSubScores.Dimension? = nil
    /// v16.156 · 改进 plan 5 步行动展开 · onAppear 按弱项分数智能决定（< 70 默认展开 / 强项保持折叠）
    @State private var showPlan: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let comp = comparison, comp.priorCount > 0 {
                patternComparisonStrip(comp)
            }

            Divider()

            scoreCard

            if let sub = score.subScores {
                Divider()
                subScoresSection(sub)
            }

            Divider()

            summaryBlock

            if !session.violations.isEmpty {
                violationsSection
            }

            Spacer(minLength: 8)

            HStack {
                // v15.23 batch132 · 再练同形态按钮（pattern 非 nil 且 onRetrain 注入时显示）
                if let pattern = session.scenarioPattern, let cb = onRetrain {
                    Button {
                        onDismiss()
                        cb(pattern)
                    } label: {
                        Label("再练同形态", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .tooltip("立即开始一次同形态训练（⌘R · \(pattern.emoji) \(pattern.displayName)）")
                }
                // v15.23 batch155 · 随机形态训练（探索弱项 · trader 跳出舒适区）
                if let cb = onRetrain {
                    Button {
                        let candidates = TrainingScenarioPattern.allCases.filter { $0 != session.scenarioPattern }
                        let pick = candidates.randomElement() ?? .oscillation
                        onDismiss()
                        cb(pick)
                    } label: {
                        Label("随机练", systemImage: "die.face.5")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .tooltip("随机选一种形态（⌘⇧R · 避开当前形态）· 探索弱项")
                }
                // v16.27 · 加练全局最弱形态（与 v16.19 history panel weakPatternRecommendRow 同算法）
                // v16.31 · 快捷键改 ⌘⌥K（K=KO 弱项 · ⌘⌥W 已被全局价差套利占 · v16.30 切机暴露）
                if let cb = onRetrain, let weakest = weakestPattern {
                    Button {
                        onDismiss()
                        cb(weakest)
                    } label: {
                        Label("练最弱", systemImage: "exclamationmark.triangle.fill")
                    }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                    .tooltip("加练历史最弱形态（⌘⌥K · \(weakest.emoji) \(weakest.displayName)）· 均分 < 70 + 训练 ≥ 3 次")
                }
                // v15.23 batch133 · 复制本次分析为 markdown（trader 求点评 / 笔记）
                Button {
                    let md = TrainingMarkdownReport.generateSingleSession(session, score: score)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(md, forType: .string)
                    flashFeedback("✓ 已复制 \(md.count) 字符 markdown")
                } label: {
                    Label("复制分析", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command])
                .tooltip("复制本次训练详细 markdown（⌘C · 粘贴到笔记 / AI 求点评）")
                // v16.50 · 一行 emoji 摘要复制（朋友圈/IM 简短分享 · 与「复制分析」完整版互补）
                Button {
                    let summary = oneLineEmojiSummary()
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(summary, forType: .string)
                    flashFeedback("✓ 已复制摘要：\(summary)")
                } label: {
                    Label("复制摘要", systemImage: "text.bubble")
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .tooltip("复制 1 行 emoji 摘要（⌘⌥C · 朋友圈/IM 一行分享 · 比 markdown 简短）")
                // v15.23 batch146 · 截图为 PNG 分享（朋友圈晒分）
                // v16.120 · Menu 形式：复制剪贴板 / 保存文件二选一（与雷达图 v16.103 同模式）
                Menu {
                    Button {
                        copyScreenshotToPasteboard()
                        flashFeedback("✓ 已截图 PNG · 粘贴到微信/朋友圈")
                    } label: {
                        Label("复制到剪贴板（⌘⇧C）", systemImage: "doc.on.clipboard")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button {
                        saveScreenshotToFile()
                    } label: {
                        Label("保存为 PNG 文件…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("截图分享", systemImage: "camera")
                }
                .tooltip("评分卡截图 PNG · ⌘⇧C 复制 / 保存为文件")
                // v16.87 · 独立 5 维雷达图 PNG（朋友圈分享单 session 形状）
                // v16.103 · Menu 形式：复制到剪贴板 / 保存到文件二选一
                if score.subScores != nil {
                    Menu {
                        Button {
                            copyRadarPNGToPasteboard()
                            flashFeedback("✓ 已截图 5 维雷达图 · 粘贴分享")
                        } label: {
                            Label("复制到剪贴板（⌘⌥R）", systemImage: "doc.on.clipboard")
                        }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                        Button {
                            saveRadarPNGToFile()
                        } label: {
                            Label("保存为 PNG 文件…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("雷达图", systemImage: "scope")
                    }
                    .tooltip("5 维雷达图 PNG · ⌘⌥R 复制剪贴板 / 保存为文件")
                }
                // v15.23 batch150 · 反馈提示（3 秒消失）
                if let feedback = actionFeedback {
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Spacer()
                Button("关闭") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540, height: sheetHeight)
        // v16.156 · 改进 plan 智能默认：弱项分数 < 70 时自动展开（trader 弱时主动给建议）
        .onAppear {
            if let sub = score.subScores {
                let weakScore = sub.ordered.first { $0.dimension == sub.weakest }?.score ?? 100
                showPlan = weakScore < 70
            }
        }
        // v16.65 · ↑↓ 键盘切换 drilldown 维度（仅 subScores 存在时生效）
        .background(drilldownKeyboardShortcuts)
        // v16.82 · ESC 关闭 sheet（IDE/sheet 通用 · 与"关闭"⏎按钮互补）
        // v16.126 · 优先关 drilldown · 全部已折叠时才关 sheet（IDE 二级 dismiss）
        .background(
            Button("") {
                if expandedDim != nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedDim = nil
                    }
                } else {
                    onDismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
        )
    }

    /// v16.65 · 隐形 button 持 ↑↓ keyboardShortcut · 切换 5 维 drilldown 展开
    /// trader 看完一维公式按 ↓ 自动展开下一维 · 完整学习 5 维不用鼠标
    /// v16.168 · 数字键 1-5 直达对应维度（与 ↑↓ 互补 · trader 数字键跳转）
    @ViewBuilder
    private var drilldownKeyboardShortcuts: some View {
        if let sub = score.subScores {
            let dims = sub.ordered.map(\.dimension)
            Group {
                Button("") { stepDrilldown(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .opacity(0)
                Button("") { stepDrilldown(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .opacity(0)
                // v16.168 · 数字键 1-5 跳维度（不需要 modifier · sheet 内独占）
                ForEach(Array(dims.enumerated()), id: \.offset) { idx, dim in
                    Button("") { jumpToDimension(dim, totalCount: dims.count) }
                        .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
                        .opacity(0)
                }
                // v16.175 · ⌘⌥P 快捷复制 5 步改进 plan markdown（与 contextMenu 互补）
                Button("") { copyImprovementPlan(sub: sub) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .opacity(0)
            }
        }
    }

    /// v16.175 · 复制 5 步改进 plan markdown 到剪贴板（与 weaknessTip contextMenu 同源 · 加快捷键入口）
    private func copyImprovementPlan(sub: TrainingSubScores) {
        let weakScore = sub.ordered.first { $0.dimension == sub.weakest }?.score ?? 0
        let plan = TrainingScorer.improvementPlan(for: sub.weakest, score: weakScore)
        let header = "【💡 改进 plan · \(sub.weakest.emoji) \(sub.weakest.displayName) \(weakScore) 分】"
        let body = plan.enumerated().map { "\(stepNumberEmoji($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("\(header)\n\(body)", forType: .string)
        flashFeedback("✓ 已复制 5 步改进 plan（⌘⌥P）")
    }

    /// v16.168 · 数字键直跳指定维度（已展开同维度 → 切换折叠 · 否则切换到该维度）
    private func jumpToDimension(_ dim: TrainingSubScores.Dimension, totalCount: Int) {
        let isAlreadyExpanded = (expandedDim == dim)
        withAnimation(.easeInOut(duration: 0.15)) {
            expandedDim = isAlreadyExpanded ? nil : dim
        }
        if !isAlreadyExpanded {
            if let sub = score.subScores,
               let pos = sub.ordered.firstIndex(where: { $0.dimension == dim }) {
                flashFeedback("📊 \(dim.emoji) \(dim.displayName) (\(pos + 1)/\(totalCount))")
            }
        }
    }

    /// 按方向切换当前展开的维度 · nil → 第一/最后 · 越界 → 关闭（nil）
    /// v16.85 · 切换时短暂提示 trader 当前在第 N/5 维
    private func stepDrilldown(by delta: Int) {
        guard let sub = score.subScores else { return }
        let dims = sub.ordered.map(\.dimension)
        let newDim: TrainingSubScores.Dimension?
        if let cur = expandedDim, let idx = dims.firstIndex(of: cur) {
            let next = idx + delta
            newDim = (next < 0 || next >= dims.count) ? nil : dims[next]
        } else {
            newDim = delta > 0 ? dims.first : dims.last
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            expandedDim = newDim
        }
        if let d = newDim, let pos = dims.firstIndex(of: d) {
            flashFeedback("📊 \(d.emoji) \(d.displayName) (\(pos + 1)/\(dims.count))")
        }
    }

    /// v16.6 · subScores 注入 200pt 五维区域 · violations 折叠展开 180pt · v16.13 · comparison 加 50pt
    /// v16.56 · 5 维 drilldown 展开 +50pt（最长 efficiency/risk 公式两行）
    private var sheetHeight: CGFloat {
        var h: CGFloat = 480
        if score.subScores != nil { h += 200 }
        if expandedDim != nil { h += 50 }
        if showViolations { h += 180 }
        if let c = comparison, c.priorCount > 0 { h += 50 }
        return h
    }

    // MARK: - Header

    private var header: some View {
        baseHeader
            .padding(12)
            .background(gradeGradient(score.grade))
            .cornerRadius(8)
    }

    private var baseHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(score.grade.emoji)
                .font(.system(size: 56))
                .scaleEffect(emojiScale)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) {
                        emojiScale = 1.0
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("训练评分")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(score.totalScore)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(gradeColor(score.grade))
                    Text("/ 100")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("· 等级 \(score.grade.displayName)")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(gradeColor(score.grade))
                }
                if !session.scenarioName.isEmpty {
                    Text("场景：\(session.scenarioName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let pattern = session.scenarioPattern {
                    Text("形态：\(pattern.displayName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // v15.23 batch119 · 评分 sheet 顶部显示场景 thumbnail（trader 看分时回顾刚练的形态）
            if let pattern = session.scenarioPattern {
                let seed = UInt64(bitPattern: Int64(session.id.hashValue))
                TrainingScenarioThumbnail(pattern: pattern,
                                          seed: seed,
                                          size: CGSize(width: 110, height: 56))
            }
        }
    }

    // MARK: - 子分条

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            subScoreBar(
                label: "盈亏子分",
                emoji: "💰",
                value: score.pnlScore,
                tint: pnlColor
            )
            subScoreBar(
                label: "纪律子分",
                emoji: "📋",
                value: score.disciplineScore,
                tint: disciplineColor
            )

            HStack(spacing: 16) {
                metric(
                    label: "盈亏率",
                    value: String(format: "%.2f%%",
                                  (session.pnlPercent as NSDecimalNumber).doubleValue),
                    color: (session.pnl >= 0) ? .green : .red
                )
                metric(
                    label: "交易数",
                    value: "\(session.trades.count) 笔",
                    color: .primary
                )
                metric(
                    label: "时长",
                    value: "\(session.durationMinutes) 分钟",
                    color: .primary
                )
                metric(
                    label: "违规",
                    value: "\(errorCount) 违规 / \(warningCount) 警告",
                    color: errorCount > 0 ? .red : (warningCount > 0 ? .orange : .secondary)
                )
            }
        }
    }

    private func subScoreBar(label: String, emoji: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(emoji) \(label)")
                    .font(.caption)
                Spacer()
                Text("\(value) / 50")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(tint)
            }
            ProgressView(value: Double(value), total: 50)
                .tint(tint)
        }
    }

    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - v16.13 · 同形态历史对比 strip

    private func patternComparisonStrip(_ comp: PatternComparison) -> some View {
        let trend = comp.trendVsAverage
        let avgInt = Int(comp.priorAverageScore.rounded())
        let deltaText: String = {
            if comp.deltaVsAverage > 0 { return "+\(comp.deltaVsAverage)" }
            if comp.deltaVsAverage < 0 { return "\(comp.deltaVsAverage)" }
            return "持平"
        }()
        return HStack(spacing: 10) {
            Text("\(comp.pattern.emoji) \(comp.pattern.displayName)")
                .font(.system(size: 11, weight: .medium))
            Divider().frame(height: 16)
            Text("同形态历史 \(comp.priorCount) 次")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("均分 \(avgInt)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(trend.emoji)
                    .font(.system(size: 13))
                    .foregroundColor(trendColor(trend))
                Text(deltaText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(trendColor(trend))
            }
            if comp.isNewBest {
                Text("🏆 新高")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(4)
            }
            Spacer()
            Text("最佳 \(comp.priorBestScore)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    private func trendColor(_ trend: PatternComparison.Trend) -> Color {
        switch trend {
        case .up:        return .green
        case .down:      return .red
        case .flat:      return .secondary
        case .firstTime: return .blue
        }
    }

    // MARK: - v16.6 · 五维细分 + weakness 提示

    private func subScoresSection(_ sub: TrainingSubScores) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("🔬 五维细分")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("仅作分析视角 · 不计入总分")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 5) {
                    ForEach(sub.ordered, id: \.dimension) { entry in
                        subScoreRow(dimension: entry.dimension,
                                    score: entry.score,
                                    isWeakest: entry.dimension == sub.weakest)
                    }
                }
                // v16.14 · 五边形雷达图（与 5 子条同步 · trader 一眼看出形状偏弱方向）
                radarChart(sub)
                    .frame(width: 130, height: 130)
            }

            weaknessTip(sub)
        }
    }

    /// v16.14 · 5 维五边形雷达图 · v16.155 抽到 FiveDimRadarChart 共享 view（HistoryPanel 也用）
    private func radarChart(_ sub: TrainingSubScores) -> some View {
        FiveDimRadarChart(sub: sub)
    }

    private func subScoreRow(dimension: TrainingSubScores.Dimension,
                             score: Int, isWeakest: Bool) -> some View {
        let isExpanded = expandedDim == dimension
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(dimension.emoji) \(dimension.displayName)")
                    .font(.system(size: 11))
                    .frame(width: 70, alignment: .leading)
                    .foregroundColor(isWeakest ? .orange : .primary)
                ProgressView(value: Double(score), total: 100)
                    .tint(subScoreColor(score))
                Text("\(score)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
                    .foregroundColor(subScoreColor(score))
                if isWeakest {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                // v16.129 · 满分 100 加 🏆（trader 完美维度即时鼓励）
                if score == 100 {
                    Text("🏆")
                        .font(.system(size: 10))
                }
                // v16.56 · drilldown chevron · 展开本次具体计算
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedDim = isExpanded ? nil : dimension
                }
            }
            // v16.51 · hover 显示该维度计算公式（trader 学习评分逻辑透明度）
            .tooltip(dimensionFormulaHint(dimension))
            // v16.163 · 右键复制公式 hint（trader 一键保存学习公式 · 与 v16.131 复制 drilldown 互补）
            .contextMenu {
                Button {
                    let text = "【\(dimension.emoji) \(dimension.displayName) 公式】\n\(dimensionFormulaHint(dimension))"
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    flashFeedback("✓ 已复制 \(dimension.displayName) 公式")
                } label: {
                    Label("复制\(dimension.displayName)计算公式", systemImage: "doc.on.doc")
                }
            }

            // v16.56 · 展开行：本次具体数据计算（与公式 hint 配套 · hover 学公式 / 点击看本次数据）
            // v16.131 · 右键复制本维度详情（trader 单维度分析分享）
            if isExpanded {
                Text(dimensionBreakdownText(dimension))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.leading, 78)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07))
                    .cornerRadius(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .contextMenu {
                        Button {
                            let text = "【\(dimension.emoji) \(dimension.displayName) · 本次 \(score) 分】\n\(dimensionBreakdownText(dimension))"
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(text, forType: .string)
                            flashFeedback("✓ 已复制 \(dimension.displayName) drilldown")
                        } label: {
                            Label("复制本维度详情", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }

    /// v16.56 · 本次该维度具体数据计算字符串（基于 TrainingScorer.subScoreBreakdown · 防漂移）
    private func dimensionBreakdownText(_ d: TrainingSubScores.Dimension) -> String {
        let b = TrainingScorer.subScoreBreakdown(session)
        switch d {
        case .pnl:
            return String(format: "本次盈亏率 %+.2f%% → v1 阶梯 = %d/50 → ×2 = %d/100\n(>5%%=50 / >2%%=40 / >0=30 / 0=20 / >-2%%=10 / ≤-2%%=0)",
                          b.pnlPct, b.pnlV1, b.pnlV1 * 2)
        case .discipline:
            return String(format: "本次 %d 违规 + %d 警告 → 50 - %d×10 - %d×3 = %d/50 → ×2 = %d/100",
                          b.errorCount, b.warningCount,
                          b.errorCount, b.warningCount,
                          b.disciplineV1, b.disciplineV1 * 2)
        case .winRate:
            if b.pairCount == 0 {
                return "本次 \(b.tradeCount) 笔交易 · 0 完整配对 → 中性 50"
            }
            let pct = Double(b.winCount) / Double(b.pairCount) * 100
            return String(format: "本次 %d 笔交易 → %d 配对 · %d 盈利 → %d/%d × 100 = %.0f",
                          b.tradeCount, b.pairCount, b.winCount,
                          b.winCount, b.pairCount, pct)
        case .risk:
            if b.pairCount == 0 || b.initialBalance == 0 {
                return "本次无完整配对 / 无初始资金 → 中性 50"
            }
            if b.worstLossPct >= 5 {
                return String(format: "本次最大单笔亏损 ¥%.0f / 初始 ¥%.0f = %.2f%% ≥ 5%% → 0",
                              b.worstLoss, b.initialBalance, b.worstLossPct)
            }
            let s = Int(round((1.0 - b.worstLossPct / 5.0) * 100))
            return String(format: "本次最大单笔亏损 ¥%.0f / 初始 ¥%.0f = %.2f%% → (1 - %.2f/5) × 100 = %d",
                          b.worstLoss, b.initialBalance, b.worstLossPct, b.worstLossPct, s)
        case .efficiency:
            if b.pairCount == 0 || b.initialBalance == 0 {
                return "本次无完整配对 / 无初始资金 → 中性 50"
            }
            let clamped = max(-0.5, min(0.5, b.avgPairPnLPct))
            let s = Int(round((clamped + 0.5) * 100))
            return String(format: "本次配对总盈亏 ¥%+.0f / %d 配对 / 初始 ¥%.0f = %+.3f%% → (clamp±0.5%% + 0.5) × 100 = %d",
                          b.totalPairPnL, b.pairCount, b.initialBalance, b.avgPairPnLPct, s)
        }
    }

    /// v16.51 · 5 维主分计算公式中文说明（trader hover 即学）
    private func dimensionFormulaHint(_ d: TrainingSubScores.Dimension) -> String {
        switch d {
        case .pnl:
            return "盈亏维度：v1 主分 pnlScore × 2（满分 50 → 100 等价折算）· 收益率高分高"
        case .discipline:
            return "纪律维度：v1 主分 disciplineScore × 2（满分 50 → 100 等价折算）· 0 违规 = 50 / -10/error / -3/warning"
        case .winRate:
            return "胜率维度：trades FIFO 配对（合约+方向）· 盈利 pair 占比 × 100 · 无 pair → 50 中性"
        case .risk:
            return "风险维度：单笔最大亏损率（亏损额 / 初始资金 × 100%）· 5% → 0 / 0% → 100 线性"
        case .efficiency:
            return "效率维度：平均每笔 pnl%（总收益 / 配对数 / 初始资金）· ±0.5% → 0/100 线性"
        }
    }

    private func weaknessTip(_ sub: TrainingSubScores) -> some View {
        let weakScore = sub.ordered.first { $0.dimension == sub.weakest }?.score ?? 0
        let plan = TrainingScorer.improvementPlan(for: sub.weakest, score: weakScore)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("💡")
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("改进建议（最弱：\(sub.weakest.emoji) \(sub.weakest.displayName)）")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    Text(sub.weakness)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // v16.147 · 5 步行动 plan 展开/收起 chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPlan.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text("📋 5 步")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: showPlan ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .tooltip(showPlan ? "收起 5 步行动建议" : "展开 5 步具体行动建议")
            }
            // v16.147 · 5 步行动 plan numbered list（默认折叠 · 展开后 trader 可右键复制全部）
            // v16.162 · 步骤数字改 1️⃣2️⃣3️⃣4️⃣5️⃣ emoji（视觉强化 · 一眼数清楚 5 步）
            if showPlan {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(plan.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text(stepNumberEmoji(idx + 1))
                                .font(.system(size: 13))
                                .frame(width: 18, alignment: .center)
                            Text(step)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .contextMenu {
                    Button {
                        let header = "【💡 改进 plan · \(sub.weakest.emoji) \(sub.weakest.displayName) \(weakScore) 分】"
                        // v16.162 · 复制时也用 emoji 序号（IM 一致 trader 一眼数清楚）
                        let body = plan.enumerated().map { "\(stepNumberEmoji($0.offset + 1)) \($0.element)" }.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString("\(header)\n\(body)", forType: .string)
                        flashFeedback("✓ 已复制 5 步改进 plan")
                    } label: {
                        Label("复制 5 步行动 plan", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
    }

    /// v16.162 · 1-5 步骤数字 emoji（trader 视觉一眼数清楚 5 步）
    private func stepNumberEmoji(_ n: Int) -> String {
        switch n {
        case 1: return "1️⃣"
        case 2: return "2️⃣"
        case 3: return "3️⃣"
        case 4: return "4️⃣"
        case 5: return "5️⃣"
        default: return "\(n)."
        }
    }

    private func subScoreColor(_ s: Int) -> Color {
        switch s {
        case 80...100: return .green
        case 60..<80:  return .blue
        case 40..<60:  return .orange
        default:       return .red
        }
    }

    // MARK: - Summary

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("📝 评价")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(score.summary)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Violations

    private var violationsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { showViolations.toggle() }
            } label: {
                HStack {
                    Image(systemName: showViolations ? "chevron.down" : "chevron.right")
                    Text("违规明细 · \(session.violations.count) 条")
                        .font(.caption)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // v16.41 · 按规则分组统计 chip 行（trader 看分后立即定位最常违反的规则）
            violationsByRuleChips

            if showViolations {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(session.violations) { v in
                            violationRow(v)
                        }
                    }
                }
                .frame(height: 180)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    /// v16.41 · 按规则 kind 分组 chip · 数量降序 · 最弱规则橙色标注
    private var violationsByRuleChips: some View {
        let grouped = Dictionary(grouping: session.violations, by: { $0.ruleKind })
            .map { (kind: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return Group {
            if grouped.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 4) {
                    Text("最常违反")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ForEach(Array(grouped.prefix(3).enumerated()), id: \.offset) { idx, item in
                        let isWeakest = (idx == 0)
                        HStack(spacing: 3) {
                            Text(item.kind.displayName)
                                .font(.system(size: 10))
                            Text("×\(item.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((isWeakest ? Color.orange : Color.secondary).opacity(0.12))
                        .foregroundColor(isWeakest ? .orange : .primary)
                        .cornerRadius(4)
                        .tooltip(isWeakest
                                 ? "最常违反 · 下次训练重点改进 \(item.kind.displayName)（共 \(item.count) 次）"
                                 : "\(item.kind.displayName) 共违反 \(item.count) 次")
                    }
                    Spacer()
                }
            }
        }
    }

    private func violationRow(_ v: DisciplineViolation) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(v.severity == .error ? "🔴" : "🟡")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(v.ruleKind.displayName) · \(v.severity.displayName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(v.severity == .error ? .red : .orange)
                Text(v.message)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private var errorCount: Int {
        session.violations.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        session.violations.filter { $0.severity == .warning }.count
    }

    private var pnlColor: Color {
        switch score.pnlScore {
        case 40...50: return .green
        case 30..<40: return .blue
        case 20..<30: return .orange
        default:      return .red
        }
    }

    private var disciplineColor: Color {
        switch score.disciplineScore {
        case 40...50: return .green
        case 30..<40: return .blue
        case 20..<30: return .orange
        default:      return .red
        }
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

    /// v15.23 batch159 · grade 对应背景渐变（视觉强化 · 弱透明 · 不抢正文）
    private func gradeGradient(_ grade: TrainingScore.Grade) -> LinearGradient {
        let base = gradeColor(grade)
        return LinearGradient(
            gradient: Gradient(colors: [
                base.opacity(0.18),
                base.opacity(0.04),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - v15.23 batch150 · 反馈提示

    /// v16.50 · 1 行 emoji 摘要（朋友圈/IM 分享 · 60-80 字符精简）
    private func oneLineEmojiSummary() -> String {
        var parts: [String] = []
        parts.append("\(score.grade.emoji) \(score.totalScore) 分 · 等级 \(score.grade.displayName)")
        if let pat = session.scenarioPattern {
            parts.append("\(pat.emoji) \(pat.displayName)")
        }
        if let comp = comparison, comp.priorCount > 0 {
            let arrow = comp.trendVsAverage.emoji
            let delta = comp.deltaVsAverage
            let sign = delta >= 0 ? "+" : ""
            parts.append("同形态\(arrow)\(sign)\(delta)")
        }
        if errorCount + warningCount > 0 {
            parts.append("⚠️ \(errorCount + warningCount) 违规")
        } else {
            parts.append("✨ 0 违规")
        }
        return parts.joined(separator: " · ")
    }

    private func flashFeedback(_ msg: String) {
        actionFeedback = msg
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                actionFeedback = nil
            }
        }
    }

    // MARK: - v15.23 batch146 · 评分卡截图分享

    /// 渲染 header + scoreCard + (subScores) + summaryBlock 为 PNG · 写入剪贴板
    private func copyScreenshotToPasteboard() {
        let shareCard = VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            scoreCard
            if let sub = score.subScores {
                Divider()
                subScoresSection(sub)
            }
            Divider()
            summaryBlock
        }
        .padding(20)
        .frame(width: 540)
        .background(Color(NSColor.windowBackgroundColor))

        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 2  // retina
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    /// v16.103 · 渲染雷达图 PNG · 与 copy/save 共用（避免重复构造 view）
    private func renderRadarPNG() -> Data? {
        guard let sub = score.subScores else { return nil }
        let card = radarShareCard(sub)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2  // retina
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { return nil }
        return png
    }

    /// v16.103 · 保存雷达图 PNG 到文件（trader 长期归档 / 邮件附件）
    private func saveRadarPNGToFile() {
        guard let png = renderRadarPNG() else {
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
            flashFeedback("✓ 已保存 \(url.lastPathComponent)")
        } catch {
            Toast.error("保存失败", error)
        }
    }

    /// v16.87/103 · 雷达图分享卡片 view（copy/save 共用）
    @ViewBuilder
    private func radarShareCard(_ sub: TrainingSubScores) -> some View {
        VStack(alignment: .center, spacing: 12) {
            VStack(spacing: 4) {
                Text(session.scenarioName.isEmpty ? "训练评分" : session.scenarioName)
                    .font(.title3.bold())
                HStack(spacing: 6) {
                    if let pattern = session.scenarioPattern {
                        Text("\(pattern.emoji) \(pattern.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("\(score.grade.emoji) \(score.totalScore)/100 · \(score.grade.displayName) 级")
                        .font(.caption.bold())
                        .foregroundColor(gradeColor(score.grade))
                }
            }
            radarChart(sub)
                .frame(width: 260, height: 260)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sub.ordered, id: \.dimension) { entry in
                    HStack(spacing: 6) {
                        Text(entry.dimension.emoji)
                            .font(.system(size: 12))
                        Text(entry.dimension.displayName)
                            .font(.system(size: 11))
                            .frame(width: 50, alignment: .leading)
                        Text("\(entry.score)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(subScoreColor(entry.score))
                        if entry.dimension == sub.weakest {
                            Text("← 最弱")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .frame(width: 200, alignment: .leading)
            Text(oneLineEmojiSummary())
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(20)
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// v16.87 · 独立 5 维雷达图 PNG（朋友圈分享单 session 形状 · 比 ⌘⇧C 更精简）
    /// v16.103 · view 提到 radarShareCard helper · copy + save 共用
    private func copyRadarPNGToPasteboard() {
        guard let png = renderRadarPNG() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }

    /// v16.120 · 保存完整评分卡截图 PNG 到文件（trader 长期归档）
    private func saveScreenshotToFile() {
        let shareCard = VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            scoreCard
            if let sub = score.subScores {
                Divider()
                subScoresSection(sub)
            }
            Divider()
            summaryBlock
        }
        .padding(20)
        .frame(width: 540)
        .background(Color(NSColor.windowBackgroundColor))
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            Toast.errorBody("导出失败", "评分卡渲染失败")
            return
        }
        let panel = NSSavePanel()
        panel.title = "保存评分卡 PNG"
        panel.allowedContentTypes = [.png]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMdd_HHmm"
        let scenarioPart = session.scenarioName.isEmpty ? "训练" : session.scenarioName
        panel.nameFieldStringValue = "评分卡_\(scenarioPart)_\(score.totalScore)分_\(dateFmt.string(from: Date())).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            flashFeedback("✓ 已保存 \(url.lastPathComponent)")
        } catch {
            Toast.error("保存失败", error)
        }
    }
}

#endif
