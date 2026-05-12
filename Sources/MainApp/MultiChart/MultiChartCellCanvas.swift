// WP-44 v15.23 batch51 · 多图表 cell 简化 K 线 mini-view（Canvas 直接画蜡烛）
//
// 设计要点：
// - 不接 ChartCore Metal · 自画 SwiftUI Canvas（轻量 · 多 cell 同屏不卡）
// - 不接 SinaMarketDataProvider 真数据（异步、网络复杂）· 用 mock 演示数据
// - 后续 batch 可接 MarketDataPipeline · 当前重点是 UI 框架闭环
//
// 渲染：
// - 主图蜡烛（OHLC）· 涨绿跌红 · 实体 + 上下影线
// - 底部成交量柱（showVolume 开关 · 占 25% 高度）
// - 网格背景（5 条横线 + 边框）

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Foundation
import Shared
import ChartCore

struct MultiChartCellCanvas: View {

    let bars: [KLine]
    /// 兼容字段（batch79 起用 subChart 决定副图）· 仍保留以避免上游 break
    let showVolume: Bool
    /// v15.23 batch68 · 共享悬停 K 线索引（0..count-1 · nil = 不悬停）
    /// 由父 MultiChartHost 跨 cell 同步 · 实现联动十字线
    let hoveredIndex: Int?
    /// hover 回调：本 cell 内鼠标移动时上报当前 index 给父
    let onHoverIndexChange: ((Int?) -> Void)?
    /// v15.23 batch72-74 · MA 4 均线开关（MA5/10/20/60 · 中国期货短线经典标配）
    let showIndicators: Bool
    /// v15.23 batch78 · BOLL 上下轨开关（突破信号 · 默认关 · trader 主动开）
    let showBoll: Bool
    /// v15.23 batch79 · 副图类型（量/KDJ/无 · trader 切换不同维度）
    let subChart: MultiChartSubChartType
    /// v15.23 batch86 · SAR 抛物线（默认关 · trader 短线趋势反转 + 跟踪止损）
    let showSAR: Bool
    /// v15.23 batch91 · 用户手动标记的水平参考线（trader 关键价位 · 支撑/压力 · 标普跌停等）
    let horizontalLines: [Double]
    /// v15.23 batch93 · 主图视图模式（false=K 线 蜡烛 · true=分时 折线）
    let isTimeShareMode: Bool
    /// v15.23 batch94 · 整数关口辅助线（trader 心理关口 · 灰虚线 · 默认关）
    let showIntegerLevels: Bool
    /// v15.23 batch97 · 涨跌停参考线（红=涨停 · 绿=跌停 · first close × ±10% 简化估算）
    let showLimitLines: Bool
    /// v15.23 batch98 · VWAP 折线（成交量加权均价 · 机构 trader 必看）
    let showVWAP: Bool
    /// v15.23 batch99 · Fibonacci 黄金回撤（区间 7 条水平线 · trader 经典回撤分析）
    let showFibonacci: Bool
    /// v15.23 batch149 · Pivot Points（5 线 R2/R1/PP/S1/S2 · 短线支撑/压力 · 默认关）
    let showPivotPoints: Bool
    /// v17.100 · 价格小数位（按合约 priceTick + PricePrecisionMode · 默认 2 保旧兼容）
    let priceDigits: Int

