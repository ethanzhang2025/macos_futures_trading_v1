// MainApp · WP-54 模拟训练 · 实时违规反馈 Feed（v15.23 batch10）
//
// 职责：
// - 显示 viewModel.liveViolations（最新在顶 · severity 颜色区分）
// - 顶部统计：error 数 / warning 数 / 距 session 开始时长（若 active）
// - 空态文案（"暂无违规 · 保持纪律 ✨"）
// - 提供清空按钮（仅手动清 · 不影响 session 评分）
//
// 注意：engine.observe() 订阅在 TrainingWindow（batch14 整合时统一接入）
//      此处只渲染 viewModel.liveViolations · 测试可手动 push

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import TradingCore

struct TrainingViolationFeed: View {

    @ObservedObject var viewModel: TrainingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.liveViolations.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("⚡ 实时违规")
                .font(.headline)

            statBadge(label: "违规", count: errorCount, color: .red)
            statBadge(label: "警告", count: warningCount, color: .orange)

            if viewModel.isSessionActive {
                Text("⏱ \(elapsedText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.liveViolations.isEmpty {
                Button {
                    viewModel.liveViolations.removeAll()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .help("仅清当前 feed · 不影响 session 评分")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(count > 0 ? color : .secondary)
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 32))
                .foregroundColor(.green.opacity(0.7))
            Text("暂无违规")
                .font(.title3)
            Text("保持纪律 ✨")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - 列表

    private var list: some View {
        List {
            ForEach(viewModel.liveViolations) { v in
                row(v)
            }
        }
        .listStyle(.inset)
    }

    private func row(_ v: DisciplineViolation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(severityEmoji(v.severity))
                .font(.system(size: 14))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(v.ruleKind.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(severityColor(v.severity))
                    Text(timeText(v.occurredAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(v.message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let ctx = v.context, !ctx.isEmpty {
                    Text(ctx)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private var errorCount: Int {
        viewModel.liveViolations.filter { $0.severity == .error }.count
    }

    private var warningCount: Int {
        viewModel.liveViolations.filter { $0.severity == .warning }.count
    }

    private var elapsedText: String {
        guard let start = viewModel.sessionStartedAt else { return "" }
        let secs = Int(Date().timeIntervalSince(start))
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func severityEmoji(_ s: DisciplineViolation.Severity) -> String {
        switch s {
        case .error:   return "🔴"
        case .warning: return "🟡"
        }
    }

    private func severityColor(_ s: DisciplineViolation.Severity) -> Color {
        switch s {
        case .error:   return .red
        case .warning: return .orange
        }
    }

    private func timeText(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: d)
    }
}

#endif
