// MainApp · Shell · v17.4 · 底部状态栏（专业产品最后一块视觉拼图）
// 显示：CTP 连接状态 / 行情状态 / 实时时间 / 训练 streak / 资金风险度
// 类 Bloomberg / TradingView 底部状态栏 · macOS HIG vibrancy 风

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import TradingCore

struct ShellStatusBar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    @State private var now: Date = Date()
    @State private var trainingLog: TrainingSessionLog = TrainingLogPersistence.load()
    @State private var currentTheme: ChartTheme = ChartThemeStore.load() ?? .dark

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// v17.96 · 心跳点透明度（每偶数秒 0.4 · 奇数秒 1.0 · 节拍式呼吸 · 提示数据流活着）
    private var heartbeatOpacity: Double {
        let s = Calendar.current.component(.second, from: now)
        return s.isMultiple(of: 2) ? 0.4 : 1.0
    }
    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private let fullDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEE"
        f.locale = Locale(identifier: "zh_Hans")
        return f
    }()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            // CTP 连接状态
            statusChip(
                icon: Circle().fill(DesignTokens.StatusColor.warning).frame(width: 6, height: 6),
                text: "CTP 未连接 (Stage A 模拟)",
                color: DesignTokens.StatusColor.warning
            )
            statusDivider
            // 行情状态 + v17.96 心跳（上次更新时间 · 1s tick · trader 一眼确认数据流活着）
            HStack(spacing: DesignTokens.Spacing.xs) {
                Circle()
                    .fill(DesignTokens.StatusColor.success)
                    .frame(width: 6, height: 6)
                    .opacity(heartbeatOpacity)
                Text("行情正常")
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.success)
                Text("· 上次更新 \(dateFmt.string(from: now))")
                    .font(DesignTokens.Typography.hint)
                    .foregroundColor(DesignTokens.StatusColor.dimmed)
            }
            .help("数据流心跳 · 每秒刷新本机时间作为 mock tick（Stage A · 接 CTP 后改读真行情 lastTickAt）")
            statusDivider
            // 资金风险度（重要数据 · 强调字号）
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("💰").font(DesignTokens.Typography.label)
                Text("权益")
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
                Text("¥100,000")
                    .font(DesignTokens.Typography.monoBold)
                    .foregroundColor(.primary)
                Text("· 风险")
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
                Text("0.0%")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.StatusColor.success)
            }
            statusDivider
            // 训练 streak
            trainingChip
            Spacer()
            // 当前 Workspace
            workspaceChip
            statusDivider
            // v17.12 A2.1 · 主题切换 chip
            themeChip
            statusDivider
            // 实时时间
            timeChip
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(height: 26)
        .background(.bar)
        .onReceive(clockTimer) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if let t = ChartThemeStore.load(), t != currentTheme { currentTheme = t }
        }
    }

    @ViewBuilder
    private var themeChip: some View {
        Button {
            let next: ChartTheme = (currentTheme == .dark) ? .light : .dark
            ChartThemeStore.save(next)
            currentTheme = next
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: currentTheme.icon)
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
                Text(currentTheme.displayName)
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
            }
        }
        .buttonStyle(.plain)
        .help("切换 \(currentTheme == .dark ? "浅色" : "深色") 主题")
    }

    @ViewBuilder
    private func statusChip<I: View>(icon: I, text: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            icon
            Text(text)
                .font(DesignTokens.Typography.label)
                .foregroundColor(color)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(DesignTokens.StatusColor.muted.opacity(0.3))
            .frame(width: DesignTokens.Border.hairline, height: 12)
    }

    @ViewBuilder
    private var trainingChip: some View {
        let streak = trainingLog.currentStreak
        if streak.count >= 2 {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(streak.isWinning ? "🔥" : "💧").font(DesignTokens.Typography.label)
                Text("\(streak.isWinning ? "连胜" : "连败") \(streak.count)")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(streak.isWinning ? .red : DesignTokens.StatusColor.accent)
            }
        } else if trainingLog.sessions.isEmpty {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("🎯").font(DesignTokens.Typography.label)
                Text("尚未训练")
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
            }
        } else {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("🎯").font(DesignTokens.Typography.label)
                Text("累计 \(trainingLog.sessions.count) 次")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.StatusColor.muted)
            }
        }
    }

    @ViewBuilder
    private var workspaceChip: some View {
        if let ws = shellVM.activeWorkspace {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(ws.primaryTab.emoji).font(DesignTokens.Typography.label)
                Text(ws.name)
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(.primary)
                Text("·")
                    .foregroundColor(DesignTokens.StatusColor.dimmed)
                    .font(DesignTokens.Typography.label)
                Text(ws.paneLayout.displayName)
                    .font(DesignTokens.Typography.label)
                    .foregroundColor(DesignTokens.StatusColor.muted)
            }
        }
    }

    private var timeChip: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "clock")
                .font(DesignTokens.Typography.label)
                .foregroundColor(DesignTokens.StatusColor.muted)
            Text(dateFmt.string(from: now))
                .font(DesignTokens.Typography.monoBold)
                .foregroundColor(.primary)
        }
        .help(fullDateFmt.string(from: now))
    }
}

#endif
