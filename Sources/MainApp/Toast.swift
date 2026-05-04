// MainApp · 统一 NSAlert toast helper（导出 / 导入 / 操作反馈通用）
//
// 设计取舍：
// - @MainActor enum · 静态方法 · 调用方一行 · 替代各处重复的 4-5 行 NSAlert 套路
// - 视觉一致：所有信息提示统一"好"按钮 · 错误统一 .warning style + localizedDescription

#if canImport(SwiftUI) && os(macOS)

import AppKit

@MainActor
enum Toast {
    /// 信息提示（成功 · 通知 · 完成）· 不阻断后续流程语义上但 runModal 仍阻塞
    static func info(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "好")
        a.runModal()
    }

    /// 错误提示（导出失败 / 解析失败等）· 自动展开 localizedDescription
    static func error(_ title: String, _ err: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = err.localizedDescription
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        a.runModal()
    }

    /// 错误提示（自定义 body · 不来自 Error）
    static func errorBody(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.alertStyle = .warning
        a.addButton(withTitle: "好")
        a.runModal()
    }
}

#endif
