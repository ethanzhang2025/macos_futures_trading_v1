// 立即显示 tooltip（替代 SwiftUI .help() macOS 系统 ~1.5s 延迟 · v15.85）
//
// 用法：替换 .help("文案") → .tooltip("文案")
// 行为：onHover 进入立即显示 · 离开立即隐藏 · 不影响点击
//
// 设计要点：
// - allowsHitTesting(false) 让 tooltip 不阻挡按钮点击
// - zIndex(1000) 防被同 HStack 邻居 clip
// - fixedSize() 让 Text 按内容宽度展开 · 不被父 frame 限制
// - offset(y: -32) 显示在按钮上方 · 与按钮中心对齐

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

struct InstantTooltip: ViewModifier {
    let text: String
    let edge: VerticalEdge   // v17.199 · 默认 .bottom · toolbar 顶部按钮上方 32px 是 window 外被裁
    @State private var isHovering = false

    private var overlayAlignment: Alignment { edge == .top ? .top : .bottom }
    private var verticalOffset: CGFloat { edge == .top ? -32 : 32 }

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(alignment: overlayAlignment) {
                if isHovering, !text.isEmpty {
                    Text(text)
                        // v17.199 · 强制深色背景 + 白字 · 旧版 .regularMaterial 在深色 chart 上对比弱致「模糊白字」
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .fixedSize()
                        .offset(y: verticalOffset)
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// 立即显示 tooltip · 不走 macOS 系统 .help 延迟（v15.85）
    /// v17.199 · edge 参数：toolbar 顶部按钮用默认 .bottom · 底部 replay/控件栏用 .top
    func tooltip(_ text: String, edge: VerticalEdge = .bottom) -> some View {
        modifier(InstantTooltip(text: text, edge: edge))
    }
}

#endif
