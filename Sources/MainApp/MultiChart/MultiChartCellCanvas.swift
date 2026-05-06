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

    init(bars: [KLine], showVolume: Bool,
         hoveredIndex: Int? = nil,
         onHoverIndexChange: ((Int?) -> Void)? = nil,
         showIndicators: Bool = true,
         showBoll: Bool = false,
         subChart: MultiChartSubChartType = .volume) {
        self.bars = bars
        self.showVolume = showVolume
        self.hoveredIndex = hoveredIndex
        self.onHoverIndexChange = onHoverIndexChange
        self.showIndicators = showIndicators
        self.showBoll = showBoll
        self.subChart = subChart
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
                drawCandles(in: ctx, rect: priceRect)
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
                    }
                }
                // v15.23 batch77 · 简洁 axis 标签（时间 3 + 价格 3 · 不喧宾夺主）
                drawAxisLabels(in: ctx, priceRect: priceRect, bottomY: size.height)
                // v15.23 batch68 · 联动十字线（垂直 vertical line at hovered index · 跨 cell 同步）
                if let hidx = hoveredIndex, hidx >= 0, hidx < bars.count {
                    let centerX = priceRect.minX + (CGFloat(hidx) + 0.5) * priceRect.width / CGFloat(bars.count)
                    var line = Path()
                    line.move(to: CGPoint(x: centerX, y: 0))
                    line.addLine(to: CGPoint(x: centerX, y: size.height))
                    ctx.stroke(line, with: .color(.accentColor.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    // 顶部小标签：bar index + close
                    let bar = bars[hidx]
                    let close = (bar.close as NSDecimalNumber).doubleValue
                    let label = "[\(hidx + 1)] \(String(format: "%.2f", close))"
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
                    let n = bars.count
                    guard n > 0, geo.size.width > 0 else { return }
                    let normalized = max(0, min(1, location.x / geo.size.width))
                    let idx = min(n - 1, Int(normalized * CGFloat(n)))
                    cb(idx)
                case .ended:
                    cb(nil)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
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
        let opens = bars.map { (bars[0].open as NSDecimalNumber).doubleValue }
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
            if i == n - 1 {
                ctx.stroke(Path(bodyRect.insetBy(dx: -0.5, dy: -0.5)),
                           with: .color(.white.opacity(0.85)),
                           lineWidth: 1)
                let dotSize: CGFloat = 4
                let dotRect = CGRect(
                    x: centerX - dotSize / 2,
                    y: yFor(close) - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
                ctx.stroke(Path(ellipseIn: dotRect),
                           with: .color(.white.opacity(0.9)),
                           lineWidth: 0.7)
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
                let txt = Text(String(format: "%.2f", price))
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
            bars.append(KLine(
                instrumentID: instrumentID,
                period: period,
                openTime: Date(timeIntervalSince1970: TimeInterval(i * secondsPerBar)),
                open: Decimal(open),
                high: Decimal(high),
                low: Decimal(low),
                close: Decimal(close),
                volume: volume,
                openInterest: 0,
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
