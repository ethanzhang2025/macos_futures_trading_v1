// ChartCore · 主图横竖网格（半透明灰线 · 与 KLineAxisView 标签对齐）
//
// 设计：
// - 与 KLineAxisView 共用 5 等距规则 · 价格 5 条横线 + 时间 5 条竖线
// - 半透明（白 0.08）· 不抢 K 线视觉 · 仅作背景结构提示
// - 纯 SwiftUI · 与 KLineMetalView 在同 ZStack 叠加 · 不进 Metal 渲染管线

#if canImport(SwiftUI)

import SwiftUI

public struct KLineGridView: View {

    /// 与 KLineAxisView.labelCount 一致 · 视觉对齐
    public static let lineCount = 5

    public init() {}

    public var body: some View {
        GeometryReader { geom in
            ZStack {
                // 横线（5 条 · 价格刻度对齐）
                ForEach(0..<Self.lineCount, id: \.self) { i in
                    let t = CGFloat(i) / CGFloat(max(1, Self.lineCount - 1))
                    Path { p in
                        let y = t * geom.size.height
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geom.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                // 竖线（5 条 · 时间刻度对齐）
                ForEach(0..<Self.lineCount, id: \.self) { i in
                    let t = CGFloat(i) / CGFloat(max(1, Self.lineCount - 1))
                    Path { p in
                        let x = t * geom.size.width
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geom.size.height))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
            .allowsHitTesting(false)  // 不挡 K 线区 gesture（pan/zoom 直达 KLineMetalView）
        }
    }
}

#endif