    init(bars: [KLine], showVolume: Bool,
         hoveredIndex: Int? = nil,
         onHoverIndexChange: ((Int?) -> Void)? = nil,
         showIndicators: Bool = true,
         showBoll: Bool = false,
         subChart: MultiChartSubChartType = .volume,
         showSAR: Bool = false,
         horizontalLines: [Double] = [],
         isTimeShareMode: Bool = false,
         showIntegerLevels: Bool = false,
         showLimitLines: Bool = false,
         showVWAP: Bool = false,
         showFibonacci: Bool = false,
         showPivotPoints: Bool = false,
         priceDigits: Int = 2) {
        self.bars = bars
        self.showVolume = showVolume
        self.hoveredIndex = hoveredIndex
        self.onHoverIndexChange = onHoverIndexChange
        self.showIndicators = showIndicators
        self.showBoll = showBoll
        self.subChart = subChart
        self.showSAR = showSAR
        self.horizontalLines = horizontalLines
        self.isTimeShareMode = isTimeShareMode
        self.showIntegerLevels = showIntegerLevels
        self.showLimitLines = showLimitLines
        self.showVWAP = showVWAP
        self.showFibonacci = showFibonacci
        self.showPivotPoints = showPivotPoints
        self.priceDigits = priceDigits
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !bars.isEmpty else { return }
                // batch79 · subChart 接管副图区高度（none = 0 · 否则 25%）
                let subHeight: CGFloat = subChart == .none ? 0 : size.height * 0.25
                let priceHeight = size.height - subHeight - 4
                let priceRect = CGRect(x: 0, y: 0, width: size.width, height: priceHeight)
                let subRect = CGRect(x: 0, y: priceHeight + 4, width: size.width, height: subHeight)

                drawGrid(in: ctx, rect: priceRect)
                // v15.34 WP-40 P1 延伸 · session/day 缺口竖线（夜盘日盘衔接 / 跨日 / 周末）
                drawSessionDividers(in: ctx, rect: priceRect)
                if isTimeShareMode {
                    // batch93 · 分时折线模式（close 红线 + 累计均价黄线 + 红色底纹）
                    drawTimeShareLine(in: ctx, rect: priceRect)
                } else {
                    drawCandles(in: ctx, rect: priceRect)
                }
                // v15.23 batch72-74 · 主图叠加 5/10/20/60 四均线（中国期货短线经典标配）
                // bars 同坐标系 · 需用相同 minLow/maxHigh 映射价格→Y · 不重算价格区间
                // 颜色梯度：快线偏黄/红 → 慢线偏紫/蓝（trader 一眼区分周期）
                if showIndicators {
                    drawMA(in: ctx, rect: priceRect, period: 5,
                           color: .yellow.opacity(0.9), lineWidth: 1)
                    drawMA(in: ctx, rect: priceRect, period: 10,
                           color: .pink.opacity(0.85), lineWidth: 1)
                    drawMA(in: ctx, rect: priceRect, period: 20,
                           color: .purple.opacity(0.85), lineWidth: 1)
                    drawMA(in: ctx, rect: priceRect, period: 60,
                           color: .blue.opacity(0.8), lineWidth: 1)
                }
                // v15.23 batch78 · BOLL 上下轨（period=20 · k=2σ · trader 突破信号）
                if showBoll {
                    drawBoll(in: ctx, rect: priceRect, period: 20, k: 2)
                }
                // v15.23 batch86 · SAR 抛物线（Wilder 0.02 step / 0.2 max · 默认关）
                if showSAR {
                    drawSAR(in: ctx, rect: priceRect)
                }
                // v15.23 batch91 · 用户标记的水平参考线（trader 支撑/压力位 · 灰虚线 + 价格标签）
                if !horizontalLines.isEmpty {
                    drawHorizontalLines(in: ctx, rect: priceRect)
                }
                // v15.23 batch94 · 整数关口辅助线（trader 心理关口 · 自动按价位级别）
                if showIntegerLevels {
                    drawIntegerLevels(in: ctx, rect: priceRect)
                }
                // v15.23 batch97 · 涨跌停参考线（中国期货特色 · 简化版 first close × ±10%）
                if showLimitLines {
                    drawLimitLines(in: ctx, rect: priceRect)
                }
                // v15.23 batch98 · VWAP 折线（机构 trader 必看 · 成交量加权均价）
                if showVWAP {
                    drawVWAP(in: ctx, rect: priceRect)
                }
                // v15.23 batch99 · Fibonacci 黄金回撤（区间高低点 7 条水平线 · trader 经典）
                if showFibonacci {
                    drawFibonacci(in: ctx, rect: priceRect)
                }
                // v15.23 batch149 · Pivot Points（5 线 · 区间静态支撑/压力）
                if showPivotPoints {
                    drawPivotPoints(in: ctx, rect: priceRect)
                }
                if subHeight > 8 {
                    drawGrid(in: ctx, rect: subRect, lines: 2)
                    switch subChart {
                    case .none:
                        break
                    case .volume:
                        drawVolumes(in: ctx, rect: subRect)
                    case .kdj:
                        drawKDJ(in: ctx, rect: subRect)
                    case .macd:
                        drawMACD(in: ctx, rect: subRect)
                    case .rsi:
                        drawRSI(in: ctx, rect: subRect)
                    case .oi:
                        drawOI(in: ctx, rect: subRect)
                    case .atr:
                        drawATR(in: ctx, rect: subRect)
                    case .cci:
                        drawCCI(in: ctx, rect: subRect)
                    case .wr:
                        drawWR(in: ctx, rect: subRect)
                    }
                    // batch101 · 副图左上角显示指标名称 + 参数（trader 一眼识别）
                    drawSubChartLabel(in: ctx, rect: subRect)
                }
                // v15.23 batch77 · 简洁 axis 标签（时间 3 + 价格 3 · 不喧宾夺主）
                drawAxisLabels(in: ctx, priceRect: priceRect, bottomY: size.height)
                // v15.23 batch102 · 主图 H/L 最高最低点标记（trader 一眼识别区间极值）
                if !isTimeShareMode {
                    drawHighLowMarkers(in: ctx, rect: priceRect)
                }
                // v15.23 batch68 · 联动十字线（垂直 vertical line at hovered index · 跨 cell 同步）
                // v15.23 batch85 · 加水平虚线 at close + 右侧价格 label（完整十字线 · trader 经典）
                if let hidx = hoveredIndex, hidx >= 0, hidx < bars.count {
                    let centerX = priceRect.minX + (CGFloat(hidx) + 0.5) * priceRect.width / CGFloat(bars.count)
                    var line = Path()
                    line.move(to: CGPoint(x: centerX, y: 0))
                    line.addLine(to: CGPoint(x: centerX, y: size.height))
                    ctx.stroke(line, with: .color(.accentColor.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    // 水平虚线 at hover bar close（仅 priceRect 内 · 不跨副图）
                    let bar = bars[hidx]
                    let close = (bar.close as NSDecimalNumber).doubleValue
                    let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
                    let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
                    if let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow {
                        let priceRange = maxHigh - minLow
                        let yClose = priceRect.maxY - CGFloat((close - minLow) / priceRange) * priceRect.height
                        var hLine = Path()
                        hLine.move(to: CGPoint(x: priceRect.minX, y: yClose))
                        hLine.addLine(to: CGPoint(x: priceRect.maxX, y: yClose))
                        ctx.stroke(hLine, with: .color(.accentColor.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        // 右侧 close 价格标签（高亮 · 强调精确价格）
                        let priceLbl = Text(String(format: "%.\(priceDigits)f", close))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white)
                        let resolvedP = ctx.resolve(priceLbl)
                        let pSize = resolvedP.measure(in: CGSize(width: 80, height: 14))
                        let pRect = CGRect(
                            x: priceRect.maxX - pSize.width - 6,
                            y: yClose - pSize.height / 2 - 1,
                            width: pSize.width + 5,
                            height: pSize.height + 2
                        )
                        ctx.fill(Path(roundedRect: pRect, cornerRadius: 2),
                                 with: .color(.accentColor.opacity(0.85)))
                        ctx.draw(priceLbl,
                                 at: CGPoint(x: pRect.midX, y: pRect.midY),
                                 anchor: .center)
                    }
                    // 顶部小标签：bar index + close
                    let label = "[\(hidx + 1)] \(String(format: "%.\(priceDigits)f", close))"
                    let labelText = Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white)
                    let resolved = ctx.resolve(labelText)
                    let labelSize = resolved.measure(in: CGSize(width: 200, height: 20))
                    let labelRect = CGRect(
                        x: max(2, min(size.width - labelSize.width - 6, centerX - labelSize.width / 2 - 3)),
                        y: 2,
                        width: labelSize.width + 6,
                        height: labelSize.height + 2
                    )
                    ctx.fill(Path(roundedRect: labelRect, cornerRadius: 2),
                             with: .color(.accentColor.opacity(0.85)))
                    ctx.draw(labelText, at: CGPoint(x: labelRect.midX, y: labelRect.midY), anchor: .center)
                }
            }
            .onContinuousHover { phase in
                guard let cb = onHoverIndexChange else { return }
                switch phase {
                case .active(let location):
                    // v15.39 · 复用 ChartHitTester（取代手写 normalized 计算 · 与主图 hit-test 同口径）
                    cb(ChartHitTester.barIndex(atX: location.x, width: geo.size.width, barCount: bars.count))
                case .ended:
                    cb(nil)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Session/Day Dividers (v15.34 WP-40 P1 延伸)

    /// 复用 ChartCore.SessionAxisHelper · 单 cell 简化版（不分 viewport · 全 bars 范围）
    /// 6 cell 同屏时：每 cell 独立显示自己的 session/day 缺口（多周期共振时尤其有用）
    private func drawSessionDividers(in ctx: GraphicsContext, rect: CGRect) {
        guard let period = bars.first?.period else { return }
        let gaps = SessionAxisHelper.detectGaps(bars: bars, period: period)
        guard !gaps.isEmpty, !bars.isEmpty else { return }
        let stepX = rect.width / CGFloat(bars.count)
        for gap in gaps {
            let x = rect.minX + CGFloat(gap.barIndex) * stepX
            var line = Path()
            line.move(to: CGPoint(x: x, y: rect.minY))
            line.addLine(to: CGPoint(x: x, y: rect.maxY))
            switch gap.kind {
            case .session:
                ctx.stroke(line, with: .color(.white.opacity(0.10)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            case .day:
                ctx.stroke(line, with: .color(.orange.opacity(0.40)),
                           style: StrokeStyle(lineWidth: 1.0, dash: [5, 4]))
            }
        }
    }

    // MARK: - Grid

    private func drawGrid(in ctx: GraphicsContext, rect: CGRect, lines: Int = 5) {
        var path = Path()
        for i in 0...lines {
            let y = rect.minY + CGFloat(i) * rect.height / CGFloat(lines)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
    }

    // MARK: - Candles

    private func drawCandles(in ctx: GraphicsContext, rect: CGRect) {
        let opens = bars.map { ($0.open as NSDecimalNumber).doubleValue }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        _ = opens
        _ = closes

        let priceRange = maxHigh - minLow
        let n = bars.count
        let candleWidth = max(1.5, rect.width / CGFloat(n) * 0.7)

        for (i, bar) in bars.enumerated() {
            let open = (bar.open as NSDecimalNumber).doubleValue
            let close = (bar.close as NSDecimalNumber).doubleValue
            let high = (bar.high as NSDecimalNumber).doubleValue
            let low = (bar.low as NSDecimalNumber).doubleValue
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)

            let yFor = { (price: Double) -> CGFloat in
                rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
            }
            let isUp = close >= open
            let color: Color = isUp ? .red : .green   // 中国习惯：涨红跌绿
            let upper = max(open, close)
            let lower = min(open, close)

            // 上下影线
            var wickPath = Path()
            wickPath.move(to: CGPoint(x: centerX, y: yFor(high)))
            wickPath.addLine(to: CGPoint(x: centerX, y: yFor(low)))
            ctx.stroke(wickPath, with: .color(color), lineWidth: 1)

            // 实体
            let bodyTop = yFor(upper)
            let bodyHeight = max(1, yFor(lower) - bodyTop)
            let bodyRect = CGRect(
                x: centerX - candleWidth / 2,
                y: bodyTop,
                width: candleWidth,
                height: bodyHeight
            )
            if isUp {
                // 涨：实心红
                ctx.fill(Path(bodyRect), with: .color(color))
            } else {
                // 跌：填充实心绿（中国习惯）· 与上影线同色
                ctx.fill(Path(bodyRect), with: .color(color))
            }
            // v15.23 batch76 · 末根 K 线高亮（白色 1px 描边 + 同色 dot · 强调最新数据）
            // v15.23 batch89 · 末根 close 永久水平虚线 from dot to maxX（trader 看 close vs MA 位置）
            // v15.23 batch92 · BOLL 突破信号 · close 突破上轨 → 红边框（强多）· 突破下轨 → 绿边框（强空）
            if i == n - 1 {
                let borderColor = breakoutBorderColor(close: close) ?? .white.opacity(0.85)
                ctx.stroke(Path(bodyRect.insetBy(dx: -0.5, dy: -0.5)),
                           with: .color(borderColor),
                           lineWidth: 1)
                let dotSize: CGFloat = 4
                let yClose = yFor(close)
                let dotRect = CGRect(
                    x: centerX - dotSize / 2,
                    y: yClose - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
                ctx.stroke(Path(ellipseIn: dotRect),
                           with: .color(.white.opacity(0.9)),
                           lineWidth: 0.7)
                // 水平虚线 from dot 到画布右边 · 同蜡烛颜色 0.5 alpha · 不抢 MA 折线
                var hLine = Path()
                hLine.move(to: CGPoint(x: centerX + dotSize / 2 + 1, y: yClose))
                hLine.addLine(to: CGPoint(x: rect.maxX, y: yClose))
                ctx.stroke(hLine, with: .color(color.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }
        }
    }

    // MARK: - Axis labels（v15.23 batch77 · 时间 3 个 + 价格 3 个 · 极简版本）

    private func drawAxisLabels(in ctx: GraphicsContext, priceRect: CGRect, bottomY: CGFloat) {
        let n = bars.count
        guard n >= 2 else { return }
        // 价格 max/mid/min · 右侧
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        if let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow {
            let mid = (maxHigh + minLow) / 2
            let pricePts: [(Double, CGFloat)] = [
                (maxHigh, priceRect.minY + 8),
                (mid, priceRect.midY),
                (minLow, priceRect.maxY - 8),
            ]
            for (price, y) in pricePts {
                let txt = Text(String(format: "%.\(priceDigits)f", price))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.9))
                let resolved = ctx.resolve(txt)
                let s = resolved.measure(in: CGSize(width: 80, height: 14))
                ctx.draw(txt,
                         at: CGPoint(x: priceRect.maxX - s.width / 2 - 3, y: y),
                         anchor: .center)
            }
        }
        // 时间 start/mid/end · 底部（紧贴 priceRect.maxY 上沿 · 不与 volume 冲突）
        let timePts: [(Int, CGFloat)] = [
            (0, priceRect.minX + 4),
            (n / 2, priceRect.minX + priceRect.width / 2),
            (n - 1, priceRect.maxX - 4),
        ]
        for (i, x) in timePts {
            guard i >= 0, i < n else { continue }
            let label = formatBarTime(bars[i].openTime)
            let txt = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.85))
            let resolved = ctx.resolve(txt)
            let s = resolved.measure(in: CGSize(width: 100, height: 14))
            // 边界保护：首末 label 紧贴边缘 · 中间居中
            let drawX: CGFloat
            if i == 0 {
                drawX = x + s.width / 2
            } else if i == n - 1 {
                drawX = x - s.width / 2
            } else {
                drawX = x
            }
            ctx.draw(txt,
                     at: CGPoint(x: drawX, y: priceRect.maxY - 7),
                     anchor: .center)
        }
    }

    /// 时间格式按周期粒度（小周期分钟级 / 中周期日时 / 日线日期）
    private func formatBarTime(_ t: Date) -> String {
        let f = DateFormatter()
        let period = bars.first?.period ?? .minute15
        switch period {
        case .minute1, .minute3, .minute5, .minute15, .minute30:
            f.dateFormat = "MM/dd HH:mm"
        case .hour1, .hour2, .hour4:
            f.dateFormat = "MM/dd HH"
        case .daily, .weekly, .monthly:
            f.dateFormat = "yy/MM/dd"
        default:
            f.dateFormat = "MM/dd HH:mm"
        }
        return f.string(from: t)
    }

    // MARK: - MA（v15.23 batch72 · 简单移动平均线 · 复用蜡烛 minLow/maxHigh 价格映射）

    /// 滑动窗口 SMA · O(N) · 前 period-1 根没有 MA 值（跳过不画）
    private func drawMA(in ctx: GraphicsContext, rect: CGRect, period: Int,
                        color: Color, lineWidth: CGFloat) {
        let n = bars.count
        guard n >= period else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor = { (price: Double) -> CGFloat in
            rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
        }
        var sum: Double = 0
        var path = Path()
        var started = false
        for i in 0..<n {
            let close = (bars[i].close as NSDecimalNumber).doubleValue
            sum += close
            if i >= period {
                let outClose = (bars[i - period].close as NSDecimalNumber).doubleValue
                sum -= outClose
            }
            if i >= period - 1 {
                let ma = sum / Double(period)
                let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
                let pt = CGPoint(x: centerX, y: yFor(ma))
                if started {
                    path.addLine(to: pt)
                } else {
                    path.move(to: pt)
                    started = true
                }
            }
        }
        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    // MARK: - 分时折线（v15.23 batch93 · close 红线 + 累计均价黄线 + 红色底纹 · trader 真盘看图）

    /// 分时图：每根 K 线 close 折线 · 累计均价虚线 · close 折线下方红色底纹强调强弱
    private func drawTimeShareLine(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 2 else { return }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        var closePath = Path()
        var avgPath = Path()
        var avg: Double = 0
        var startedClose = false
        var startedAvg = false
        for i in 0..<n {
            let x = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let yC = yFor(closes[i])
            if startedClose {
                closePath.addLine(to: CGPoint(x: x, y: yC))
            } else {
                closePath.move(to: CGPoint(x: x, y: yC))
                startedClose = true
            }
            avg = (avg * Double(i) + closes[i]) / Double(i + 1)
            let yA = yFor(avg)
            if startedAvg {
                avgPath.addLine(to: CGPoint(x: x, y: yA))
            } else {
                avgPath.move(to: CGPoint(x: x, y: yA))
                startedAvg = true
            }
        }
        // 红色底纹（close 折线下方填充 · 高亮强度）
        var fillPath = closePath
        let lastX = rect.minX + (CGFloat(n - 1) + 0.5) * rect.width / CGFloat(n)
        fillPath.addLine(to: CGPoint(x: lastX, y: rect.maxY))
        fillPath.addLine(to: CGPoint(x: rect.minX + 0.5 * rect.width / CGFloat(n), y: rect.maxY))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(.red.opacity(0.12)))
        // close 红线
        ctx.stroke(closePath, with: .color(.red.opacity(0.9)), lineWidth: 1.2)
        // 累计均价黄虚线
        ctx.stroke(avgPath, with: .color(.yellow.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
        // 末根 close dot 高亮（同 K 线模式）
        if let last = closes.last {
            let x = rect.minX + (CGFloat(n - 1) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(last)
            let dot = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot), with: .color(.red))
            ctx.stroke(Path(ellipseIn: dot),
                       with: .color(.white.opacity(0.9)), lineWidth: 0.7)
        }
    }

    // MARK: - BOLL 突破信号（v15.23 batch92 · 末根 close 突破上下轨时换边框色）

    /// close > BOLL 上轨 → 红边框（突破多头）· < 下轨 → 绿边框（破位空头）· 否则 nil（默认白）
    /// 仅 showBoll=true 时启用 · 与 drawBoll 用相同 period=20 / k=2 标准
    private func breakoutBorderColor(close: Double) -> Color? {
        guard showBoll, bars.count >= 20 else { return nil }
        let n = bars.count
        let period = 20
        let closes = bars[(n - period)..<n].map { ($0.close as NSDecimalNumber).doubleValue }
        let mean = closes.reduce(0, +) / Double(period)
        let variance = closes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(period)
        let stdev = sqrt(variance)
        let upper = mean + 2 * stdev
        let lower = mean - 2 * stdev
        if close > upper { return .red.opacity(0.95) }
        if close < lower { return .green.opacity(0.95) }
        return nil
    }

    // MARK: - H/L 最高最低点标记（v15.23 batch102 · trader 区间极值一眼可见）

    /// 区间最高点标 "H X.XX"（红） · 最低点标 "L X.XX"（绿）· 自动定位
    private func drawHighLowMarkers(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 2 else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        guard let maxIdx = highs.firstIndex(of: maxHigh),
              let minIdx = lows.firstIndex(of: minLow) else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        // H 标记（在最高点上方 6px · 红色）
        let hX = rect.minX + (CGFloat(maxIdx) + 0.5) * rect.width / CGFloat(n)
        let hY = yFor(maxHigh) + 8  // 注意 +y 是向下（顶部最低 y），最高点在 yFor(maxHigh)，标签在它上方就是 -y
        let hLbl = Text("H \(String(format: "%.\(priceDigits)f", maxHigh))")
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.red.opacity(0.85))
        ctx.draw(hLbl, at: CGPoint(x: max(rect.minX + 30, min(rect.maxX - 30, hX)),
                                    y: yFor(maxHigh) - 6),
                 anchor: .center)
        _ = hY
        // L 标记（在最低点下方）
        let lX = rect.minX + (CGFloat(minIdx) + 0.5) * rect.width / CGFloat(n)
        let lLbl = Text("L \(String(format: "%.\(priceDigits)f", minLow))")
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.green.opacity(0.85))
        ctx.draw(lLbl, at: CGPoint(x: max(rect.minX + 30, min(rect.maxX - 30, lX)),
                                    y: yFor(minLow) + 6),
                 anchor: .center)
    }

    // MARK: - 副图标签（v15.23 batch101 · 左上角显示指标名 + 参数 · trader 一眼识别）

    /// 副图左上角显示当前指标名称 + 标准参数（避免 trader 困惑当前看的是 KDJ(9,3,3) 还是 RSI(14)）
    private func drawSubChartLabel(in ctx: GraphicsContext, rect: CGRect) {
        let label: String
        switch subChart {
        case .none: return
        case .volume: label = "量"
        case .kdj: label = "KDJ(9,3,3)"
        case .macd: label = "MACD(12,26,9)"
        case .rsi: label = "RSI(14)"
        case .oi: label = "OI 持仓量"
        case .atr: label = "ATR(14)"
        case .cci: label = "CCI(14)"
        case .wr:  label = "W%R(14)"
        }
        let txt = Text(label)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.85))
        ctx.draw(txt, at: CGPoint(x: rect.minX + 4, y: rect.minY + 6),
                 anchor: .leading)
    }

    // MARK: - Fibonacci 黄金回撤（v15.23 batch99 · 区间高低 7 条水平线 · trader 经典回撤分析）

    /// 经典 Fib 比例：0% / 23.6% / 38.2% / 50% / 61.8% / 78.6% / 100%
    /// 0% = 区间最低 · 100% = 区间最高 · 中间是回撤位
    /// trader 看 close 在哪条 fib 线附近 → 经典买卖位（如 38.2/61.8 极强）
    private func drawFibonacci(in ctx: GraphicsContext, rect: CGRect) {
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        let levels: [(Double, String, Color)] = [
            (0.0, "0", .blue.opacity(0.5)),
            (0.236, "23.6", .gray.opacity(0.4)),
            (0.382, "38.2", .yellow.opacity(0.6)),
            (0.5, "50", .orange.opacity(0.55)),
            (0.618, "61.8", .yellow.opacity(0.6)),       // 黄金分割
            (0.786, "78.6", .gray.opacity(0.4)),
            (1.0, "100", .blue.opacity(0.5)),
        ]
        for (ratio, label, color) in levels {
            let price = minLow + ratio * priceRange
            let y = yFor(price)
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            // 左下角标签：比例 + 价格
            let txt = Text("\(label)% \(String(format: "%.\(priceDigits)f", price))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(color.opacity(2))
            ctx.draw(txt, at: CGPoint(x: rect.minX + 38, y: y - 5),
                     anchor: .center)
        }
    }

    // MARK: - Pivot Points（v15.23 batch149 · 5 线 · 区间静态支撑/压力）

    /// 简化版：用 bars[0]（区间首根）作"前一周期" H/L/C 计算 PP/R1/R2/S1/S2
    /// PP = (H+L+C)/3 · R1=2*PP-L · S1=2*PP-H · R2=PP+(H-L) · S2=PP-(H-L)
    /// trader 看 close 接近哪条线 → 短线进出场参考位
    private func drawPivotPoints(in ctx: GraphicsContext, rect: CGRect) {
        guard let first = bars.first else { return }
        let h = (first.high as NSDecimalNumber).doubleValue
        let l = (first.low as NSDecimalNumber).doubleValue
        let c = (first.close as NSDecimalNumber).doubleValue
        let pp = (h + l + c) / 3
        let r1 = 2 * pp - l
        let s1 = 2 * pp - h
        let r2 = pp + (h - l)
        let s2 = pp - (h - l)

        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }

        let levels: [(Double, String, Color)] = [
            (r2, "R2", .red.opacity(0.7)),
            (r1, "R1", .red.opacity(0.5)),
            (pp, "PP", .yellow.opacity(0.7)),
            (s1, "S1", .green.opacity(0.5)),
            (s2, "S2", .green.opacity(0.7)),
        ]
        for (price, label, color) in levels {
            let y = yFor(price)
            // 越界裁剪
            guard y >= rect.minY - 2 && y <= rect.maxY + 2 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 0.6, dash: [4, 2]))
            // 右上方标签 "R2 3520.5"
            let txt = Text("\(label) \(String(format: "%.\(priceDigits)f", price))")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(color.opacity(2))
            ctx.draw(txt, at: CGPoint(x: rect.maxX - 4, y: y - 5),
                     anchor: .topTrailing)
        }
    }

