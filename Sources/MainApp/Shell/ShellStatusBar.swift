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
        HStack(spacing: 16) {
            // CTP 连接状态
            statusChip(
                icon: Circle().fill(Color.orange).frame(width: 6, height: 6),
                text: "CTP 未连接 (Stage A 模拟)",
                color: .orange
            )
            statusDivider
            // 行情状态 + v17.96 心跳（上次更新时间 · 1s tick · trader 一眼确认数据流活着）
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .opacity(heartbeatOpacity)
                Text("行情正常")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("· 上次更新 \(dateFmt.string(from: now))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .help("数据流心跳 · 每秒刷新本机时间作为 mock tick（Stage A · 接 CTP 后改读真行情 lastTickAt）")
            statusDivider
            // 资金风险度
            statusChip(
                icon: Text("💰").font(.system(size: 10)),
                text: "权益 ¥100,000 · 风险 0.0%",
                color: .secondary
            )
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
        .padding(.horizontal, 12)
        .frame(height: 22)
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
            HStack(spacing: 4) {
                Image(systemName: currentTheme.icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(currentTheme.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("切换 \(currentTheme == .dark ? "浅色" : "深色") 主题")
    }

    @ViewBuilder
    private func statusChip<I: View>(icon: I, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            icon
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
    }

    private var statusDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 12)
    }

    @ViewBuilder
    private var trainingChip: some View {
        let streak = trainingLog.currentStreak
        if streak.count >= 2 {
            HStack(spacing: 4) {
                Text(streak.isWinning ? "🔥" : "💧").font(.system(size: 10))
                Text("\(streak.isWinning ? "连胜" : "连败") \(streak.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(streak.isWinning ? .red : .blue)
            }
        } else if trainingLog.sessions.isEmpty {
            HStack(spacing: 4) {
                Text("🎯").font(.system(size: 10))
                Text("尚未训练")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Text("🎯").font(.system(size: 10))
                Text("累计 \(trainingLog.sessions.count) 次")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var workspaceChip: some View {
        if let ws = shellVM.activeWorkspace {
            HStack(spacing: 4) {
                Text(ws.primaryTab.emoji).font(.system(size: 10))
                Text(ws.name)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("·").foregroundColor(.secondary.opacity(0.4)).font(.system(size: 10))
                Text(ws.paneLayout.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }

    private var timeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(dateFmt.string(from: now))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.primary)
        }
        .help(fullDateFmt.string(from: now))
    }
}

#endif
