// v16.155 · 5 维五边形雷达图共享 view
// 抽自 TrainingScoreSheet.radarChart（v16.14） · 让 HistoryPanel 等也可复用渲染
// Canvas 顶部从 pnl 顺时针 · 0-100 → 半径 0..maxR · 最弱维度橙色加粗

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import TradingCore

struct FiveDimRadarChart: View {
    let sub: TrainingSubScores

    var body: some View {
        let dims = sub.ordered
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2 - 18
            let n = dims.count
            let angleStep = 2 * Double.pi / Double(n)
            let startAngle = -Double.pi / 2
            func vertex(_ i: Int, ratio: Double) -> CGPoint {
                let a = startAngle + angleStep * Double(i)
                return CGPoint(x: center.x + CGFloat(cos(a)) * CGFloat(maxR * ratio),
                               y: center.y + CGFloat(sin(a)) * CGFloat(maxR * ratio))
            }
            func polygon(ratio: Double) -> Path {
                var p = Path()
                for i in 0..<n {
                    let pt = vertex(i, ratio: ratio)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                return p
            }
            ctx.stroke(polygon(ratio: 1.0), with: .color(.secondary.opacity(0.30)), lineWidth: 1)
            for ratio in [0.25, 0.50, 0.75] {
                ctx.stroke(polygon(ratio: ratio), with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
            for i in 0..<n {
                var line = Path()
                line.move(to: center)
                line.addLine(to: vertex(i, ratio: 1.0))
                ctx.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
            var scorePath = Path()
            for (i, entry) in dims.enumerated() {
                let pt = vertex(i, ratio: Double(entry.score) / 100.0)
                if i == 0 { scorePath.move(to: pt) } else { scorePath.addLine(to: pt) }
            }
            scorePath.closeSubpath()
            ctx.fill(scorePath, with: .color(.blue.opacity(0.18)))
            ctx.stroke(scorePath, with: .color(.blue), lineWidth: 1.5)
            for (i, entry) in dims.enumerated() {
                let pt = vertex(i, ratio: Double(entry.score) / 100.0)
                let isWeakest = entry.dimension == sub.weakest
                let dotR: CGFloat = isWeakest ? 3.5 : 2.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x - dotR, y: pt.y - dotR,
                                           width: dotR * 2, height: dotR * 2)),
                    with: .color(isWeakest ? .orange : .blue)
                )
            }
            for (i, entry) in dims.enumerated() {
                let label = vertex(i, ratio: 1.0 + 14.0 / maxR)
                ctx.draw(Text(entry.dimension.emoji).font(.system(size: 13)), at: label)
            }
        }
    }
}

#endif
