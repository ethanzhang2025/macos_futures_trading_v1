// MainApp · Shell · v17.0 PoC Step 6
// 左侧 Sidebar · 5 section（自选 / 板块 / 持仓 / 异动 / 训练）
// v17.3 训练真数据 · v17.21 持仓真数据（SimulatedTradingStore）· 自选 + 板块 + 异动仍 mock

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import TradingCore
import Shared

struct ShellSidebar: View {
    @EnvironmentObject var shellVM: ShellViewModel
    /// v17.3 · 训练 log 真实数据（启动时一次性加载 · 后续重启刷新）
    @State private var trainingLog: TrainingSessionLog = TrainingLogPersistence.load()
    /// v17.21 · 模拟交易 snapshot 真实数据（持仓 + 现价 · UserDefaults didChange 跟随）
    @State private var tradingSnapshot: SimulatedTradingSnapshot? = SimulatedTradingStore.load()

    var body: some View {
        List {
            watchlistSection
            sectorSection
            positionSection
            anomalySection
            trainingSection
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // v17.21 · TradingWindow 改持仓时 Sidebar 实时跟（与 chartTheme/HUD 同模式）
            if let snap = SimulatedTradingStore.load() { tradingSnapshot = snap }
        }
    }

    // MARK: - 自选 mini

    private var watchlistSection: some View {
        Section {
            ForEach(mockWatchlist, id: \.symbol) { item in
                HStack(spacing: 6) {
                    Text(item.symbol)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Text(item.price)
                        .font(.system(size: 11, design: .monospaced))
                    Text(item.change)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(item.change.hasPrefix("+") ? .red : .green)
                }
                .padding(.vertical, 1)
            }
        } header: {
            Label("自选", systemImage: "star.fill")
                .foregroundColor(.orange)
        }
    }

    // MARK: - 板块

    private var sectorSection: some View {
        Section {
            ForEach(mockSectors, id: \.name) { sec in
                HStack(spacing: 6) {
                    Text(sec.emoji)
                    Text(sec.name).font(.system(size: 12))
                    Spacer()
                    Text(sec.change)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(sec.change.hasPrefix("+") ? .red : .green)
                }
                .padding(.vertical, 1)
            }
        } header: {
            Label("板块", systemImage: "square.grid.2x2.fill")
                .foregroundColor(.blue)
        }
    }

    // MARK: - 持仓速览（v17.21 接 SimulatedTradingStore 真实数据）

    private var realPositions: [Position] {
        tradingSnapshot?.positions ?? []
    }

    private func positionPnL(_ pos: Position) -> Decimal {
        guard let lastPrice = tradingSnapshot?.instrumentLastPrice[pos.instrumentID] else { return 0 }
        return pos.floatingPnL(currentPrice: lastPrice)
    }

