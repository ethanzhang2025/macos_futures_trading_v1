// MainApp · 统一 NSAlert toast helper + PNGRenderer 渲染工具 + Pasteboard 复制工具
//
// 设计取舍：
// - Toast：@MainActor enum · 静态方法 · 替代各处重复 NSAlert 模板 · 视觉一致
// - PNGRenderer：抽 ImageRenderer + tiff/bitmap/png 4 行套路 · 截图导出 3 个 callsite 共用
// - Pasteboard：抽 NSPasteboard.general + clearContents + setString/writeObjects 套路
//   v15.20 simplify v2 · 6 处字符串 + 1 处图片 callsite 共用（AlertWindow / ChartScene）

#if canImport(SwiftUI) && os(macOS)

import AppKit
import SwiftUI

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

/// 系统剪贴板复制工具（IM/邮件分享 · 价位 / 测距详情 / 预警名 / 历史详情 / 截图 共用）
/// v15.20 simplify v2 · 抽 `NSPasteboard.general + clearContents + setString/writeObjects` 三行套路
@MainActor
enum Pasteboard {
    /// 复制文本到系统剪贴板（覆盖既有内容）
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// 复制图片到系统剪贴板（覆盖既有内容 · 走 writeObjects 而非 setData）
    static func copy(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}

/// SwiftUI 视图 → PNG Data 渲染工具（ChartScene 截图 / ReviewWindow chartCard 单图 / 全部图导出共用）
@MainActor
enum PNGRenderer {
    /// - Parameters:
    ///   - view: 待渲染 SwiftUI View
    ///   - width / height: 输出尺寸 pt
    ///   - scale: Retina 倍率（默认 2 · trader 高清需求）
    /// - Returns: PNG Data · ImageRenderer 失败任一步骤返回 nil
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = scale
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}

#endif
