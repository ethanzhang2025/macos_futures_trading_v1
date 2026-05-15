// v15.85 原版自定 SwiftUI overlay tooltip · 在普通 chart window 工作正常
// v17.200 反弹：Shell 嵌入模式（v17.6+）顶部加了 PrimaryTabBar · tooltip 显示在 toolbar 上方 32px
//   恰被 PrimaryTabBar 半透明覆盖 · 用户看到「模糊白字」
// v17.201 改用 macOS 系统 .help() · NSWindow 级显示 · 永远在正确层级
//   代价：~1.5s 显示延迟（macOS 系统默认）
// v17.226 · Step 5 · 改走 NSPopover HoverPopoverService（0 延迟 + 自定义视觉）
//   V1 主窗 environment 注入 hoverPopoverService → 用 NSPopover · NSWindow 级显示无遮挡
//   旧 Shell / detached / 其他独立窗 environment 缺失 → 降级到系统 .help()（无 break）
//
// 用法：.tooltip("xxx") · 全 app 调用点零修改

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

extension View {
    /// hover tooltip · V1 主窗走 NSPopover 0 延迟 · 其他窗口降级 .help()
    func tooltip(_ text: String) -> some View {
        modifier(HoverPopoverModifier(text: text))
    }
}

#endif
