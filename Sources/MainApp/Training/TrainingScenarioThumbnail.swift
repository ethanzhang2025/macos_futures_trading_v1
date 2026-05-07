// WP-54 v15.23 batch116 · 训练场景 K 线 thumbnail（SwiftUI Canvas · macOS-only）
//
// 用途：训练面板 startSheet 选预设时 · 在场景描述卡右侧显示 100×40pt mini K 线
// trader 一眼看懂走势特征（震荡/趋势/V 反 等 9 种）→ 决定要不要练
//
// 设计：
// - 数据由 TrainingScenarioThumbnailGenerator 合成（TradingCore · 跨平台已测）
// - 涨红跌绿（中国期货习惯 · 与主图配色一致）
// - 末根突出（带 close dot · 与 multichart cell 末根高亮风格一致）
// - 无 axis / 无文字 · 极简 mini-chart · 节省 sheet 空间

#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import TradingCore

struct TrainingScenarioThumbnail: View {
    let pattern: TrainingScenarioPattern
    let seed: UInt64
    let size: CGSize

    var body: some View {
        Canvas { ctx, canvasSize in
            let bars = TrainingScenarioThumbnailGenerator.bars(for: pattern, seed: seed)
            guard !bars.isEmpty else { return }
            let highs = bars.map(\.high)
            let lows  = bars.map(\.low)
            let maxP  = highs.max() ?? 1
            let minP  = lows.min()  ?? 0
            let range = max(maxP - minP, 1e-6)
            let n = bars.count
            let barWidth = canvasSize.width / CGFloat(n)
            let candleWidth = max(barWidth * 0.7, 0.8)

            for (i, bar) in bars.enumerated() {
                let xCenter = CGFloat(i) * barWidth + barWidth / 2
                let yHigh  = CGFloat(1 - (bar.high  - minP) / range) * canvasSize.height
                let yLow   = CGFloat(1 - (bar.low   - minP) / range) * canvasSize.height
                let yOpen  = CGFloat(1 - (bar.open  - minP) / range) * canvasSize.height
                let yClose = CGFloat(1 - (bar.close - minP) / range) * canvasSize.height

                // 涨红跌绿（中国期货习惯）
                let color: Color = bar.isUp ? .red : .green

                // wick（细线）
                var wick = Path()
                wick.move(to: CGPoint(x: xCenter, y: yHigh))
                wick.addLine(to: CGPoint(x: xCenter, y: yLow))
                ctx.stroke(wick, with: .color(color), lineWidth: 0.5)

                // body（实心矩形 · 至少 0.8pt 高度防 doji 不可见）
                let bodyTop = min(yOpen, yClose)
                let bodyHeight = max(abs(yOpen - yClose), 0.8)
                let body = CGRect(x: xCenter - candleWidth / 2,
                                  y: bodyTop,
                                  width: candleWidth,
                                  height: bodyHeight)
                ctx.fill(Path(body), with: .color(color))

                // 末根 close dot（视觉锚点 · 与 multichart 风格一致）
                if i == n - 1 {
                    let dotSize: CGFloat = 2.5
                    let dot = CGRect(x: xCenter - dotSize / 2,
                                     y: yClose - dotSize / 2,
                                     width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: dot), with: .color(color))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .cornerRadius(3)
        .help("\(pattern.displayName) 形态预览（mock 60 根 K 线）")
    }
}
#endif
