// MainApp · 国际化 helper（v15.25 WP-i18n P4）
//
// 用途：String 类型 API 调用点（NSAlert/NSSavePanel/NSWindow 的 messageText/title/
//      addButton(withTitle:) 等）用 L("xxx") 包裹 · 自动从 SPM Bundle.module 的
//      Localizable.strings 查翻译。
//
// 工作机制：
// - SwiftUI Text/Button 等第一参数是 LocalizedStringKey 自动 i18n（无需此 helper）
// - 但 NSAlert.messageText = "x" 是 String 类型 setter · 不会自动 localize
// - 此 helper 等价 NSLocalizedString(key, bundle: .module, comment: "")
//
// SwiftUI 自动 i18n 已覆盖：Text/Button/Label/Toggle/Picker/Section/Menu/.help/.alert
// 此 helper 只用于剩余 String 类型 API 调用点

#if canImport(Foundation)
import Foundation

public func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
#endif
