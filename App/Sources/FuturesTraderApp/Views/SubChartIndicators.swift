import SwiftUI
import MarketData

/// 副图指标类型
enum SubChartType: String, CaseIterable {
    case macd = "MACD"
    case kdj = "KDJ"
    case rsi = "RSI"
}

/// 副图指标计算与绘制
enum SubChartRenderer {

    // MARK: - MACD

    struct MACDData {
        let dif: [Double?], dea: [Double?], macd: [Double?]
    }

    static func calcMACD(_ closes: [Double]) -> MACDData {
        let ema12 = ema(closes, 12), ema26 = ema(closes, 26)
        var dif = [Double?](repeating: nil, count: closes.count)
        for i in 0..<closes.count {
            if let e12 = ema12[i], let e26 = ema26[i] { dif[i] = e12 - e26 }
        }
        let difVals = dif.compactMap { $0 }
        let deaAll = ema(difVals, 9)
        var dea = [Double?](repeating: nil, count: closes.count)
        var idx = 0
        for i in 0..<closes.count {
            if dif[i] != nil { dea[i] = idx < deaAll.count ? deaAll[idx] : nil; idx += 1 }
        }
        var macd = [Double?](repeating: nil, count: closes.count)
        for i in 0..<closes.count {
            if let d = dif[i], let e = dea[i] { macd[i] = 2 * (d - e) }
        }
        return MACDData(dif: dif, dea: dea, macd: macd)
    }

