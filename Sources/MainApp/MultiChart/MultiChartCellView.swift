// WP-44 v15.23 batch70 · 多图表 cell view（每 cell 独立 MarketDataPipeline · 真行情 + Mock 兜底）
//
// 设计要点：
// - 每 cell 独立 pipeline · `.task(id: pipelineKey)` 在 instrumentID/period 变化时自动取消并重启
// - liveBars 拉到 → 真行情 (Sina) · liveBars 空 → Mock 兜底（autoTick 注入末根抖动）
// - dataSource 状态点：🟢 Sina 真行情 / 🟡 Mock 兜底 / ⚪️ 加载中
// - bars 实时回传 host（hoverOHLCText / 跨 cell 联动用真数据）
//
// 不接 ChartCore Metal · 复用 MultiChartCellCanvas · 6 cell 同屏不卡

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import DataCore

enum MultiChartCellDataState: Equatable {
    case loading
    case live      // 真行情（Sina pipeline 给了非空 snapshot）
    case mock      // Mock 兜底（pipeline 拉空 / 不支持的合约）
}

struct MultiChartCellView: View {

    let state: MultiChartCellState
    let idx: Int
    let autoTickEnabled: Bool
    let tickSeed: UInt64
    let sharedHoveredIndex: Int?
    let onHoverIndexChange: (Int?) -> Void
    /// 上报当前 cell 的有效 bars（host 用作 hoverOHLCText 数据源）
    let onBarsChange: (UUID, [KLine]) -> Void
    let onContractTap: (String) -> Void
    let onPeriodTap: (KLinePeriod) -> Void
    let onVolumeToggle: () -> Void
    let onPushToMain: () -> Void

    static let instrumentPool: [String] = [
        "RB0", "IF0", "AU0", "CU0", "I0", "MA0",
        "AG0", "TA0", "ZN0", "AL0",
    ]

    static let periodPool: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30, .hour1, .hour4, .daily,
    ]

    @State private var liveBars: [KLine] = []
    @State private var dataState: MultiChartCellDataState = .loading

    /// 真行情拉到则用真数据 · 否则 Mock 兜底（autoTick 让末根 K 线抖动）
    private var effectiveBars: [KLine] {
        if !liveBars.isEmpty { return liveBars }
        return MultiChartMockData.bars(
            instrumentID: state.instrumentID,
            period: state.period,
            tickSeed: autoTickEnabled ? tickSeed : 0
        )
    }

    /// pipeline 重启 key · instrumentID/period 任一变化即取消旧 task · 启动新 pipeline
    private var pipelineKey: String {
        "\(state.instrumentID)|\(state.period.rawValue)"
    }

    var body: some View {
        VStack(spacing: 0) {
            cellToolbar
            MultiChartCellCanvas(
                bars: effectiveBars,
                showVolume: state.showVolume,
                hoveredIndex: sharedHoveredIndex,
                onHoverIndexChange: onHoverIndexChange
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
        .cornerRadius(4)
        .task(id: pipelineKey) {
            await streamRealMarket()
        }
        .onAppear {
            onBarsChange(state.id, effectiveBars)
        }
        .onChange(of: liveBars.count) { _ in
            onBarsChange(state.id, effectiveBars)
        }
        .onChange(of: tickSeed) { _ in
            // mock 兜底时末根抖动 · 让 host hoverOHLC 跟随
            if dataState == .mock {
                onBarsChange(state.id, effectiveBars)
            }
        }
        .onChange(of: pipelineKey) { _ in
            // 合约/周期切换 · 立即上报新 mock（pipeline 真数据回来后 onChange(liveBars) 再上报）
            onBarsChange(state.id, effectiveBars)
        }
    }

    // MARK: - 真行情 stream（每 cell 独立 pipeline · .task 自动取消重启）

    @MainActor
    private func streamRealMarket() async {
        liveBars = []
        dataState = .loading
        // 不支持的合约直接走 Mock · 不创建 pipeline 浪费网络
        guard MarketDataPipeline.supportedContracts.contains(state.instrumentID) else {
            dataState = .mock
            return
        }
        let pipe = MarketDataPipeline(instrumentID: state.instrumentID, period: state.period)
        let stream = await pipe.start()
        var snapshotReceived = false
        // .task(id:) 取消（cell 销毁 / 切合约/周期）→ task isCancelled true · 检查后 break 出循环走 pipe.stop()
        // stream 不 emit 时无法立即响应 cancel · 可接受 · 下次 polling tick 会到 emit 后退出
        for await update in stream {
            if Task.isCancelled { break }
            switch update {
            case .snapshot(let bars):
                if bars.isEmpty && !snapshotReceived {
                    dataState = .mock
                    continue
                }
                snapshotReceived = true
                liveBars = bars
                dataState = .live
            case .completedBar(let bar):
                liveBars.append(bar)
                if dataState != .live { dataState = .live }
            }
        }
        await pipe.stop()
    }

    // MARK: - Toolbar（合约 / 周期 / 数据状态点 / 末根价 / 量开关 / 推主图）

    private var cellToolbar: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(Self.instrumentPool, id: \.self) { id in
                    Button(id) { onContractTap(id) }
                }
            } label: {
                Text(state.instrumentID)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 40)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 60)
            .help("切换合约")

            Menu {
                ForEach(Self.periodPool, id: \.self) { p in
                    Button(p.rawValue) { onPeriodTap(p) }
                }
            } label: {
                Text(state.period.rawValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 50)
            .help("切换周期")

            dataStateDot

            Spacer()

            lastPriceText

            Button {
                onVolumeToggle()
            } label: {
                Image(systemName: state.showVolume ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help(state.showVolume ? "隐藏成交量" : "显示成交量")

            Button {
                onPushToMain()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("在主图打开 \(state.instrumentID)（深入分析 · 完整指标/画线/复盘）")

            Text("#\(idx + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
    }

    /// 数据状态指示点（hover tooltip 解释来源）
    @ViewBuilder
    private var dataStateDot: some View {
        switch dataState {
        case .loading:
            Circle()
                .fill(Color.gray)
                .frame(width: 6, height: 6)
                .help("加载中…")
        case .live:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .help("Sina 真行情（实时轮询）")
        case .mock:
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)
                .help("Mock 兜底（行情不可达 / 合约暂不支持 · 仅 UI 演示）")
        }
    }

    /// 末根 K 线 close · 涨红跌绿
    @ViewBuilder
    private var lastPriceText: some View {
        let bars = effectiveBars
        if let last = bars.last {
            let close = (last.close as NSDecimalNumber).doubleValue
            let prev = bars.count >= 2 ? (bars[bars.count - 2].close as NSDecimalNumber).doubleValue : close
            let isUp = close >= prev
            Text(String(format: "%.2f", close))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isUp ? .red : .green)
        }
    }
}

#endif