    // MARK: - VWAP（v15.23 batch98 · 成交量加权均价 · 机构 trader 必看）

    /// VWAP[i] = sum(close[0..i] × volume[0..i]) / sum(volume[0..i]) · 累积形式
    /// 蓝色折线（与 MA 区分）· 反映"市场平均交易成本"· trader 看 close vs VWAP 多空力量
    private func drawVWAP(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 2 else { return }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        let volumes = bars.map { Double($0.volume) }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        var sumPV = 0.0
        var sumV = 0.0
        var path = Path()
        var started = false
        for i in 0..<n {
            sumPV += closes[i] * volumes[i]
            sumV += volumes[i]
            guard sumV > 0 else { continue }
            let vwap = sumPV / sumV
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let pt = CGPoint(x: centerX, y: yFor(vwap))
            if started {
                path.addLine(to: pt)
            } else {
                path.move(to: pt)
                started = true
            }
        }
        // 蓝色实线（与 MA60 蓝区分 · 用 cyan 0.85 alpha）
        ctx.stroke(path, with: .color(.cyan.opacity(0.85)), lineWidth: 1.2)
    }

    // MARK: - 涨跌停参考线（v15.23 batch97 · 简化版 first close × ±10%）

    /// 红色 = 涨停 · 绿色 = 跌停 · 简化估算（实际不同合约规则不同 · 5%/7%/10% 等）
    /// 不同 K 线区间会"前结算价"漂移 · 此处用首根 close 当 reference 提供视觉参考
    private func drawLimitLines(in ctx: GraphicsContext, rect: CGRect) {
        guard let first = bars.first else { return }
        let firstClose = (first.close as NSDecimalNumber).doubleValue
        guard firstClose > 0 else { return }
        let upperLimit = firstClose * 1.10
        let lowerLimit = firstClose * 0.90
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        // 仅当涨跌停在可视区间附近时画（±20% buffer · 远超出范围则隐藏避免溢出）
        for (price, color, label) in [
            (upperLimit, Color.red.opacity(0.4), "涨停 \(String(format: "%.\(priceDigits)f", upperLimit))"),
            (lowerLimit, Color.green.opacity(0.4), "跌停 \(String(format: "%.\(priceDigits)f", lowerLimit))"),
        ] {
            guard price >= minLow - priceRange * 0.2,
                  price <= maxHigh + priceRange * 0.2 else { continue }
            let y = yFor(price)
            let yClamped = max(rect.minY, min(rect.maxY, y))
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: yClamped))
            line.addLine(to: CGPoint(x: rect.maxX, y: yClamped))
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            let txt = Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color.opacity(2))  // 翻倍透明度让 text 比线明显
            ctx.draw(txt, at: CGPoint(x: rect.minX + 38, y: yClamped - 6),
                     anchor: .center)
        }
    }

    // MARK: - 整数关口辅助线（v15.23 batch94 · 自动按价位级别 · trader 心理关口）

    /// 自动按价位级别决定 step（10000+→1000 / 1000+→100 / 100+→10 / 10+→1 / else→0.1）
    /// 在 priceRange 内画整数关口（灰色 0.18 alpha · 极弱化 · 不抢蜡烛）
    private func drawIntegerLevels(in ctx: GraphicsContext, rect: CGRect) {
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let midPrice = (maxHigh + minLow) / 2
        let step: Double
        if midPrice > 10000 { step = 1000 }
        else if midPrice > 1000 { step = 100 }
        else if midPrice > 100 { step = 10 }
        else if midPrice > 10 { step = 1 }
        else { step = 0.1 }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { p in
            rect.maxY - CGFloat((p - minLow) / priceRange) * rect.height
        }
        var p = ceil(minLow / step) * step
        var lineCount = 0
        while p <= maxHigh && lineCount < 10 {  // 防过多线挤
            let y = yFor(p)
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: y))
            line.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(line, with: .color(.gray.opacity(0.18)),
                       style: StrokeStyle(lineWidth: 0.4, dash: [1, 4]))
            p += step
            lineCount += 1
        }
    }

    // MARK: - 水平参考线（v15.23 batch91 · trader 标支撑/压力价位）

    /// 用户标记的水平参考线 · 灰白虚线 · 左上角小价格标签
    private func drawHorizontalLines(in ctx: GraphicsContext, rect: CGRect) {
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        for price in horizontalLines {
            // 仅显示在可视价格范围内的（外侧不画 · 避免溢出）
            guard price >= minLow - priceRange * 0.3, price <= maxHigh + priceRange * 0.3 else { continue }
            let y = rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
            // 钳制到 rect 内（极端价位时贴边显示）
            let yClamped = max(rect.minY, min(rect.maxY, y))
            var line = Path()
            line.move(to: CGPoint(x: rect.minX, y: yClamped))
            line.addLine(to: CGPoint(x: rect.maxX, y: yClamped))
            ctx.stroke(line, with: .color(.orange.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
            let lbl = Text(String(format: "%.\(priceDigits)f", price))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.orange.opacity(0.85))
            ctx.draw(lbl, at: CGPoint(x: rect.minX + 24, y: yClamped - 6),
                     anchor: .center)
        }
    }

    // MARK: - ATR（v15.23 batch95 · Wilder 14 · trader 设止损 + 仓位管理）

    /// ATR(14) 标准 Wilder 平滑 · 橙色折线 · 末根价值可用于止损位计算（如 close ± 2×ATR）
    private func drawATR(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        let N = 14
        guard n >= N + 1 else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        // 计算 TR 序列
        var trs: [Double] = []
        for i in 1..<n {
            let h = highs[i], l = lows[i], pc = closes[i - 1]
            let tr = max(h - l, abs(h - pc), abs(l - pc))
            trs.append(tr)
        }
        // ATR Wilder 平滑（首 N 用 SMA · 后续 (prev × (N-1) + TR) / N）
        var atrs: [Double] = Array(repeating: .nan, count: n)
        let initialAvg = trs[0..<N].reduce(0, +) / Double(N)
        atrs[N] = initialAvg
        var prev = initialAvg
        for i in (N + 1)..<n {
            let cur = (prev * Double(N - 1) + trs[i - 1]) / Double(N)
            atrs[i] = cur
            prev = cur
        }
        // 归一化坐标 + 折线
        let nonNan = atrs.compactMap { $0.isNaN ? nil : $0 }
        guard let maxA = nonNan.max(), let minA = nonNan.min(), maxA > minA else { return }
        let range = maxA - minA
        let yFor: (Double) -> CGFloat = { v in
            rect.maxY - CGFloat((v - minA) / range) * rect.height
        }
        var path = Path()
        var started = false
        for i in 0..<n where !atrs[i].isNaN {
            let x = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let pt = CGPoint(x: x, y: yFor(atrs[i]))
            if started {
                path.addLine(to: pt)
            } else {
                path.move(to: pt)
                started = true
            }
        }
        ctx.stroke(path, with: .color(.orange.opacity(0.85)), lineWidth: 0.9)
        // 末根 ATR dot 高亮 + 数值标签
        if let lastATR = atrs.last, !lastATR.isNaN {
            let x = rect.minX + (CGFloat(n - 1) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(lastATR)
            let dot = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot), with: .color(.orange))
            let lbl = Text(String(format: "%.\(priceDigits)f", lastATR))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.orange.opacity(0.9))
            ctx.draw(lbl, at: CGPoint(x: rect.maxX - 18, y: rect.minY + 6),
                     anchor: .center)
        }
    }

    // MARK: - OI 持仓量（v15.23 batch87 · 折线图 · 中国期货独有 · 主力意图）

    /// OI 折线（蓝色 · 折线在 OI 区间归一化 · 末根高亮 dot 强调最新）
    /// trader 看 OI：增仓上涨 = 多头强势 · 增仓下跌 = 空头强势 · 减仓 = 多空回吐
    private func drawOI(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 2 else { return }
        let ois = bars.map { ($0.openInterest as NSDecimalNumber).doubleValue }
        guard let maxOI = ois.max(), let minOI = ois.min() else { return }
        // 全 0 数据（mock 老数据）→ 平线提示无 OI · 仅画一条灰线
        guard maxOI > 0 else {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            ctx.stroke(path, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            let placeholder = Text("OI 数据未提供")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
            ctx.draw(placeholder, at: CGPoint(x: rect.midX, y: rect.midY - 6),
                     anchor: .center)
            return
        }
        let range = maxOI - minOI
        let yFor: (Double) -> CGFloat = { v in
            // range 极小 → 居中显示（避免 / 0 + 锯齿）
            range > 0 ? rect.maxY - CGFloat((v - minOI) / range) * rect.height : rect.midY
        }
        var path = Path()
        var started = false
        for i in 0..<n {
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let pt = CGPoint(x: centerX, y: yFor(ois[i]))
            if started {
                path.addLine(to: pt)
            } else {
                path.move(to: pt)
                started = true
            }
        }
        ctx.stroke(path, with: .color(.blue.opacity(0.8)), lineWidth: 1)
        // 末根 OI dot 高亮 + 数值标签（万手单位 · trader 习惯）
        if let lastOI = ois.last {
            let centerX = rect.minX + (CGFloat(n - 1) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(lastOI)
            let dot = CGRect(x: centerX - 2, y: y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot), with: .color(.blue))
            let lbl = Text(String(format: "%.1f万", lastOI / 10000))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.blue.opacity(0.9))
            ctx.draw(lbl, at: CGPoint(x: rect.maxX - 18, y: rect.minY + 6),
                     anchor: .center)
        }
    }

    // MARK: - SAR（v15.23 batch86 · Wilder Parabolic SAR · 标准 step=0.02 / max=0.2）

    /// SAR 抛物线 · 蓝色 2.5px 圆点（每根 K 线一个 · up trend 在低位 / down trend 在高位）
    /// 算法参考 Wilder 标准实现 · trader 短线趋势反转判断 + 跟踪止损位
    private func drawSAR(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 3 else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor: (Double) -> CGFloat = { price in
            rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
        }
        let afStep = 0.02
        let afMax = 0.2
        // 初始 trend 由前两根 close 大小判断
        var isUp = closes[1] > closes[0]
        var sar = isUp ? lows[0] : highs[0]
        var ep = isUp ? highs[0] : lows[0]
        var af = afStep
        var sarValues: [Double] = [sar]
        for i in 1..<n {
            var nextSAR = sar + af * (ep - sar)
            if isUp {
                // SAR 不能高于上 2 根 low
                let lowPrev1 = lows[i - 1]
                let lowPrev2 = i >= 2 ? lows[i - 2] : lowPrev1
                nextSAR = min(nextSAR, lowPrev1, lowPrev2)
                if lows[i] < nextSAR {
                    // 反转为 down · SAR = 上一段最高点 EP · EP = 当前 low · AF reset
                    isUp = false
                    sar = ep
                    ep = lows[i]
                    af = afStep
                } else {
                    sar = nextSAR
                    if highs[i] > ep {
                        ep = highs[i]
                        af = min(afMax, af + afStep)
                    }
                }
            } else {
                // SAR 不能低于上 2 根 high
                let highPrev1 = highs[i - 1]
                let highPrev2 = i >= 2 ? highs[i - 2] : highPrev1
                nextSAR = max(nextSAR, highPrev1, highPrev2)
                if highs[i] > nextSAR {
                    isUp = true
                    sar = ep
                    ep = highs[i]
                    af = afStep
                } else {
                    sar = nextSAR
                    if lows[i] < ep {
                        ep = lows[i]
                        af = min(afMax, af + afStep)
                    }
                }
            }
            sarValues.append(sar)
        }
        let dotSize: CGFloat = 2.5
        for (i, v) in sarValues.enumerated() {
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(v)
            let dot = CGRect(x: centerX - dotSize / 2,
                             y: y - dotSize / 2,
                             width: dotSize,
                             height: dotSize)
            ctx.fill(Path(ellipseIn: dot), with: .color(.cyan.opacity(0.85)))
        }
    }

    // MARK: - BOLL（v15.23 batch78 · 上下轨折线 · 标准 period=20 / k=2σ · 中轨复用 MA20 不重画）

    private func drawBoll(in ctx: GraphicsContext, rect: CGRect, period: Int, k: Double) {
        let n = bars.count
        guard n >= period else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        guard let maxHigh = highs.max(), let minLow = lows.min(), maxHigh > minLow else { return }
        let priceRange = maxHigh - minLow
        let yFor = { (price: Double) -> CGFloat in
            rect.maxY - CGFloat((price - minLow) / priceRange) * rect.height
        }
        var upperPath = Path()
        var lowerPath = Path()
        var startedU = false
        var startedL = false
        // 计算每根 K 线 [i-period+1..i] 窗口内 close 的 mean + stdev
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        for i in (period - 1)..<n {
            let window = closes[(i - period + 1)...i]
            let mean = window.reduce(0, +) / Double(period)
            let variance = window.reduce(0) { $0 + pow($1 - mean, 2) } / Double(period)
            let stdev = sqrt(variance)
            let upper = mean + k * stdev
            let lower = mean - k * stdev
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let upperPt = CGPoint(x: centerX, y: yFor(upper))
            let lowerPt = CGPoint(x: centerX, y: yFor(lower))
            if startedU { upperPath.addLine(to: upperPt) } else { upperPath.move(to: upperPt); startedU = true }
            if startedL { lowerPath.addLine(to: lowerPt) } else { lowerPath.move(to: lowerPt); startedL = true }
        }
        ctx.stroke(upperPath, with: .color(.cyan.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
        ctx.stroke(lowerPath, with: .color(.cyan.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
    }

    // MARK: - KDJ（v15.23 batch79 · 标准 9-3-3 · 短线超买超卖 · trader 副图必备）

    /// 计算并画 K/D/J 三条线 · 标准参数 N=9 · M1=3 · M2=3
    /// - K 白色 · D 黄色 · J 紫色 · 80 / 20 水平参考线
    private func drawKDJ(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        let N = 9
        guard n >= N else { return }
        let highs = bars.map { ($0.high as NSDecimalNumber).doubleValue }
        let lows = bars.map { ($0.low as NSDecimalNumber).doubleValue }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        var ks: [Double] = []
        var ds: [Double] = []
        var js: [Double] = []
        var prevK = 50.0
        var prevD = 50.0
        for i in 0..<n {
            if i < N - 1 {
                ks.append(.nan)
                ds.append(.nan)
                js.append(.nan)
                continue
            }
            let win = (i - N + 1)...i
            let hh = highs[win].max() ?? 0
            let ll = lows[win].min() ?? 0
            let rsv = hh - ll > 0 ? (closes[i] - ll) / (hh - ll) * 100 : 50
            let k = (2.0 / 3.0) * prevK + (1.0 / 3.0) * rsv
            let d = (2.0 / 3.0) * prevD + (1.0 / 3.0) * k
            let j = 3 * k - 2 * d
            ks.append(k); ds.append(d); js.append(j)
            prevK = k; prevD = d
        }
        // 画 80/20 参考虚线（KDJ 经典超买超卖位）
        for ref in [80.0, 20.0] {
            let y = rect.maxY - CGFloat(ref / 100) * rect.height
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(path, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        // J 范围可超 0-100 · 钳制到 [0, 100] 显示（trader 看趋势 · 数值不重要）
        // 三条线：K 白 / D 黄 / J 紫
        drawKDJLine(in: ctx, rect: rect, values: ks, color: .white.opacity(0.85))
        drawKDJLine(in: ctx, rect: rect, values: ds, color: .yellow.opacity(0.85))
        drawKDJLine(in: ctx, rect: rect, values: js, color: .purple.opacity(0.85))
        // v15.23 batch82 · KDJ 金叉/死叉信号点（K 上穿/下穿 D · trader 短线核心信号）
        drawCrossSignals(in: ctx, rect: rect, fast: ks, slow: ds) { v in
            let clamped = max(0, min(100, v))
            return rect.maxY - CGFloat(clamped / 100) * rect.height
        }
    }

    private func drawKDJLine(in ctx: GraphicsContext, rect: CGRect,
                             values: [Double], color: Color) {
        let n = values.count
        guard n > 0, rect.height > 0 else { return }
        var path = Path()
        var started = false
        for i in 0..<n {
            let v = values[i]
            guard !v.isNaN else { continue }
            let clamped = max(0, min(100, v))
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = rect.maxY - CGFloat(clamped / 100) * rect.height
            let pt = CGPoint(x: centerX, y: y)
            if started {
                path.addLine(to: pt)
            } else {
                path.move(to: pt)
                started = true
            }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 0.9)
    }

    // MARK: - RSI（v15.23 batch84 · 标准 14 周期 · 30/70 超买超卖 · 趋势强弱）

    /// RSI(14) = 100 - 100 / (1 + RS) · RS = avg_gain / avg_loss · Wilder 平滑
    private func drawRSI(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        let N = 14
        guard n >= N + 1 else { return }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        var rsi: [Double] = Array(repeating: .nan, count: n)
        // 首个 RSI[N] 用 simple average · 之后 Wilder 平滑
        var gainSum = 0.0
        var lossSum = 0.0
        for i in 1...N {
            let diff = closes[i] - closes[i - 1]
            if diff >= 0 { gainSum += diff } else { lossSum -= diff }
        }
        var avgGain = gainSum / Double(N)
        var avgLoss = lossSum / Double(N)
        rsi[N] = avgLoss > 0 ? 100 - 100 / (1 + avgGain / avgLoss) : 100
        for i in (N + 1)..<n {
            let diff = closes[i] - closes[i - 1]
            let g = diff >= 0 ? diff : 0
            let l = diff < 0 ? -diff : 0
            avgGain = (avgGain * Double(N - 1) + g) / Double(N)
            avgLoss = (avgLoss * Double(N - 1) + l) / Double(N)
            rsi[i] = avgLoss > 0 ? 100 - 100 / (1 + avgGain / avgLoss) : 100
        }
        // 70 / 30 参考虚线（经典超买/超卖位）
        for ref in [70.0, 30.0] {
            let y = rect.maxY - CGFloat(ref / 100) * rect.height
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(path, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        // RSI 折线 · 青色
        drawKDJLine(in: ctx, rect: rect, values: rsi, color: .cyan.opacity(0.85))
    }

    // MARK: - CCI（v15.23 batch127 · 标准 14 周期 · ±100 超买超卖 · 期货顺势指标）

    /// CCI(14) = (TP - MA(TP, 14)) / (0.015 × MD)
    /// TP = (H+L+C)/3 · MD = mean(|TP - MA|, 窗口内)
    /// 典型范围 [-200, +200] · ±100 参考线 · 紫色与其他副图区分
    private func drawCCI(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        let N = 14
        guard n >= N else { return }
        var cci: [Double] = Array(repeating: .nan, count: n)
        for idx in (N - 1)..<n {
            let tps = bars[(idx - N + 1)...idx].map { bar -> Double in
                let h = (bar.high as NSDecimalNumber).doubleValue
                let l = (bar.low as NSDecimalNumber).doubleValue
                let c = (bar.close as NSDecimalNumber).doubleValue
                return (h + l + c) / 3
            }
            let ma = tps.reduce(0, +) / Double(N)
            let md = tps.map { abs($0 - ma) }.reduce(0, +) / Double(N)
            cci[idx] = md > 1e-9 ? (tps.last! - ma) / (0.015 * md) : 0
        }
        // 坐标系：±200 默认范围 · 极端行情自动扩展至实际 max
        let validVals = cci.compactMap { $0.isNaN ? nil : abs($0) }
        let absMax = max(200, validVals.max() ?? 200)
        let midY = rect.midY
        let halfH = rect.height / 2
        let yFor = { (v: Double) -> CGFloat in
            midY - CGFloat(v / absMax) * halfH
        }
        // ±100 参考虚线（经典超买/超卖位）
        for ref in [100.0, -100.0] {
            let y = yFor(ref)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(path, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        // 0 轴参考线
        var zeroPath = Path()
        zeroPath.move(to: CGPoint(x: rect.minX, y: midY))
        zeroPath.addLine(to: CGPoint(x: rect.maxX, y: midY))
        ctx.stroke(zeroPath, with: .color(.secondary.opacity(0.5)), lineWidth: 0.4)
        // CCI 折线 · 紫色（与 KDJ/MACD/RSI/OI/ATR 区分）
        var path = Path()
        var started = false
        for i in 0..<n where !cci[i].isNaN {
            let x = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(cci[i])
            if !started {
                path.move(to: CGPoint(x: x, y: y)); started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(path, with: .color(.purple.opacity(0.9)), lineWidth: 0.9)
    }

    // MARK: - W%R（v15.23 batch137 · 14 周期 · -20 超买 / -80 超卖 · 短线反转信号）

    /// W%R = -100 × (Hn - C) / (Hn - Ln) · 范围 [-100, 0]
    private func drawWR(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        let N = 14
        guard n >= N else { return }
        var wr: [Double] = Array(repeating: .nan, count: n)
        for idx in (N - 1)..<n {
            let window = bars[(idx - N + 1)...idx]
            let hn = window.map { ($0.high as NSDecimalNumber).doubleValue }.max() ?? 0
            let ln = window.map { ($0.low as NSDecimalNumber).doubleValue }.min() ?? 0
            let c = (bars[idx].close as NSDecimalNumber).doubleValue
            wr[idx] = (hn - ln) > 1e-9 ? -100 * (hn - c) / (hn - ln) : -50
        }
        // 坐标系固定 [-100, 0]（W%R 数学界定 · 不需要自适应）
        let yFor = { (v: Double) -> CGFloat in
            // -100 → bottom · 0 → top · 反向（v 越大 y 越小）
            rect.minY + CGFloat((-v) / 100) * rect.height
        }
        // -20 / -80 参考虚线
        for ref in [-20.0, -80.0] {
            let y = yFor(ref)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(path, with: .color(.secondary.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        }
        // W%R 折线 · 青绿色 teal（与 RSI cyan / CCI purple 区分）
        var path = Path()
        var started = false
        for i in 0..<n where !wr[i].isNaN {
            let x = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(wr[i])
            if !started {
                path.move(to: CGPoint(x: x, y: y)); started = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(path, with: .color(.teal.opacity(0.9)), lineWidth: 0.9)
    }

    // MARK: - 金叉/死叉信号点（v15.23 batch82 · KDJ + MACD 共用 · trader 副图核心信号）

    /// fast 上穿 slow → 金叉（红圆点）· fast 下穿 slow → 死叉（绿圆点）
    /// - 圆点画在交叉点 · yFor closure 由调用方注入（KDJ/MACD 各自坐标系）
    private func drawCrossSignals(in ctx: GraphicsContext, rect: CGRect,
                                  fast: [Double], slow: [Double],
                                  yFor: (Double) -> CGFloat) {
        let n = min(fast.count, slow.count)
        guard n >= 2 else { return }
        let dotSize: CGFloat = 5
        for i in 1..<n {
            let f0 = fast[i - 1]
            let f1 = fast[i]
            let s0 = slow[i - 1]
            let s1 = slow[i]
            guard !f0.isNaN, !f1.isNaN, !s0.isNaN, !s1.isNaN else { continue }
            let crossUp = f0 <= s0 && f1 > s1     // 金叉
            let crossDown = f0 >= s0 && f1 < s1   // 死叉
            guard crossUp || crossDown else { continue }
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = yFor((f1 + s1) / 2)
            let dot = CGRect(
                x: centerX - dotSize / 2,
                y: y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            ctx.fill(Path(ellipseIn: dot),
                     with: .color(crossUp ? .red : .green))
            ctx.stroke(Path(ellipseIn: dot),
                       with: .color(.white.opacity(0.9)),
                       lineWidth: 0.6)
        }
    }

    // MARK: - MACD（v15.23 batch80 · 标准 12-26-9 · DIF/DEA 双线 + 红绿柱 · 中长线必看）

    /// 计算并画 MACD：DIF（白）+ DEA（黄）+ MACD 柱（红/绿）
    /// 标准参数：fast=12 · slow=26 · signal=9
    private func drawMACD(in ctx: GraphicsContext, rect: CGRect) {
        let n = bars.count
        guard n >= 26 + 9 else { return }
        let closes = bars.map { ($0.close as NSDecimalNumber).doubleValue }
        let ema12 = ema(closes, period: 12)
        let ema26 = ema(closes, period: 26)
        var dif: [Double] = Array(repeating: .nan, count: n)
        for i in 0..<n where !ema12[i].isNaN && !ema26[i].isNaN {
            dif[i] = ema12[i] - ema26[i]
        }
        let dea = ema(dif, period: 9)
        var macd: [Double] = Array(repeating: .nan, count: n)
        for i in 0..<n where !dif[i].isNaN && !dea[i].isNaN {
            macd[i] = (dif[i] - dea[i]) * 2
        }
        // 找 max abs(value) for symmetric 0-axis layout（柱 + 双线）
        let allVals = dif + dea + macd
        let absMax = allVals.compactMap { $0.isNaN ? nil : abs($0) }.max() ?? 1
        guard absMax > 0 else { return }
        // 0 轴在 rect 中线 · 上半 = +absMax / 下半 = -absMax
        let midY = rect.midY
        let halfH = rect.height / 2
        let yFor = { (v: Double) -> CGFloat in
            midY - CGFloat(v / absMax) * halfH
        }
        // 0 轴参考线
        var zeroPath = Path()
        zeroPath.move(to: CGPoint(x: rect.minX, y: midY))
        zeroPath.addLine(to: CGPoint(x: rect.maxX, y: midY))
        ctx.stroke(zeroPath, with: .color(.secondary.opacity(0.4)),
                   style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
        // MACD 柱（红涨 / 绿跌 · 中国习惯）
        let barWidth = max(1.5, rect.width / CGFloat(n) * 0.7)
        for i in 0..<n where !macd[i].isNaN {
            let v = macd[i]
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let y = yFor(v)
            let h = abs(midY - y)
            let color: Color = v >= 0 ? .red.opacity(0.7) : .green.opacity(0.7)
            let r = CGRect(
                x: centerX - barWidth / 2,
                y: min(midY, y),
                width: barWidth,
                height: max(1, h)
            )
            ctx.fill(Path(r), with: .color(color))
        }
        // DIF 白线 + DEA 黄线
        drawMACDLine(in: ctx, rect: rect, values: dif, yFor: yFor, color: .white.opacity(0.85))
        drawMACDLine(in: ctx, rect: rect, values: dea, yFor: yFor, color: .yellow.opacity(0.85))
        // v15.23 batch82 · MACD 金叉/死叉信号点（DIF 上穿/下穿 DEA · 趋势核心信号）
        drawCrossSignals(in: ctx, rect: rect, fast: dif, slow: dea, yFor: yFor)
    }

    private func drawMACDLine(in ctx: GraphicsContext, rect: CGRect,
                              values: [Double], yFor: (Double) -> CGFloat, color: Color) {
        let n = values.count
        var path = Path()
        var started = false
        for i in 0..<n {
            let v = values[i]
            guard !v.isNaN else { continue }
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let pt = CGPoint(x: centerX, y: yFor(v))
            if started {
                path.addLine(to: pt)
            } else {
                path.move(to: pt)
                started = true
            }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 0.9)
    }

    /// EMA 工具 · 首个非 NaN 值作 seed · 后续指数加权
    /// 输入数组允许含 NaN（来自 dif 数组的 warmup 期）· 输出对齐索引
    private func ema(_ values: [Double], period: Int) -> [Double] {
        let n = values.count
        var out: [Double] = Array(repeating: .nan, count: n)
        let alpha = 2.0 / (Double(period) + 1)
        var prev: Double? = nil
        for i in 0..<n {
            let v = values[i]
            guard !v.isNaN else { continue }
            if let p = prev {
                let cur = v * alpha + p * (1 - alpha)
                out[i] = cur
                prev = cur
            } else {
                out[i] = v
                prev = v
            }
        }
        return out
    }

    // MARK: - Volume

    private func drawVolumes(in ctx: GraphicsContext, rect: CGRect) {
        let volumes = bars.map { Double($0.volume) }
        guard let maxVol = volumes.max(), maxVol > 0 else { return }

        let n = bars.count
        let barWidth = max(1.5, rect.width / CGFloat(n) * 0.7)

        for (i, bar) in bars.enumerated() {
            let vol = Double(bar.volume)
            let h = CGFloat(vol / maxVol) * rect.height
            let centerX = rect.minX + (CGFloat(i) + 0.5) * rect.width / CGFloat(n)
            let close = (bar.close as NSDecimalNumber).doubleValue
            let open = (bar.open as NSDecimalNumber).doubleValue
            let color: Color = close >= open ? .red.opacity(0.6) : .green.opacity(0.6)
            let volRect = CGRect(
                x: centerX - barWidth / 2,
                y: rect.maxY - h,
                width: barWidth,
                height: h
            )
            ctx.fill(Path(volRect), with: .color(color))
        }
    }
}

// MARK: - Mock K 线生成（独立 cell · seed 按 instrumentID + period 决定 · 同 cell 稳定）

enum MultiChartMockData {

    /// 按 instrumentID + period 生成稳定 mock K 线（120 根 · 不同合约/周期波动幅度有差异）
    /// - Parameter tickSeed: v15.23 batch56 · 每秒变化的 seed offset · 让最末根 K 线 close 微动模拟 tick
    static func bars(instrumentID: String, period: KLinePeriod, count: Int = 120,
                     tickSeed: UInt64 = 0) -> [KLine] {
        let basePrice = basePriceFor(instrumentID)
        let volatility = volatilityFor(instrumentID, period: period)
        // 用 hashable 当 seed · 同 (id, period) 重新打开看到一样的图
        var rng = SeededRNG(seed: UInt64(abs(instrumentID.hashValue ^ period.rawValue.hashValue)))
        var bars: [KLine] = []
        bars.reserveCapacity(count)
        var price = basePrice
        let secondsPerBar = max(60, period.seconds)
        for i in 0..<count {
            let drift = Double.random(in: -volatility...volatility, using: &rng)
            let open = price
            var close = max(basePrice * 0.5, price + drift)
            // v15.23 batch56 · 末根 K 线注入 tick 抖动（≤ 0.3×volatility · 不破坏整体走势）
            if i == count - 1, tickSeed != 0 {
                var tickRng = SeededRNG(seed: tickSeed ^ rng.state)
                let tickDrift = Double.random(in: -volatility * 0.3...volatility * 0.3, using: &tickRng)
                close = max(basePrice * 0.5, close + tickDrift)
            }
            let wickRange = volatility * 0.6
            let high = max(open, close) + Double.random(in: 0...wickRange, using: &rng)
            let low = min(open, close) - Double.random(in: 0...wickRange, using: &rng)
            let volume = Int.random(in: 800...4000, using: &rng)
            // v15.23 batch87 · mock OI · 跟随趋势缓慢累积 + 随机抖动（让 OI 副图非平线）
            // 真行情 Sina 提供 openInterest · mock 仅用于 UI demo
            let oiBase = 100_000 + (i * 50) // 缓慢累积
            let oiNoise = Int.random(in: -2000...3000, using: &rng)
            let oi = max(0, oiBase + oiNoise)
            bars.append(KLine(
                instrumentID: instrumentID,
                period: period,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * secondsPerBar)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: volume,
                openInterest: Decimal(oi),
                turnover: 0
            ))
            price = close
        }
        return bars
    }

    private static func basePriceFor(_ id: String) -> Double {
        switch id {
        case "RB0":  return 3500
        case "IF0":  return 3800
        case "AU0":  return 480
        case "CU0":  return 70000
        case "I0":   return 800
        case "MA0":  return 16000
        default:     return 3000
        }
    }

    private static func volatilityFor(_ id: String, period: KLinePeriod) -> Double {
        let base = basePriceFor(id)
        let pctPerBar: Double
        switch period {
        case .minute1, .minute3, .minute5: pctPerBar = 0.0015
        case .minute15, .minute30:         pctPerBar = 0.003
        case .hour1, .hour2:               pctPerBar = 0.005
        case .hour4, .daily:               pctPerBar = 0.01
        default:                           pctPerBar = 0.002
        }
        return base * pctPerBar
    }

    /// 简单 LCG · 给同 (id, period) 稳定结果（@AppStorage 重启看到一样的图）
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed | 1 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

#endif
