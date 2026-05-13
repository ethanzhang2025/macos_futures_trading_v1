// v17.156 · 主图 9 overlay IncrementalState 聚合（ChartIndicatorRunner overlay 增量化核心）
//
// 背景（v17.139 性能瓶颈）：
// - 之前 ChartIndicatorRunner.step(newBar) 每根做 MainChartOverlayCompute.compute(historyBars+newBar, book) 全量重算
// - 5kbars 9 overlay ≈ 50ms / 根 · 8× 回放速度热路径 trader 卡顿
//
// v17.155 已给 9 个 overlay 全部加 IncrementalIndicator（之前 8 个已有 · SAR + 新版 SuperTrend 本批补齐）。
// 本类聚合 9 个 state · 单根 step O(period) 或 O(1) · 总成本预期降 10×（→ ~5ms/根）。
//
// 列顺序与 MainChartOverlayCompute.compute 完全一致（绑定 trader 已认的 HUD 渲染顺序）：
//   if vwap          → [VWAP]                                                   1 列
//   if pivot         → [P, R1, S1, R2, S2]      （drop R3/S3 · v17.150）         5 列
//   if superTrend    → [SUPERTREND]             （drop SUPERTREND-DIR）         1 列
//   if ichimoku      → [TENKAN, KIJUN, SENKOU-A, SENKOU-B]  （drop CHIKOU）     4 列
//   if sar           → [SAR]                                                    1 列
//   if priceChannel  → [PC-UPPER, PC-LOWER]                                     2 列
//   if envelopes     → [ENV-MID, ENV-UPPER, ENV-LOWER]                          3 列
//   if donchian      → [DC-UPPER, DC-MID, DC-LOWER]                             3 列
//   if keltner       → [KC-UPPER, KC-MID, KC-LOWER]（KC step 返回顺序 mid/upper/lower · 此处重排）3 列
//
// 9 全开 = 23 列。

import Foundation
import Shared
import IndicatorCore

// MARK: - v17.139 → v17.156 · 主图 overlay 全量计算（prime 路径 · 已从 ChartScene.swift 移出 · Linux 跨平台）
//
// 用途：ChartIndicatorRunner.prime 一次性建 overlay 初始 series（步入历史末尾的全量列）· step 路径走 OverlayIncrementalStates.step
// 列顺序与 OverlayIncrementalStates.step 完全对齐（详见该结构体注释表）
// SuperTrend-DIR / Pivot R3/S3 / Ichimoku CHIKOU 在此过滤 · 与 trader HUD 实际渲染列一致

enum MainChartOverlayCompute {

    static func compute(bars: [KLine], book: MainChartOverlayBook) -> [IndicatorSeries] {
        guard book.anyEnabled, !bars.isEmpty else { return [] }
        let kline = KLineSeries(
            opens: bars.map(\.open),
            highs: bars.map(\.high),
            lows: bars.map(\.low),
            closes: bars.map(\.close),
            volumes: bars.map(\.volume),
            openInterests: bars.map { _ in 0 }
        )
        var out: [IndicatorSeries] = []
        if book.isEnabled(.vwap) {
            out.append(contentsOf: (try? VWAP.calculate(kline: kline, params: [])) ?? [])
        }
        if book.isEnabled(.pivot) {
            let result = (try? PivotPoints.calculate(kline: kline, params: [])) ?? []
            // v17.150 · 只取 5 线 P/R1/S1/R2/S2（IndicatorCore 输出 7 列含 R3/S3 极端阈值 · trader HUD 5 行更紧凑）
            let kept: Set<String> = ["P", "R1", "S1", "R2", "S2"]
            out.append(contentsOf: result.filter { kept.contains($0.name) })
        }
        if book.isEnabled(.superTrend) {
            let result = (try? SuperTrend.calculate(
                kline: kline,
                params: [Decimal(book.superTrendPeriod), book.superTrendMultiplier]
            )) ?? []
            // drop SUPERTREND-DIR（trader HUD 不需方向 ±1 数字 · 后续渲染层可独立读取色彩区分）
            if let st = result.first(where: { $0.name == "SUPERTREND" }) {
                out.append(st)
            }
        }
        if book.isEnabled(.ichimoku) {
            let result = (try? Ichimoku.calculate(
                kline: kline,
                params: [Decimal(book.ichimokuTenkan), Decimal(book.ichimokuKijun), Decimal(book.ichimokuSenkou)]
            )) ?? []
            // 输出 4 主线 · v17.161 toggle 开时再加 CHIKOU 第 5 列（close 后移 kijun 根 · 滞后线 trader 高级用户）
            for name in ["TENKAN", "KIJUN", "SENKOU-A", "SENKOU-B"] {
                if let s = result.first(where: { $0.name == name }) {
                    out.append(s)
                }
            }
            if book.ichimokuShowChikou {
                if let s = result.first(where: { $0.name == "CHIKOU" }) {
                    out.append(s)
                }
            }
        }
        if book.isEnabled(.sar) {
            out.append(contentsOf: (try? SAR.calculate(kline: kline, params: [book.sarStep, book.sarMax])) ?? [])
        }
        if book.isEnabled(.priceChannel) {
            out.append(contentsOf: (try? PriceChannel.calculate(kline: kline, params: [Decimal(book.priceChannelPeriod)])) ?? [])
        }
        if book.isEnabled(.envelopes) {
            out.append(contentsOf: (try? Envelopes.calculate(kline: kline, params: [Decimal(book.envelopesPeriod), book.envelopesPercent])) ?? [])
        }
        if book.isEnabled(.donchian) {
            let result = (try? Donchian.calculate(kline: kline, params: [Decimal(book.donchianPeriod)])) ?? []
            for name in ["DC-UPPER", "DC-MID", "DC-LOWER"] {
                if let s = result.first(where: { $0.name == name }) {
                    out.append(s)
                }
            }
        }
        if book.isEnabled(.keltner) {
            let result = (try? KC.calculate(
                kline: kline,
                params: [Decimal(book.keltnerEMA), Decimal(book.keltnerATR), book.keltnerMultiplier]
            )) ?? []
            for name in ["KC-UPPER", "KC-MID", "KC-LOWER"] {
                if let s = result.first(where: { $0.name == name }) {
                    out.append(s)
                }
            }
        }
        // v17.159 · 3 改进型均线（HMA / DEMA / TEMA · 各 1 列 · 顺序追加末尾）
        if book.isEnabled(.hma) {
            out.append(contentsOf: (try? HMA.calculate(kline: kline, params: [Decimal(book.hmaPeriod)])) ?? [])
        }
        if book.isEnabled(.dema) {
            out.append(contentsOf: (try? DEMA.calculate(kline: kline, params: [Decimal(book.demaPeriod)])) ?? [])
        }
        if book.isEnabled(.tema) {
            out.append(contentsOf: (try? TEMA.calculate(kline: kline, params: [Decimal(book.temaPeriod)])) ?? [])
        }
        return out
    }
}

