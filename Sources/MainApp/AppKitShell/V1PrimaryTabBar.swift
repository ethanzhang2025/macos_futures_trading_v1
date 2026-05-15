// MainApp · AppKitShell · v17.211 · V1 重构 A1 PrimaryTabBar 重塑
//
// doc A1 「PrimaryTabBar 处理规则」章节 184-231
//   - 看盘 → 主窗 default 状态（永远 active · V1 主窗中央 ChartScene 一直在）
//   - 套利 → openWindow(id: "spread")
//   - 期权 → openWindow(id: "option")
//   - 复盘 → openWindow(id: "review")
//   - 训练 → openWindow(id: "training")
//
// 与旧 PrimaryTabBar 区别：
//   - 旧版改 shellVM.primaryTab + activateFirstWorkspaceOfPrimaryTab() · 切 PaneContainer paneBody
//   - V1 版"看盘"永远 active · 其他 4 是入口按钮 · 点击 openWindow 调独立 NSWindow
//
// 旧 PrimaryTabBar.swift 保留不动（旧 Shell 兼容）· Step 6 删旧 Shell 时连带删除。

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

/// V1 主窗顶部 PrimaryTabBar · A1 决策实现
struct V1PrimaryTabBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(PrimaryTab.allCases) { tab in
                primaryTabButton(tab)
            }
            Spacer()
            globalSearchButton
            connectionStatus
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: ShellMetrics.topBarHeight)
        .background(.regularMaterial)
    }

    /// 看盘永远 active · 其他 4 tab 是入口按钮（点击 openWindow · 不切 active 状态）
    @ViewBuilder
    private func primaryTabButton(_ tab: PrimaryTab) -> some View {
        let isActive = (tab == .watching)
        Button {
            handleTabTap(tab)
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(tab.emoji).font(.system(size: 15))
                Text(tab.displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(isActive
                        ? DesignTokens.StatusColor.accent.opacity(0.16)
                        : Color.clear)
            .foregroundColor(isActive ? DesignTokens.StatusColor.accent : .primary)
            .cornerRadius(DesignTokens.Radius.sm)
        }
        .buttonStyle(.plain)
        .help(helpText(for: tab))
    }

    private func handleTabTap(_ tab: PrimaryTab) {
        switch tab {
        case .watching:
            // V1 主窗 default 状态 · 看盘永远 active · 点击 no-op
            break
        case .arbitrage:
            openWindow(id: "spread")
        case .option:
            openWindow(id: "option")
        case .review:
            openWindow(id: "review")
        case .training:
            openWindow(id: "training")
        }
    }

    private func helpText(for tab: PrimaryTab) -> String {
        switch tab {
        case .watching:  return "看盘（主工作台 default 状态）"
        case .arbitrage: return "套利（独立窗口 · ⌘⌥S）"
        case .option:    return "期权（独立窗口 · ⌘⌥O）"
        case .review:    return "复盘（独立窗口 · ⌘R）"
        case .training:  return "模拟训练（独立窗口 · ⌘⇧T）"
        }
    }

    private var globalSearchButton: some View {
        Button {
            shellVM.showCommandPalette = true
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(DesignTokens.Typography.label)
                Text("⌘K")
                    .font(DesignTokens.Typography.hint)
            }
            .foregroundColor(DesignTokens.StatusColor.muted)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.StatusColor.muted.opacity(0.4),
                                  lineWidth: DesignTokens.Border.hairline)
            )
        }
        .buttonStyle(.plain)
        .help("全局命令面板（合约 / 模块 / Workspace · ⌘K）")
    }

    private var connectionStatus: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(DesignTokens.StatusColor.warning)
                .frame(width: 6, height: 6)
            Text("CTP 未连接 · 行情正常")
                .font(DesignTokens.Typography.hint)
                .foregroundColor(DesignTokens.StatusColor.muted)
        }
        .padding(.leading, DesignTokens.Spacing.sm)
    }
}

#endif