    private var positionSection: some View {
        Section {
            ForEach(realPositions, id: \.instrumentID) { pos in
                HStack(spacing: 6) {
                    Text(pos.instrumentID)
                        .font(.system(size: 12, design: .monospaced))
                    Text(pos.direction.displayName)
                        .font(.system(size: 10))
                        .padding(.horizontal, 3)
                        .background((pos.direction == .long ? Color.red : Color.green).opacity(0.2))
                        .cornerRadius(2)
                    Text("\(pos.volume)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    let pnl = positionPnL(pos)
                    let pnlVal = NSDecimalNumber(decimal: pnl).doubleValue
                    Text(String(format: "%@¥%.0f", pnlVal >= 0 ? "+" : "", pnlVal))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(pnlVal >= 0 ? .red : .green)
                }
                .padding(.vertical, 1)
            }
            if realPositions.isEmpty {
                Text("无持仓").font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Label("持仓 (\(realPositions.count))", systemImage: "briefcase.fill")
                .foregroundColor(.purple)
        }
    }

    // MARK: - 异动

    private var anomalySection: some View {
        Section {
            ForEach(mockAnomalies, id: \.title) { item in
                HStack(spacing: 6) {
                    Text("⚠️").font(.system(size: 10))
                    Text(item.title).font(.system(size: 11))
                    Spacer()
                    Text(item.time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 1)
            }
        } header: {
            Label("异动 (\(mockAnomalies.count))", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    // MARK: - 训练

    // MARK: - 训练（v17.3 · 接 TrainingLogPersistence 真实数据）

    private var trainingSection: some View {
        Section {
            // 连胜/连败 streak
            let streak = trainingLog.currentStreak
            if streak.count >= 2 {
                HStack {
                    Text(streak.isWinning ? "🔥" : "💧")
                    Text("\(streak.isWinning ? "连胜" : "连败") \(streak.count) 次")
                        .font(.system(size: 12))
                    Spacer()
                }
            }
            // 本月均分
            if let avg = thisMonthAvg {
                HStack {
                    Text("📊")
                    Text("本月均分 \(avg)")
                        .font(.system(size: 12))
                    Spacer()
                }
            }
            // 训练总次数
            HStack {
                Text("🎯")
                Text("累计 \(trainingLog.sessions.count) 次训练")
                    .font(.system(size: 12))
                Spacer()
            }
            // 下次专项（v16.213 加的 focusDimension）
            if let dim = focusDimension {
                HStack {
                    Text("🎯")
                    Text("下次专项: \(dim)")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Spacer()
                }
            }
            if trainingLog.sessions.isEmpty {
                Text("尚未开始训练 · 主区切到 🎯 训练模块")
                    .font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Label("训练", systemImage: "target")
                .foregroundColor(.green)
        }
    }

    /// 本月均分（仅含 v2 score · 与 HistoryPanel 同算法）
    private var thisMonthAvg: Int? {
        let cal = Calendar(identifier: .gregorian)
        guard let monthStart = cal.dateInterval(of: .month, for: Date())?.start else { return nil }
        let scores = trainingLog.sessions
            .filter { $0.endedAt >= monthStart }
            .compactMap { trainingLog.score(for: $0.id)?.totalScore }
        guard !scores.isEmpty else { return nil }
        return Int(round(Double(scores.reduce(0, +)) / Double(scores.count)))
    }

    /// v16.213 专项维度（@AppStorage 读 raw → 中文）
    private var focusDimension: String? {
        guard let raw = UserDefaults.standard.string(forKey: "viewState.v1.training.focusDimension"),
              !raw.isEmpty,
              let dim = TrainingSubScores.Dimension(rawValue: raw) else { return nil }
        return "\(dim.emoji) \(dim.displayName)"
    }
}

// MARK: - Mock 数据（v17.0 PoC Step 6 · v17.1+ 接真实 ViewModel）

private struct WatchItem { let symbol: String; let price: String; let change: String }
private struct SectorItem { let emoji: String; let name: String; let change: String }
private struct AnomalyItem { let title: String; let time: String }

private let mockWatchlist: [WatchItem] = [
    WatchItem(symbol: "rb2510",   price: "3225",   change: "+0.78%"),
    WatchItem(symbol: "IF2509",   price: "3870",   change: "-0.52%"),
    WatchItem(symbol: "i2510",    price: "780.5",  change: "+1.23%"),
    WatchItem(symbol: "ag2510",   price: "8520",   change: "+0.31%"),
    WatchItem(symbol: "MA2510",   price: "2450",   change: "-0.18%"),
]

private let mockSectors: [SectorItem] = [
    SectorItem(emoji: "⚙️", name: "黑色",   change: "+0.65%"),
    SectorItem(emoji: "🔧", name: "有色",   change: "+0.20%"),
    SectorItem(emoji: "🌾", name: "农产品", change: "-0.42%"),
    SectorItem(emoji: "🛢", name: "能化",   change: "+0.88%"),
]

private let mockAnomalies: [AnomalyItem] = [
    AnomalyItem(title: "螺纹突破阻力", time: "14:23"),
    AnomalyItem(title: "原油持续单边", time: "14:18"),
    AnomalyItem(title: "价差异常扩大", time: "13:55"),
]

#endif
