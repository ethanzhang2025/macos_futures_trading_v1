// MainApp · Shell · v17.0 PoC Step 2
// 顶部一级模块 Tab Bar（5 大模块 · ⌘+1..5 切换）
// 风格 B：icon emoji + 文字（拍板项 B 推荐）

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct PrimaryTabBar: View {
    @EnvironmentObject var shellVM: ShellViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PrimaryTab.allCases) { tab in
                primaryTabButton(tab)
            }
            Spacer()
            globalSearchButton
            connectionStatus
        }
        .padding(.horizontal, 12)
        .frame(height: ShellMetrics.topBarHeight)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func primaryTabButton(_ tab: PrimaryTab) -> some View {
        let isActive = (shellVM.primaryTab == tab)
        Button {
            if shellVM.primaryTab != tab {
                shellVM.primaryTab = tab
                shellVM.activateFirstWorkspaceOfPrimaryTab()
            }
        } label: {
            HStack(spacing: 4) {
                Text(tab.emoji).font(.system(size: 14))
                Text(tab.displayName)
                    .font(.system(size: 13,
                                  weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isActive
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear)
            .foregroundColor(isActive ? .accentColor : .primary)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help("\(tab.displayName)（⌘\(tab.shortcutNumber)）")
    }

    private var globalSearchButton: some View {
        Button {
            shellVM.showCommandPalette = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                Text("⌘K")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("全局命令面板（合约 / 模块 / Workspace · ⌘K）")
    }

    private var connectionStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text("CTP 未连接 · 行情正常")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

extension PrimaryTab {
    /// ⌘+数字快捷键编号
    var shortcutNumber: Int {
        switch self {
        case .watching:  return 1
        case .arbitrage: return 2
        case .option:    return 3
        case .review:    return 4
        case .training:  return 5
        }
    }
}

extension ShellViewModel {
    /// 切一级模块时自动激活该模块下的第一个 workspace（按 lastUsedAt desc）
    func activateFirstWorkspaceOfPrimaryTab() {
        let candidates = workspaces
            .filter { $0.primaryTab == primaryTab }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        if let first = candidates.first {
            activeWorkspaceID = first.id
        } else {
            // 该一级模块下无 workspace · 自动新建
            newWorkspace()
        }
    }
}

#endif
