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

    @State private var showViolations: Bool = false
    /// v15.23 batch150 · 复制/截图反馈提示（3 秒自动清空）
    @State private var actionFeedback: String? = nil
    /// v15.23 batch152 · grade emoji 放大动画起始 scale（0.5 → 1.0 弹簧）
    @State private var emojiScale: CGFloat = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

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
                // v15.23 batch146 · 截图为 PNG 分享（朋友圈晒分）
                Button {
                    copyScreenshotToPasteboard()
                    flashFeedback("✓ 已截图 PNG · 粘贴到微信/朋友圈")
                } label: {
                    Label("截图分享", systemImage: "camera")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .tooltip("评分卡截图为 PNG（⌘⇧C · 粘贴到微信/朋友圈）")
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
    }

    /// v16.6 · subScores 注入 200pt 五维区域 · violations 折叠展开 180pt
    private var sheetHeight: CGFloat {
        var h: CGFloat = 480
        if score.subScores != nil { h += 200 }
        if showViolations { h += 180 }
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

            VStack(spacing: 5) {
                ForEach(sub.ordered, id: \.dimension) { entry in
                    subScoreRow(dimension: entry.dimension,
                                score: entry.score,
                                isWeakest: entry.dimension == sub.weakest)
                }
            }

            weaknessTip(sub)
        }
    }

    private func subScoreRow(dimension: TrainingSubScores.Dimension,
                             score: Int, isWeakest: Bool) -> some View {
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
        }
    }

    private func weaknessTip(_ sub: TrainingSubScores) -> some View {
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
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
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
        .frame(width: 500)
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
}

#endif
