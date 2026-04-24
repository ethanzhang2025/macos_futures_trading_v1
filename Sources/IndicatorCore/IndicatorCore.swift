// IndicatorCore · 56 指标 + 麦语言底层函数
// WP-24 占位骨架 · 后续 WP-30 归入 Legacy Sources/FormulaEngine/*，WP-41 填充 56 指标
// 职责：指标计算引擎（原生 Swift 实现）+ 麦语言 Lexer/Parser/Interpreter 同源底层函数
// 禁做：不把指标计算绑进渲染线程；不重复实现 Legacy FormulaEngine 已有函数

import Foundation
import Shared
import DataCore

public enum IndicatorCoreModule {
    public static let version = "0.1.0-skeleton"
}
