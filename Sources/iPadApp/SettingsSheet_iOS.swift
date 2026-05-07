// SettingsSheet_iOS · iPad 设置 sheet（WP-61 batch007）
//
// Section：
//   1. 同步状态：lastSync / 拉/推统计 / 冲突日志 N 条 · 手动触发 sync
//   2. 主题：跟随系统 / 浅色 / 深色（@AppStorage 持久化）
//   3. 关于：版本号 / 文档链接 / 协议条款占位
//
// 触发：root toolbar gear icon → sheet（presentationDetents medium/large）

#if canImport(SwiftUI) && os(iOS)

import SwiftUI
import SyncCore

enum AppTheme: String, CaseIterable {
    case auto = "auto"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .auto: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsSheet_iOS: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: SyncCoordinator_iOS
    @AppStorage("ipad.theme") private var theme: String = AppTheme.auto.rawValue

    @State private var conflicts: [SyncConflict] = []
    @State private var isLoadingConflicts = false

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                themeSection
                conflictSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await loadConflicts() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 同步状态

    @ViewBuilder
    private var syncSection: some View {
        Section("CloudKit 同步") {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading) {
                    Text(statusText)
                        .font(.subheadline)
                    if let detail = statusDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(coordinator.lastSyncDates.sorted(by: { $0.key < $1.key }), id: \.key) { (recordType, date) in
                LabeledContent(displayName(recordType)) {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                // batch008 接入实际 syncAll 触发 · 此处占位保持简洁
                Task { await dummyTriggerSync() }
            } label: {
                Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var statusIcon: String {
        switch coordinator.status {
        case .idle: return "circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .lastSucceeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.status {
        case .idle, .syncing: return .secondary
        case .lastSucceeded: return .green
        case .failed: return .orange
        }
    }

    private var statusText: String {
        switch coordinator.status {
        case .idle: return "等待"
        case .syncing(let rt): return "同步中：\(displayName(rt))"
        case .lastSucceeded(let at): return "已同步 · \(at.formatted(.relative(presentation: .numeric)))"
        case .failed(let msg): return "失败：\(msg)"
        }
    }

    private var statusDetail: String? {
        guard coordinator.conflictCount > 0 else { return nil }
        return "累计冲突 \(coordinator.conflictCount) 条 · 见下方冲突日志"
    }

    private func displayName(_ recordType: String) -> String {
        switch recordType {
        case Watchlist.syncRecordType: return "自选"
        case WorkspaceTemplate.syncRecordType: return "工作区"
        case SyncableSettings.syncRecordType: return "偏好"
        default: return recordType
        }
    }

    private func dummyTriggerSync() async {
        // batch005-008 期间用占位 · batch008 / WP-61 收尾时改为读取 root 持有的 book/workspace/settings
        _ = await coordinator.syncWatchlist(book: WatchlistViewModel.demoSeed())
    }

    // MARK: - 主题

    private var themeSection: some View {
        Section("外观") {
            Picker("主题", selection: $theme) {
                ForEach(AppTheme.allCases, id: \.rawValue) { t in
                    Text(t.displayName).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 冲突日志

    @ViewBuilder
    private var conflictSection: some View {
        if !conflicts.isEmpty {
            Section("最近冲突 · 最新 \(min(conflicts.count, 10)) 条") {
                ForEach(conflicts.prefix(10), id: \.recordID) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(displayName(c.recordType))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                            Text("v\(c.localVersion) ↔ v\(c.remoteVersion)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(c.resolvedAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(c.resolution == .local ? "→ 本地胜" : "→ 远端胜")
                            .font(.caption2)
                            .foregroundStyle(c.resolution == .local ? .blue : .orange)
                    }
                    .padding(.vertical, 2)
                }

                Button(role: .destructive) {
                    Task {
                        await coordinator.clearConflicts()
                        await loadConflicts()
                    }
                } label: {
                    Label("清空冲突日志", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: "v15.25 · iPad 基础版")
            LabeledContent("WP", value: "WP-61")
            LabeledContent("Stage", value: "A · M7-M9")
        }
    }

    private func loadConflicts() async {
        isLoadingConflicts = true
        conflicts = await coordinator.recentConflicts(limit: 50)
        isLoadingConflicts = false
    }
}

#endif
