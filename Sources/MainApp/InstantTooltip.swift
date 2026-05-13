// v15.85 原版自定 SwiftUI overlay tooltip · 在普通 chart window 工作正常
// v17.200 反弹：Shell 嵌入模式（v17.6+）顶部加了 PrimaryTabBar · tooltip 显示在 toolbar 上方 32px
//   恰被 PrimaryTabBar 半透明覆盖 · 用户看到「模糊白字」
// v17.201 改用 macOS 系统 .help() · NSWindow 级显示 · 永远在正确层级
//   代价：~1.5s 显示延迟（macOS 系统默认） · 但保证可见
//
// 用法：.tooltip("xxx") 等价 .help("xxx")

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

extension View {
    /// macOS 系统 tooltip（NSWindow 级 · 不被 Shell 任何子视图遮挡）
    /// v17.201 · 从自定 SwiftUI overlay 改回系统 .help()
    func tooltip(_ text: String) -> some View {
        self.help(text)
    }
}

#endif
