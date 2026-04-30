// MainApp · 副图区（MACD / KDJ · 枚举驱动 · SwiftUI Canvas）
//
// 共用：drawLine（yMap 闭包参数）+ drawDashLine（零轴 / 参考线）
// 分发：y 范围（MACD 上下对称 / KDJ 固定视野）· 直方图（仅 MACD）· 配色 · HUD 文字
//
// viewport 共享：父视图传 viewport · 父变即重渲染（SwiftUI 标准）
// 性能取舍：[Double?] 缓存（compute() 一次性 Decimal → Double 桥接）· 拖拽 60Hz drawChart 不再走 NSDecimalNumber bridge
// 扩展：加 RSI/DMA/VOL = SubIndicatorKind 加 case + compute()/draw 加分支即可

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import ChartCore
import IndicatorCore

// MARK: - 副图类型枚举（外部用）

enum SubIndicatorKind: String, CaseIterable, Identifiable, Sendable {
    case macd
    case kdj
    case rsi
    case volume

    var id: String { rawValue }

    /// 用当前参数生成 HUD 标题（用户改参数后立即更新 · 无参版本由调用方传 .default）
    func displayName(params: IndicatorParamsBook) -> String {
        switch self {
        case .macd:   return "MACD \(params.macdParams[0])/\(params.macdParams[1])/\(params.macdParams[2])"
        case .kdj:    return "KDJ \(params.kdjParams[0])/\(params.kdjParams[1])/\(params.kdjParams[2])"
        case .rsi:    return "RSI \(params.rsiPeriod)"
        case .volume: return "成交量"
        }
    }

    /// 短名（Picker 紧凑显示）
    var shortName: String {
        switch self {
        case .macd:   return "MACD"
        case .kdj:    return "KDJ"
        case .rsi:    return "RSI"
        case .volume: return "成交量"
        }
    }
}

// MARK: - 副图视图

struct SubChartView: View {

    // MARK: 配色（基色单源 · MACD/KDJ 别名指向相同基色，让维护时不漏改）

    static let bgColor       = Color(red: 0.07, green: 0.08, blue: 0.10)   // #11141A 同 K 线 clearColor
    static let zeroLineColor = Color.white.opacity(0.25)
    static let kdjGuideColor = Color.white.opacity(0.15)

    static let yellowColor   = Color(red: 1.00, green: 0.78, blue: 0.18)   // 短期/快线（DIF · K）
    static let purpleColor   = Color(red: 0.63, green: 0.42, blue: 0.83)   // 中期/慢线（DEA · D）
    static let blueColor     = Color(red: 0.30, green: 0.78, blue: 1.00)   // J 专用
    static let bullColor     = Color(red: 0.96, green: 0.27, blue: 0.27)   // 涨红
    static let bearColor     = Color(red: 0.18, green: 0.74, blue: 0.42)   // 跌绿

    // MACD 别名
    static let macdDifColor  = yellowColor
    static let macdDeaColor  = purpleColor
    static let macdBullColor = bullColor
    static let macdBearColor = bearColor

    // KDJ 别名
    static let kdjKColor = yellowColor
    static let kdjDColor = purpleColor
    static let kdjJColor = blueColor

    // KDJ 视野（J 极端到 ±50 不裁断 · 仅副图内部用）
    private static let kdjViewMin: CGFloat = -20
    private static let kdjViewMax: CGFloat = 120

    // RSI 视野（0~100 固定 · 70/30 超买超卖参考线）
    private static let rsiViewMin: CGFloat = 0
    private static let rsiViewMax: CGFloat = 100
    static let rsiLineColor    = yellowColor
    static let rsiGuideColor   = Color.white.opacity(0.15)

    // 成交量配色（涨红跌绿 · 与 K 线一致）
    static let volumeBullColor = bullColor
    static let volumeBearColor = bearColor
    static let volumeAxisColor = Color.white.opacity(0.15)

    let bars: [KLine]
    let viewport: RenderViewport
    let kind: SubIndicatorKind
    /// v15.2 自定义指标参数 · 由父级注入 · 改后通过 ComputeKey 触发重算
    let params: IndicatorParamsBook

