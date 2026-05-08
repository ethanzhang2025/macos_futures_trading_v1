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
    let onBollToggle: () -> Void
    let onSARToggle: () -> Void
    let onIntegerLevelsToggle: () -> Void
    let onLimitLinesToggle: () -> Void
    let onVWAPToggle: () -> Void
    let onFibonacciToggle: () -> Void
    let onPivotPointsToggle: () -> Void
    let onSubChartTap: (MultiChartSubChartType) -> Void
    let onTimeShareToggle: () -> Void
    let onPushToMain: () -> Void

    static let instrumentPool: [String] = [
        "RB0", "IF0", "AU0", "CU0", "I0", "MA0",
        "AG0", "TA0", "ZN0", "AL0",
    ]

    static let periodPool: [KLinePeriod] = [
        .minute1, .minute5, .minute15, .minute30, .hour1, .hour4, .daily,
    ]

    /// v15.23 batch96 · 合约中文别名（trader 直观识别 · "螺纹" 比 "RB0" 更熟悉）
    /// 主连续 + 主流商品 · 老用户合约符号也保留（hover 显示中文 + 代号）
    static let instrumentDisplayName: [String: String] = [
        "RB0": "螺纹钢",
        "IF0": "沪深 300",
        "AU0": "黄金",
        "CU0": "沪铜",
        "I0": "铁矿石",
        "MA0": "甲醇",
        "AG0": "白银",
        "TA0": "PTA",
        "ZN0": "沪锌",
        "AL0": "沪铝",
    ]

    @State private var liveBars: [KLine] = []
    @State private var dataState: MultiChartCellDataState = .loading
    /// v15.23 batch71 · 链式串行写 cache（保 K 线时间序 · 避免 race condition · 同 ChartScene 模式）
    @State private var klineSaveTask: Task<Void, Never>? = nil
    /// v15.23 batch90 · 真行情最近一次更新时间（snapshot / completedBar 时刷新 · trader 看行情新鲜度）
    @State private var lastUpdateTime: Date? = nil

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
                showIndicators: state.showIndicators,
                showBoll: state.showBoll,
                subChart: state.subChart,
                showSAR: state.showSAR,
                horizontalLines: state.horizontalLines,
                isTimeShareMode: state.isTimeShareMode,
                showIntegerLevels: state.showIntegerLevels,
                showLimitLines: state.showLimitLines,
                showVWAP: state.showVWAP,
                showFibonacci: state.showFibonacci,
                showPivotPoints: state.showPivotPoints
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
                lastUpdateTime = Date()
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
                lastUpdateTime = Date()
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
            // v15.23 batch156 · 锁定 cell 视觉指示（左侧 lock icon）
            if state.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .help("已锁定 · 右键解锁")
            }
            Menu {
                ForEach(Self.instrumentPool, id: \.self) { id in
                    Button {
                        onContractTap(id)
                    } label: {
                        // batch96 · "RB0  螺纹钢" 双显示 · trader 一眼对应代号 + 品种
                        if let cn = Self.instrumentDisplayName[id] {
                            Text("\(id)  \(cn)")
                        } else {
                            Text(id)
                        }
                    }
                }
            } label: {
                Text(state.instrumentID)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 40)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 60)
            .help("切换合约（当前：\(Self.instrumentDisplayName[state.instrumentID] ?? state.instrumentID) · \(state.instrumentID)）")

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

            // v15.23 batch90 · 数据新鲜度（"5s 前" / "停滞"红 · trader 监控真行情连接质量）
            if let fresh = freshnessText {
                Text(fresh)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(freshnessColor)
                    .help("距上一次行情更新（snapshot / completedBar）的时长 · > 5 分钟标红警告")
            }

            // v15.23 batch83 · 末根 K 线倒计时（短周期 trader 节奏感 · 仅真行情 + ≤1h 周期）
            if let cd = countdownText {
                Text("⏱\(cd)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .help("距下根 \(state.period.rawValue) K 线 close（按本地系统时间对齐周期边界）")
            }

            Spacer()

            // batch103 · 综合多空评级（短促 emoji + 中文 · trader 一眼判断方向）
            bullRatingLabel

            lastPriceText

            // v15.23 batch79 · 副图 picker（量/KDJ/无 · 替换原 showVolume toggle · 兼容老配置）
            Menu {
                ForEach(MultiChartSubChartType.allCases, id: \.self) { sub in
                    Button {
                        onSubChartTap(sub)
                    } label: {
                        if state.subChart == sub {
                            Label(sub.displayName, systemImage: "checkmark")
                        } else {
                            Text(sub.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: subChartIcon)
                    .font(.system(size: 11))
                    .foregroundColor(state.subChart == .none ? .secondary : .accentColor)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("副图：\(state.subChart.displayName)（点击切换 量 / KDJ / 无）")

            // v15.23 batch93 · K 线 ⇋ 分时折线切换（trader 真盘工具）
            Button {
                onTimeShareToggle()
            } label: {
                Image(systemName: state.isTimeShareMode ? "waveform" : "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(state.isTimeShareMode ? .red.opacity(0.85) : .secondary)
            }
            .buttonStyle(.borderless)
            .help(state.isTimeShareMode ? "切回 K 线（蜡烛图）" : "切到分时折线（trader 真盘看图）")

            // v15.23 batch88 · 主图指标 Menu 收纳（MA 4 均线 / BOLL / SAR 三选多 · 减少 toolbar 拥挤）
            Menu {
                Button {
                    onIndicatorsToggle()
                } label: {
                    Label("MA 5/10/20/60 四均线", systemImage: state.showIndicators ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onBollToggle()
                } label: {
                    Label("BOLL 上下轨（20 · 2σ）", systemImage: state.showBoll ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onSARToggle()
                } label: {
                    Label("SAR 抛物线（0.02/0.2）", systemImage: state.showSAR ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onIntegerLevelsToggle()
                } label: {
                    Label("整数关口辅助线", systemImage: state.showIntegerLevels ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onLimitLinesToggle()
                } label: {
                    Label("涨跌停参考线（±10%）", systemImage: state.showLimitLines ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onVWAPToggle()
                } label: {
                    Label("VWAP 成交量加权均价", systemImage: state.showVWAP ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onFibonacciToggle()
                } label: {
                    Label("Fibonacci 黄金回撤", systemImage: state.showFibonacci ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    onPivotPointsToggle()
                } label: {
                    Label("Pivot Points (R2/R1/PP/S1/S2)",
                          systemImage: state.showPivotPoints ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: indicatorMenuIcon)
                    .font(.system(size: 11))
                    .foregroundColor(indicatorMenuColor)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("主图指标：MA \(state.showIndicators ? "✓" : "⬜") · BOLL \(state.showBoll ? "✓" : "⬜") · SAR \(state.showSAR ? "✓" : "⬜")")

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

    /// v15.23 batch90 · 真行情数据新鲜度（lastUpdateTime → "5s 前" / "停滞" · trader 监控行情连接）
    private var freshnessText: String? {
        guard dataState == .live, let lastUpdate = lastUpdateTime else { return nil }
        _ = tickSeed  // 让 view body 每秒重渲触发刷新
        let elapsed = Int(Date().timeIntervalSince(lastUpdate))
        if elapsed < 10 {
            return "\(elapsed)s 前"
        } else if elapsed < 60 {
            return "\(elapsed)s 前"
        } else if elapsed < 300 {
            return "\(elapsed / 60)m 前"
        } else {
            return "停滞"  // 5 分钟无更新 · 行情可能断
        }
    }

    private var freshnessColor: Color {
        guard dataState == .live, let lastUpdate = lastUpdateTime else { return .secondary }
        _ = tickSeed
        let elapsed = Int(Date().timeIntervalSince(lastUpdate))
        if elapsed < 10 { return .green.opacity(0.8) }
        if elapsed < 30 { return .secondary }
        if elapsed < 300 { return .orange.opacity(0.8) }
        return .red.opacity(0.85)  // 停滞警告
    }

    /// v15.23 batch83 · 末根 K 线倒计时（短周期节奏感 · 仅 .live 真行情 + 周期 < 2h 时显示）
    /// 计算：next_bar_open = ceil(now / period_sec) × period_sec · remaining = next - now
    private var countdownText: String? {
        guard dataState == .live else { return nil }
        let periodSec = state.period.seconds
        // 仅短周期显示（1m/3m/5m/15m/30m/1h）· 4h+ 倒计时太长无意义
        guard periodSec >= 60, periodSec <= 3600 else { return nil }
        // 注：参与 tickSeed 引用 · 让 view body 每秒重渲触发倒计时刷新
        _ = tickSeed
        let now = Date().timeIntervalSince1970
        let pSec = Double(periodSec)
        let nextBar = (now / pSec).rounded(.up) * pSec
        let remaining = max(0, Int(nextBar - now))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    /// v15.23 batch88 · 主图指标 Menu icon + 颜色（任一指标开则高亮）
    private var indicatorMenuIcon: String {
        // 任一指标开 → 上升趋势线图标（强调"有指标"）· 全关 → 平线
        let anyOn = state.showIndicators || state.showBoll || state.showSAR
        return anyOn ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis"
    }

    private var indicatorMenuColor: Color {
        // 全关 → 灰 · 部分开 → secondary accent · 全开 → 亮 accent
        let count = (state.showIndicators ? 1 : 0)
                  + (state.showBoll ? 1 : 0)
                  + (state.showSAR ? 1 : 0)
                  + (state.showIntegerLevels ? 1 : 0)
                  + (state.showLimitLines ? 1 : 0)
                  + (state.showVWAP ? 1 : 0)
                  + (state.showFibonacci ? 1 : 0)
        switch count {
        case 0: return .secondary
        case 1...3: return .accentColor.opacity(0.75)
        default: return .accentColor
        }
    }

    /// v15.23 batch79-95 · 副图 Menu icon（按当前选择切换图标）
    private var subChartIcon: String {
        switch state.subChart {
        case .none: return "chart.bar"
        case .volume: return "chart.bar.fill"
        case .kdj: return "waveform.path.ecg"
        case .macd: return "chart.xyaxis.line"
        case .rsi: return "gauge.with.dots.needle.50percent"
        case .oi: return "person.3.fill"
        case .atr: return "tornado"
        case .cci: return "arrow.up.arrow.down"
        case .wr: return "arrow.left.and.right"
        }
    }

    /// v15.23 batch103 · 综合多空评级（依赖 effectiveBars · 末根综合 MA/KDJ/MACD）
    @ViewBuilder
    private var bullRatingLabel: some View {
        let bars = effectiveBars
        if bars.count >= 61 {
            let score = MultiChartHost.bullScoreAt(bars: bars, idx: bars.count - 1)
            if score >= 0 {
                let r = MultiChartHost.bullRatingLabel(score: score)
                Text("\(r.emoji)\(r.text)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(r.color)
                    .help("综合 7 项指标多空评级（\(score)/7）：MA20/MA60 位置 · 多头排列 · KDJ 多头 · MACD 金叉")
            }
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