    static func drawMACD(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar], padding: CGFloat, hoverIndex: Int?) {
        guard bars.count >= 2 else { return }
        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let data = calcMACD(closes)

        let chartW = size.width - padding * 2, chartH = size.height - 10, topPad: CGFloat = 14
        let barW = chartW / CGFloat(bars.count), stickW = max(1, barW * 0.55)

        var allVals: [Double] = []
        for i in 0..<bars.count {
            if let d = data.dif[i] { allVals.append(d) }
            if let e = data.dea[i] { allVals.append(e) }
            if let m = data.macd[i] { allVals.append(m) }
        }
        guard let maxV = allVals.max(), let minV = allVals.min() else { return }
        let absMax = max(abs(maxV), abs(minV), 0.01)
        let midY = topPad + (chartH - topPad) / 2
        let scale = (chartH - topPad) / 2 / CGFloat(absMax)

        // 零轴
        var zl = Path(); zl.move(to: CGPoint(x: padding, y: midY)); zl.addLine(to: CGPoint(x: size.width - padding, y: midY))
        context.stroke(zl, with: .color(Theme.gridLine), lineWidth: 0.5)

        // 柱状图
        for i in 0..<bars.count {
            guard let m = data.macd[i] else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            let h = CGFloat(abs(m)) * scale
            let y = m >= 0 ? midY - h : midY
            context.fill(Path(CGRect(x: x - stickW / 2, y: y, width: stickW, height: max(1, h))), with: .color(m >= 0 ? Theme.up : Theme.down))
        }

        drawLine(context: context, values: data.dif, color: Theme.ma5, barW: barW, padding: padding, midY: midY, scale: scale)
        drawLine(context: context, values: data.dea, color: Theme.ma20, barW: barW, padding: padding, midY: midY, scale: scale)

        context.draw(Text("MACD(12,26,9)").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 40, y: 5))
        context.draw(Text("DIF").font(.system(size: 9)).foregroundColor(Theme.ma5), at: CGPoint(x: padding + 100, y: 5))
        context.draw(Text("DEA").font(.system(size: 9)).foregroundColor(Theme.ma20), at: CGPoint(x: padding + 125, y: 5))

        drawVCrosshair(context: context, size: size, bars: bars, padding: padding, hoverIndex: hoverIndex)
    }

    // MARK: - KDJ

    struct KDJData {
        let k: [Double?], d: [Double?], j: [Double?]
    }

    static func calcKDJ(_ bars: [SinaKLineBar], n: Int = 9, m1: Int = 3, m2: Int = 3) -> KDJData {
        let count = bars.count
        var rsv = [Double?](repeating: nil, count: count)
        for i in 0..<count {
            let start = max(0, i - n + 1)
            var hn: Double = -.infinity, ln: Double = .infinity
            for j in start...i {
                let h = NSDecimalNumber(decimal: bars[j].high).doubleValue
                let l = NSDecimalNumber(decimal: bars[j].low).doubleValue
                hn = max(hn, h); ln = min(ln, l)
            }
            let c = NSDecimalNumber(decimal: bars[i].close).doubleValue
            rsv[i] = (hn - ln) > 0 ? (c - ln) / (hn - ln) * 100 : 50
        }
        var k = [Double?](repeating: nil, count: count)
        var d = [Double?](repeating: nil, count: count)
        var j = [Double?](repeating: nil, count: count)
        var prevK = 50.0, prevD = 50.0
        for i in 0..<count {
            guard let r = rsv[i] else { continue }
            let curK = (Double(m1 - 1) * prevK + r) / Double(m1)
            let curD = (Double(m2 - 1) * prevD + curK) / Double(m2)
            k[i] = curK; d[i] = curD; j[i] = 3 * curK - 2 * curD
            prevK = curK; prevD = curD
        }
        return KDJData(k: k, d: d, j: j)
    }

    static func drawKDJ(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar], padding: CGFloat, hoverIndex: Int?) {
        guard bars.count >= 2 else { return }
        let data = calcKDJ(bars)

        let chartW = size.width - padding * 2, chartH = size.height - 10, topPad: CGFloat = 14
        let barW = chartW / CGFloat(bars.count)

        // 范围 0-100
        let sY: (Double) -> CGFloat = { v in topPad + (chartH - topPad) * CGFloat(1 - v / 100) }

        // 网格 20/50/80
        for level in [20.0, 50.0, 80.0] {
            let y = sY(level)
            var p = Path(); p.move(to: CGPoint(x: padding, y: y)); p.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(p, with: .color(Theme.gridLine), lineWidth: 0.5)
            context.draw(Text(String(format: "%.0f", level)).font(.system(size: 8, design: .monospaced)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: size.width - padding + 5, y: y), anchor: .leading)
        }

        let kColor = Theme.ma5
        let dColor = Theme.ma20
        let jColor = Color(red: 0.95, green: 0.45, blue: 0.85) // 粉紫

        drawLineScaled(context: context, values: data.k, color: kColor, barW: barW, padding: padding, sY: sY)
        drawLineScaled(context: context, values: data.d, color: dColor, barW: barW, padding: padding, sY: sY)
        drawLineScaled(context: context, values: data.j, color: jColor, barW: barW, padding: padding, sY: sY)

        context.draw(Text("KDJ(9,3,3)").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 35, y: 5))
        context.draw(Text("K").font(.system(size: 9)).foregroundColor(kColor), at: CGPoint(x: padding + 85, y: 5))
        context.draw(Text("D").font(.system(size: 9)).foregroundColor(dColor), at: CGPoint(x: padding + 100, y: 5))
        context.draw(Text("J").font(.system(size: 9)).foregroundColor(jColor), at: CGPoint(x: padding + 115, y: 5))

        drawVCrosshair(context: context, size: size, bars: bars, padding: padding, hoverIndex: hoverIndex)
    }

    // MARK: - RSI

    static func calcRSI(_ closes: [Double], period: Int = 14) -> [Double?] {
        let count = closes.count
        var rsi = [Double?](repeating: nil, count: count)
        guard count > 1 else { return rsi }
        var avgGain = 0.0, avgLoss = 0.0
        for i in 1..<count {
            let change = closes[i] - closes[i - 1]
            let gain = max(0, change), loss = max(0, -change)
            if i < period {
                avgGain += gain; avgLoss += loss
            } else if i == period {
                avgGain = (avgGain + gain) / Double(period)
                avgLoss = (avgLoss + loss) / Double(period)
                rsi[i] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)
            } else {
                avgGain = (avgGain * Double(period - 1) + gain) / Double(period)
                avgLoss = (avgLoss * Double(period - 1) + loss) / Double(period)
                rsi[i] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss)
            }
        }
        return rsi
    }

    static func drawRSI(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar], padding: CGFloat, hoverIndex: Int?) {
        guard bars.count >= 2 else { return }
        let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
        let rsi6 = calcRSI(closes, period: 6)
        let rsi14 = calcRSI(closes, period: 14)
        let rsi24 = calcRSI(closes, period: 24)

        let chartW = size.width - padding * 2, chartH = size.height - 10, topPad: CGFloat = 14
        let barW = chartW / CGFloat(bars.count)
        let sY: (Double) -> CGFloat = { v in topPad + (chartH - topPad) * CGFloat(1 - v / 100) }

        // 超买超卖线
        for level in [20.0, 50.0, 80.0] {
            let y = sY(level)
            var p = Path(); p.move(to: CGPoint(x: padding, y: y)); p.addLine(to: CGPoint(x: size.width - padding, y: y))
            context.stroke(p, with: .color(Theme.gridLine), lineWidth: 0.5)
            context.draw(Text(String(format: "%.0f", level)).font(.system(size: 8, design: .monospaced)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: size.width - padding + 5, y: y), anchor: .leading)
        }

        let c6 = Theme.ma5
        let c14 = Theme.ma20
        let c24 = Color(red: 0.95, green: 0.45, blue: 0.85)

        drawLineScaled(context: context, values: rsi6, color: c6, barW: barW, padding: padding, sY: sY)
        drawLineScaled(context: context, values: rsi14, color: c14, barW: barW, padding: padding, sY: sY)
        drawLineScaled(context: context, values: rsi24, color: c24, barW: barW, padding: padding, sY: sY)

        context.draw(Text("RSI").font(.system(size: 9)).foregroundColor(Theme.textMuted), at: CGPoint(x: padding + 15, y: 5))
        context.draw(Text("6").font(.system(size: 9)).foregroundColor(c6), at: CGPoint(x: padding + 40, y: 5))
        context.draw(Text("14").font(.system(size: 9)).foregroundColor(c14), at: CGPoint(x: padding + 55, y: 5))
        context.draw(Text("24").font(.system(size: 9)).foregroundColor(c24), at: CGPoint(x: padding + 75, y: 5))

        drawVCrosshair(context: context, size: size, bars: bars, padding: padding, hoverIndex: hoverIndex)
    }

    // MARK: - 通用

    private static func ema(_ values: [Double], _ period: Int) -> [Double?] {
        var r = [Double?](repeating: nil, count: values.count)
        let k = 2.0 / Double(period + 1)
        var prev: Double?
        for i in 0..<values.count {
            if prev == nil { prev = values[i] } else { prev = k * values[i] + (1 - k) * prev! }
            r[i] = prev
        }
        return r
    }

    private static func drawLine(context: GraphicsContext, values: [Double?], color: Color, barW: CGFloat, padding: CGFloat, midY: CGFloat, scale: CGFloat) {
        var path = Path(); var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            let y = midY - CGFloat(v) * scale
            if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private static func drawLineScaled(context: GraphicsContext, values: [Double?], color: Color, barW: CGFloat, padding: CGFloat, sY: (Double) -> CGFloat) {
        var path = Path(); var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let x = padding + CGFloat(i) * barW + barW / 2
            let y = sY(v)
            if !started { path.move(to: CGPoint(x: x, y: y)); started = true }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private static func drawVCrosshair(context: GraphicsContext, size: CGSize, bars: [SinaKLineBar], padding: CGFloat, hoverIndex: Int?) {
        guard let idx = hoverIndex, idx >= 0, idx < bars.count else { return }
        let barW = (size.width - padding * 2) / CGFloat(bars.count)
        let x = padding + CGFloat(idx) * barW + barW / 2
        var vl = Path(); vl.move(to: CGPoint(x: x, y: 0)); vl.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(vl, with: .color(Theme.crosshair), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
    }

    /// 获取悬浮时的副图指标文本
    static func hoverText(type: SubChartType, bars: [SinaKLineBar], index: Int) -> [(String, String, Color)] {
        switch type {
        case .macd:
            let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
            let data = calcMACD(closes)
            guard index < data.dif.count else { return [] }
            var items: [(String, String, Color)] = []
            if let d = data.dif[index] { items.append(("DIF", String(format: "%.1f", d), Theme.ma5)) }
            if let e = data.dea[index] { items.append(("DEA", String(format: "%.1f", e), Theme.ma20)) }
            if let m = data.macd[index] { items.append(("MACD", String(format: "%.1f", m), m >= 0 ? Theme.up : Theme.down)) }
            return items
        case .kdj:
            let data = calcKDJ(bars)
            guard index < data.k.count else { return [] }
            var items: [(String, String, Color)] = []
            if let k = data.k[index] { items.append(("K", String(format: "%.1f", k), Theme.ma5)) }
            if let d = data.d[index] { items.append(("D", String(format: "%.1f", d), Theme.ma20)) }
            if let j = data.j[index] { items.append(("J", String(format: "%.1f", j), Color(red: 0.95, green: 0.45, blue: 0.85))) }
            return items
        case .rsi:
            let closes = bars.map { NSDecimalNumber(decimal: $0.close).doubleValue }
            let r6 = calcRSI(closes, period: 6)
            let r14 = calcRSI(closes, period: 14)
            guard index < r6.count else { return [] }
            var items: [(String, String, Color)] = []
            if let v = r6[index] { items.append(("RSI6", String(format: "%.1f", v), Theme.ma5)) }
            if let v = r14[index] { items.append(("RSI14", String(format: "%.1f", v), Theme.ma20)) }
            return items
        }
    }
}
