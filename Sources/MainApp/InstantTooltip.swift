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
            .overlay(alignment: .top) {
                if isHovering, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
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