    /// 三槽位（MACD: DIF/DEA/HIST · KDJ: K/D/J）
    /// compute() 末尾一次性 Decimal → Double 桥接 · 拖拽热路径直接读 Double，不再走 NSDecimalNumber
    @State private var seriesA: [Double?] = []
    @State private var seriesB: [Double?] = []
    @State private var seriesC: [Double?] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            Self.bgColor
            Canvas { ctx, size in drawChart(ctx, size: size) }
            hud
        }
        .task(id: ComputeKey(barCount: bars.count, kind: kind, params: params)) {
            await compute()
        }
    }

    /// 触发重算的复合 key（bars 增量 + 切副图 + 改参数都要重算）
    private struct ComputeKey: Equatable {
        let barCount: Int
        let kind: SubIndicatorKind
        let params: IndicatorParamsBook
    }

    // MARK: - 计算（按 kind 分发 · 后台 detached 跑 · 末尾一次性桥接 Decimal → Double）

    @MainActor
    private func compute() async {
        let snap = bars
        let kindCopy = kind
        let paramsCopy = params
        let result = await Task.detached(priority: .userInitiated) {
            let series = KLineSeries(
                opens: snap.map(\.open),
                highs: snap.map(\.high),
                lows: snap.map(\.low),
                closes: snap.map(\.close),
                volumes: snap.map(\.volume),
                openInterests: snap.map { _ in 0 }
            )
            switch kindCopy {
            case .macd:
                return (try? MACD.calculate(kline: series, params: paramsCopy.macdParamsDecimal)) ?? []
            case .kdj:
                return (try? KDJ.calculate(kline: series, params: paramsCopy.kdjParamsDecimal)) ?? []
            case .rsi:
                return (try? RSI.calculate(kline: series, params: paramsCopy.rsiParamsDecimal)) ?? []
            case .volume:
                return []  // 成交量直接读 bars · 不走 Indicator 计算
            }
        }.value

        switch kind {
        case .macd:
            seriesA = doublesOf(result, name: "DIF")
            seriesB = doublesOf(result, name: "DEA")
            seriesC = doublesOf(result, name: "MACD")
        case .kdj:
            seriesA = doublesOf(result, name: "K")
            seriesB = doublesOf(result, name: "D")
            seriesC = doublesOf(result, name: "J")
        case .rsi:
            // RSI 14 输出系列名通常就是 "RSI" 或 "RSI14" · 取首个 series
            let firstSeries = result.first?.values ?? []
            seriesA = firstSeries.map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = []
            seriesC = []
        case .volume:
            seriesA = bars.map { Double($0.volume) }  // 直接读 K 线 volume（Int → Double）
            seriesB = []
            seriesC = []
        }
    }

    private func doublesOf(_ result: [IndicatorSeries], name: String) -> [Double?] {
        let raw = result.first { $0.name == name }?.values ?? []
        return raw.map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
    }

    // MARK: - HUD（按 kind 分发文字）

    private var hud: some View {
        let visibleEnd = min(viewport.startIndex + viewport.visibleCount, bars.count) - 1
        let aLast = lastValue(seriesA, at: visibleEnd)
        let bLast = lastValue(seriesB, at: visibleEnd)
        let cLast = lastValue(seriesC, at: visibleEnd)

        // 视觉迭代第 12 项：副图 HUD 去 kind 名（工具条 segmented 已显示）· 仅数值 · 更紧凑
        return HStack(spacing: 8) {
            switch kind {
            case .macd:
                Text("DIF \(fmt(aLast))").foregroundColor(Self.macdDifColor)
                Text("DEA \(fmt(bLast))").foregroundColor(Self.macdDeaColor)
                Text("MACD \(fmt(cLast))").foregroundColor(
                    cLast.map { $0 >= 0 ? Self.macdBullColor : Self.macdBearColor } ?? .secondary
                )
            case .kdj:
                Text("K \(fmt(aLast))").foregroundColor(Self.kdjKColor)
                Text("D \(fmt(bLast))").foregroundColor(Self.kdjDColor)
                Text("J \(fmt(cLast))").foregroundColor(Self.kdjJColor)
            case .rsi:
                Text("RSI \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 70 ? Self.bullColor : ($0 <= 30 ? Self.bearColor : Self.rsiLineColor) } ?? .secondary
                )
            case .volume:
                Text("VOL \(fmtVolume(aLast))").foregroundColor(
                    visibleEnd >= 0 && visibleEnd < bars.count
                        ? (bars[visibleEnd].close >= bars[visibleEnd].open ? Self.volumeBullColor : Self.volumeBearColor)
                        : .secondary
                )
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .cornerRadius(4)
        .padding(8)
    }

    // MARK: - Canvas 绘制（按 kind 分发）

    private func drawChart(_ ctx: GraphicsContext, size: CGSize) {
        let visibleStart = viewport.startIndex
        let visibleCount = viewport.visibleCount
        let visibleEnd = min(visibleStart + visibleCount, bars.count)
        guard visibleEnd > visibleStart else { return }

        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)

        switch kind {
        case .macd:
            drawMACD(ctx, size: size,
                     visibleStart: visibleStart, visibleEnd: visibleEnd,
                     barWidth: barWidth, xOffset: xOffset)
        case .kdj:
            drawKDJ(ctx, size: size,
                    visibleStart: visibleStart, visibleEnd: visibleEnd,
                    barWidth: barWidth, xOffset: xOffset)
        case .rsi:
            drawRSI(ctx, size: size,
                    visibleStart: visibleStart, visibleEnd: visibleEnd,
                    barWidth: barWidth, xOffset: xOffset)
        case .volume:
            drawVolume(ctx, size: size,
                       visibleStart: visibleStart, visibleEnd: visibleEnd,
                       barWidth: barWidth, xOffset: xOffset)
        }
    }

    /// RSI：固定 0~100 视野（70/50/30 参考线 · 超买/中位/超卖）· 单线
    private func drawRSI(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.rsiViewMin
        let viewMax = Self.rsiViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(70), 50, 30] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: Self.rsiGuideColor)
        }

        drawLine(seriesA, color: Self.rsiLineColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// 成交量：底部基线 0 · 顶部 visible max · 涨红跌绿（按 K 线 close >= open 判涨）
    private func drawVolume(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        // y 范围：visible 内最大 volume · 顶部留 10% 边距
        var maxVolume: Double = 1.0
        for i in visibleStart..<visibleEnd where i < seriesA.count {
            if let v = seriesA[i], v > maxVolume { maxVolume = v }
        }
        let yScale = size.height * 0.9 / CGFloat(maxVolume)
        let yBase = size.height

        drawDashLine(at: yBase - 1, ctx: ctx, width: size.width, color: Self.volumeAxisColor)

        for i in visibleStart..<visibleEnd {
            guard i < seriesA.count, let v = seriesA[i], i < bars.count else { continue }
            let value = CGFloat(v)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let height = value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: yBase - height,
                width: barWidth * 0.6,
                height: height
            )
            let isUp = bars[i].close >= bars[i].open
            ctx.fill(Path(rect),
                     with: .color(isUp ? Self.volumeBullColor : Self.volumeBearColor))
        }
    }

    /// MACD：上下对称 · 零轴居中 · 直方图（涨红跌绿）+ DIF/DEA 双线
    private func drawMACD(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        // y 范围：visible 内 |DIF/DEA/柱| 最大值 · 上下对称 · 留 10% 边距
        var maxAbs: Double = 0.01
        for i in visibleStart..<visibleEnd {
            for arr in [seriesA, seriesB, seriesC] {
                if i < arr.count, let v = arr[i], abs(v) > maxAbs {
                    maxAbs = abs(v)
                }
            }
        }
        let yScale = (size.height / 2) * 0.9 / CGFloat(maxAbs)
        let yCenter = size.height / 2
        let yMap: (CGFloat) -> CGFloat = { yCenter - $0 * yScale }

        drawDashLine(at: yCenter, ctx: ctx, width: size.width, color: Self.zeroLineColor)

        // 直方图（涨红跌绿）
        for i in visibleStart..<visibleEnd {
            guard i < seriesC.count, let v = seriesC[i] else { continue }
            let value = CGFloat(v)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let yTop = yCenter - value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: min(yTop, yCenter),
                width: barWidth * 0.6,
                height: abs(yTop - yCenter)
            )
            ctx.fill(Path(rect),
                     with: .color(value >= 0 ? Self.macdBullColor : Self.macdBearColor))
        }

        drawLine(seriesA, color: Self.macdDifColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.macdDeaColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// KDJ：固定 -20~120 视野（80/50/20 参考线 · 超买/中位/超卖）· K/D/J 三线
    private func drawKDJ(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.kdjViewMin
        let viewMax = Self.kdjViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(80), 50, 20] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: Self.kdjGuideColor)
        }

        drawLine(seriesA, color: Self.kdjKColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.kdjDColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesC, color: Self.kdjJColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// 通用虚线（零轴 / 参考线 共用）
    private func drawDashLine(at y: CGFloat, ctx: GraphicsContext, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// 通用折线（MACD/KDJ 共用）· yMap 把指标值映射到屏幕 y 坐标
    private func drawLine(
        _ values: [Double?], color: Color, ctx: GraphicsContext,
        yMap: (CGFloat) -> CGFloat,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        var path = Path()
        var moved = false
        for i in visibleStart..<visibleEnd {
            guard i < values.count, let v = values[i] else { continue }
            let value = CGFloat(v)
            let x = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let y = yMap(value)
            if !moved {
                path.move(to: CGPoint(x: x, y: y))
                moved = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - 工具

    /// visible window 末位最近一个非 nil 值（反向 stride · 不分配中间数组）
    private func lastValue(_ values: [Double?], at end: Int) -> Double? {
        guard end >= 0, !values.isEmpty else { return nil }
        let safeEnd = min(end, values.count - 1)
        for i in stride(from: safeEnd, through: 0, by: -1) {
            if let v = values[i] { return v }
        }
        return nil
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f", v)
    }

    /// 成交量格式：≥1M 用 M / ≥1K 用 K · 与 Watchlist openInterestText 风格一致
    private func fmtVolume(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(Int(v))
    }
}

#endif