struct OverlayIncrementalStates {

    var vwap: VWAP.IncrementalState?
    var pivot: PivotPoints.IncrementalState?
    var superTrend: SuperTrend.IncrementalState?
    var ichimoku: Ichimoku.IncrementalState?
    var sar: SAR.IncrementalState?
    var priceChannel: PriceChannel.IncrementalState?
    var envelopes: Envelopes.IncrementalState?
    var donchian: Donchian.IncrementalState?
    var keltner: KC.IncrementalState?
    // v17.159 · 3 改进型均线
    var hma: HMA.IncrementalState?
    var dema: DEMA.IncrementalState?
    var tema: TEMA.IncrementalState?
    // v17.161 · CHIKOU 滞后渲染需要的状态（用于 ChartIndicatorRunner.step 退避填充）
    var ichimokuShowChikou: Bool = false
    var ichimokuKijun: Int = 0

    /// 用 history KLine 序列消化每个启用 overlay 的 state · 完成后 step(newBar) 输出当前根
    /// makeIncrementalState 失败（try? = nil · 参数非法等）→ 该 overlay 在 step 时跳过 · 与 MainChartOverlayCompute.compute 同款 `?? []` 行为对齐
    init(history: KLineSeries, book: MainChartOverlayBook) {
        if book.isEnabled(.vwap) {
            vwap = try? VWAP.makeIncrementalState(kline: history, params: [])
        }
        if book.isEnabled(.pivot) {
            pivot = try? PivotPoints.makeIncrementalState(kline: history, params: [])
        }
        if book.isEnabled(.superTrend) {
            superTrend = try? SuperTrend.makeIncrementalState(
                kline: history,
                params: [Decimal(book.superTrendPeriod), book.superTrendMultiplier]
            )
        }
        if book.isEnabled(.ichimoku) {
            ichimoku = try? Ichimoku.makeIncrementalState(
                kline: history,
                params: [Decimal(book.ichimokuTenkan), Decimal(book.ichimokuKijun), Decimal(book.ichimokuSenkou)]
            )
            ichimokuShowChikou = book.ichimokuShowChikou
            ichimokuKijun = book.ichimokuKijun
        }
        if book.isEnabled(.sar) {
            sar = try? SAR.makeIncrementalState(
                kline: history,
                params: [book.sarStep, book.sarMax]
            )
        }
        if book.isEnabled(.priceChannel) {
            priceChannel = try? PriceChannel.makeIncrementalState(
                kline: history,
                params: [Decimal(book.priceChannelPeriod)]
            )
        }
        if book.isEnabled(.envelopes) {
            envelopes = try? Envelopes.makeIncrementalState(
                kline: history,
                params: [Decimal(book.envelopesPeriod), book.envelopesPercent]
            )
        }
        if book.isEnabled(.donchian) {
            donchian = try? Donchian.makeIncrementalState(
                kline: history,
                params: [Decimal(book.donchianPeriod)]
            )
        }
        if book.isEnabled(.keltner) {
            keltner = try? KC.makeIncrementalState(
                kline: history,
                params: [Decimal(book.keltnerEMA), Decimal(book.keltnerATR), book.keltnerMultiplier]
            )
        }
        // v17.159 · 3 改进型均线
        if book.isEnabled(.hma) {
            hma = try? HMA.makeIncrementalState(kline: history, params: [Decimal(book.hmaPeriod)])
        }
        if book.isEnabled(.dema) {
            dema = try? DEMA.makeIncrementalState(kline: history, params: [Decimal(book.demaPeriod)])
        }
        if book.isEnabled(.tema) {
            tema = try? TEMA.makeIncrementalState(kline: history, params: [Decimal(book.temaPeriod)])
        }
    }

