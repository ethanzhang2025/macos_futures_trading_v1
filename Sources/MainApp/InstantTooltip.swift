// v15.85 原版自定 SwiftUI overlay tooltip · 在普通 chart window 工作正常
// v17.200 反弹：Shell 嵌入模式（v17.6+）顶部加了 PrimaryTabBar · tooltip 显示在 toolbar 上方 32px
//   恰被 PrimaryTabBar 半透明覆盖 · 用户看到「模糊白字」
// v17.201 改用 macOS 系统 .help() · NSWindow 级显示 · 永远在正确层级
//   代价：~1.5s 显示延迟（macOS 系统默认）
// v17.226 · 改走 NSPopover HoverPopoverService（0 延迟 + 自定义视觉）
// v17.233 · 紧急回退 v17.226 · 全 app 322 处 .tooltip 全替换 HoverPopoverModifier 导致主线程被大量
//   NSViewRepresentable + onHover 监听淹没 · 旧版 / V1 主窗一起卡死（按 ⌘K 弹命令面板都几秒不响应）
//   HoverPopoverService.swift 保留 · 未来仅在 V1 个别按钮选择性应用 · 不再全局替换
//
// 用法：.tooltip("xxx") · 全 app 调用点零修改

#if canImport(SwiftUI) && os(macOS)

import SwiftUI

extension View {
    /// macOS 系统 tooltip · NSWindow 级显示 · 永远在正确层级
    /// v17.233 · 回退 v17.226 · 用系统 .help() 而非 NSPopover（全局替换性能崩盘）
    func tooltip(_ text: String) -> some View {
        self.help(text)
    }
}

#endif
