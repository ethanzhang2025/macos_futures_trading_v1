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
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            // v15.85 原始设计 · alignment .top + offset y:-32 显示在按钮上方
            // v17.199 仅改 background 颜色：旧 .regularMaterial 在深色 chart 对比弱致「模糊白字」
            // 改 Color.black.opacity(0.92) 不透明深色 + .white 文字 · 任何背景下都清晰
            .overlay(alignment: .top) {
                if isHovering, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .fixedSize()
                        .offset(y: -32)
                        .zIndex(1000)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// 立即显示 tooltip · 不走 macOS 系统 .help 延迟（v15.85）
    func tooltip(_ text: String) -> some View {
        modifier(InstantTooltip(text: text))
    }
}

#endif