    /// 推进 1 根新 K · 输出顺序与 MainChartOverlayCompute.compute(bars).flatMap(\.values.last) 完全一致
    /// 各 overlay 的 state 推进 O(period) 或 O(1) · 总成本与启用数线性
    mutating func step(newBar: KLine) -> [Decimal?] {
        var out: [Decimal?] = []

        if var s = vwap {
            let row = VWAP.stepIncremental(state: &s, newBar: newBar)
            vwap = s
            out.append(row[0])
        }
        if var s = pivot {
            let row = PivotPoints.stepIncremental(state: &s, newBar: newBar)
            pivot = s
            // PivotPoints stepIncremental 输出 [P, R1, S1, R2, S2, R3, S3] · 7 列 · 取前 5（drop R3/S3 · v17.150）
            out.append(row[0])
            out.append(row[1])
            out.append(row[2])
            out.append(row[3])
            out.append(row[4])
        }
        if var s = superTrend {
            let row = SuperTrend.stepIncremental(state: &s, newBar: newBar)
            superTrend = s
            // SuperTrend stepIncremental 输出 [SUPERTREND, SUPERTREND-DIR] · 只取主线 drop DIR
            out.append(row[0])
        }
        if var s = ichimoku {
            let row = Ichimoku.stepIncremental(state: &s, newBar: newBar)
            ichimoku = s
            // Ichimoku stepIncremental 输出 [TENKAN, KIJUN, SENKOU-A, SENKOU-B, CHIKOU(nil)]
            // v17.161 · showChikou 开时输出 5 列 · 5th = nil（CHIKOU 用未来 close · 增量永远 nil）
            //          实际渲染：ChartIndicatorRunner.step 用本根 close 退避填到 (newLen-1-kijun) 位置 · 模拟全量 shiftBackward
            out.append(row[0])
            out.append(row[1])
            out.append(row[2])
            out.append(row[3])
            if ichimokuShowChikou {
                out.append(row[4])   // 永远 nil（来自 Ichimoku.stepIncremental · 用 shiftForward 后空 CHIKOU 位）
            }
        }
        if var s = sar {
            let row = SAR.stepIncremental(state: &s, newBar: newBar)
            sar = s
            out.append(row[0])
        }
        if var s = priceChannel {
            let row = PriceChannel.stepIncremental(state: &s, newBar: newBar)
            priceChannel = s
            // PriceChannel stepIncremental 输出 [PC-UPPER, PC-LOWER] · 2 列
            out.append(row[0])
            out.append(row[1])
        }
        if var s = envelopes {
            let row = Envelopes.stepIncremental(state: &s, newBar: newBar)
            envelopes = s
            // Envelopes stepIncremental 输出 [ENV-MID, ENV-UPPER, ENV-LOWER] · 3 列
            out.append(row[0])
            out.append(row[1])
            out.append(row[2])
        }
        if var s = donchian {
            let row = Donchian.stepIncremental(state: &s, newBar: newBar)
            donchian = s
            // Donchian stepIncremental 输出 [DC-UPPER, DC-MID, DC-LOWER] · 3 列
            out.append(row[0])
            out.append(row[1])
            out.append(row[2])
        }
        if var s = keltner {
            let row = KC.stepIncremental(state: &s, newBar: newBar)
            keltner = s
            // KC stepIncremental 输出 [KC-MID, KC-UPPER, KC-LOWER] · MainChartOverlayCompute 重排为 [UPPER, MID, LOWER]
            out.append(row[1])
            out.append(row[0])
            out.append(row[2])
        }
        // v17.159 · 3 改进型均线（HMA / DEMA / TEMA 各 1 列）· 顺序与 compute 末尾追加一致
        if var s = hma {
            out.append(HMA.stepIncremental(state: &s, newBar: newBar)[0])
            hma = s
        }
        if var s = dema {
            out.append(DEMA.stepIncremental(state: &s, newBar: newBar)[0])
            dema = s
        }
        if var s = tema {
            out.append(TEMA.stepIncremental(state: &s, newBar: newBar)[0])
            tema = s
        }
        return out
    }
}
