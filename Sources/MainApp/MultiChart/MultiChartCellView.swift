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
import StoreCore

enum MultiChartCellDataState: Equatable {
    case loading
    case live      // 真行情（Sina pipeline 给了非空 snapshot · 含本地缓存 fast path）
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
    let onIndicatorsToggle: () -> Void
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
    /// v15.23 batch71 · 链式串行写 cache（保 K 线时间序 · 避免 race condition · 同 ChartScene 模式）
    @State private var klineSaveTask: Task<Void, Never>? = nil

    /// v15.23 batch71 · K 线 cache · ChartScene 同款（重启秒回 + 真行情拉空时离线兜底）
    @Environment(\.storeManager) private var storeManager

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
                onHoverIndexChange: onHoverIndexChange,
                showIndicators: state.showIndicators
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
        let instrumentID = state.instrumentID
        let period = state.period
        // 不支持的合约直接走 Mock · 不创建 pipeline 浪费网络
        guard MarketDataPipeline.supportedContracts.contains(instrumentID) else {
            dataState = .mock
            return
        }
        // v15.23 batch71 · M5 cache fast path · 网络 fetch 前先 load 磁盘缓存 · 立即显示
        // ChartScene 同模式 · 协议返 [KLine] 非 Optional · 单层 try? · isEmpty 跳过空缓存
        if let store = storeManager?.kline,
           let cached = try? await store.load(instrumentID: instrumentID, period: period),
           !cached.isEmpty {
            liveBars = cached
            dataState = .live
        }
        let pipe = MarketDataPipeline(instrumentID: instrumentID, period: period)
        let stream = await pipe.start()
        var snapshotReceived = false
        // .task(id:) 取消（cell 销毁 / 切合约/周期）→ task isCancelled true · 检查后 break 出循环走 pipe.stop()
        // stream 不 emit 时无法立即响应 cancel · 可接受 · 下次 polling tick 会到 emit 后退出
        for await update in stream {
            if Task.isCancelled { break }
            switch update {
            case .snapshot(let snapBars):
                if snapBars.isEmpty && !snapshotReceived {
                    // 真行情拉空 · 无 cache → Mock 兜底 · 有 cache → 保留 cache 数据（仍 .live · 离线模式）
                    if liveBars.isEmpty {
                        dataState = .mock
                    }
                    continue
                }
                snapshotReceived = true
                liveBars = snapBars
                dataState = .live
                // M5 持久化：snapshot 后异步 save 全量 · 链式串行（前一个 task 完成后再写 · 同 ChartScene）
                if let store = storeManager?.kline {
                    let prev = klineSaveTask
                    klineSaveTask = Task {
                        await prev?.value
                        try? await store.save(snapBars, instrumentID: instrumentID, period: period)
                    }
                }
            case .completedBar(let bar):
                liveBars.append(bar)
                if dataState != .live { dataState = .live }
                // M5 持久化：完成的单根 K 线异步 append · maxBars 按 period 动态（v12.9）· 链式串行保 K 线时间序
                if let store = storeManager?.kline {
                    let prev = klineSaveTask
                    let maxBars = MarketDataPipeline.cacheMaxBars(for: period)
                    klineSaveTask = Task {
                        await prev?.value
                        try? await store.append([bar], instrumentID: instrumentID, period: period, maxBars: maxBars)
                    }
                }
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

            // v15.23 batch72 · MA 双均线开关（MA5 黄 / MA20 紫 · 短线标配）
            Button {
                onIndicatorsToggle()
            } label: {
                Image(systemName: state.showIndicators ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis")
                    .font(.system(size: 11))
                    .foregroundColor(state.showIndicators ? .accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(state.showIndicators ? "隐藏 MA5/10/20/60 四均线" : "显示 MA5/10/20/60 四均线（短线标配）")

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
                .help("Sina 真行情（实时轮询）/ 本地缓存（离线兜底）· 数据真实")
        case .mock:
            Circle()
                .fill(Color.yellow)
                .frame(width: 6, height: 6)
                .help("Mock 兜底（行情不可达 / 合约暂不支持 · 仅 UI 演示）")
        }
    }

    /// 末根 K 线 close · 涨红跌绿 + v15.23 batch76 区间涨跌幅
    @ViewBuilder
    private var lastPriceText: some View {
        let bars = effectiveBars
        if let last = bars.last, let first = bars.first {
            let close = (last.close as NSDecimalNumber).doubleValue
            let firstClose = (first.close as NSDecimalNumber).doubleValue
            let prev = bars.count >= 2 ? (bars[bars.count - 2].close as NSDecimalNumber).doubleValue : close
            let isUp = close >= prev
            let pct = firstClose > 0 ? (close - firstClose) / firstClose * 100 : 0
            let pctIsUp = pct >= 0
            HStack(spacing: 4) {
                Text(String(format: "%.2f", close))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isUp ? .red : .green)
                Text(String(format: "%+.2f%%", pct))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(pctIsUp ? .red.opacity(0.8) : .green.opacity(0.8))
                    .help("区间累计涨跌幅（(末根 close - 首根 close) / 首根 close）")
            }
        }
    }
}

#endif
