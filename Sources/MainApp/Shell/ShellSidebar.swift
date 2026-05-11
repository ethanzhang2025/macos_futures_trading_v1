// MainApp · Shell · v17.0 PoC Step 6
// 左侧 Sidebar · 5 section（自选 / 板块 / 持仓 / 异动 / 训练）
// v17.0 用 mock 数据展示视觉 · v17.1+ 接真实 ViewModel

#if canImport(SwiftUI) && os(macOS)
import SwiftUI

struct ShellSidebar: View {
    @EnvironmentObject var shellVM: ShellViewModel

    var body: some View {
        List {
            watchlistSection
            sectorSection
            positionSection
            anomalySection
            trainingSection
        }
        .listStyle(.sidebar)
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

    // MARK: - 持仓速览

    private var positionSection: some View {
        Section {
            ForEach(mockPositions, id: \.symbol) { pos in
                HStack(spacing: 6) {
                    Text(pos.symbol)
                        .font(.system(size: 12, design: .monospaced))
                    Text(pos.direction == "多" ? "多" : "空")
                        .font(.system(size: 10))
                        .padding(.horizontal, 3)
                        .background((pos.direction == "多" ? Color.red : Color.green).opacity(0.2))
                        .cornerRadius(2)
                    Spacer()
                    Text(pos.pnl)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(pos.pnl.hasPrefix("+") ? .red : .green)
                }
                .padding(.vertical, 1)
            }
            if mockPositions.isEmpty {
                Text("无持仓").font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Label("持仓 (\(mockPositions.count))", systemImage: "briefcase.fill")
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

    private var trainingSection: some View {
        Section {
            HStack {
                Text("🔥")
                Text("连胜 7 次")
                    .font(.system(size: 12))
                Spacer()
            }
            HStack {
                Text("📊")
                Text("本月均分 82")
                    .font(.system(size: 12))
                Spacer()
            }
            HStack {
                Text("🎯")
                Text("下次专项: 纪律")
                    .font(.system(size: 12))
                Spacer()
            }
        } header: {
            Label("训练", systemImage: "target")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Mock 数据（v17.0 PoC Step 6 · v17.1+ 接真实 ViewModel）

private struct WatchItem { let symbol: String; let price: String; let change: String }
private struct SectorItem { let emoji: String; let name: String; let change: String }
private struct PositionItem { let symbol: String; let direction: String; let pnl: String }
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

private let mockPositions: [PositionItem] = [
    PositionItem(symbol: "rb2510", direction: "多", pnl: "+¥2,340"),
    PositionItem(symbol: "IF2509", direction: "空", pnl: "-¥420"),
]

private let mockAnomalies: [AnomalyItem] = [
    AnomalyItem(title: "螺纹突破阻力", time: "14:23"),
    AnomalyItem(title: "原油持续单边", time: "14:18"),
    AnomalyItem(title: "价差异常扩大", time: "13:55"),
]

#endif
