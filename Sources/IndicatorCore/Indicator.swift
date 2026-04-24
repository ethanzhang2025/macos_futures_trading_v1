// WP-41 · 原生 Swift 指标 API 层
// 算法与 Legacy FormulaEngine/BuiltinFunctions/*.swift 等价，但提供独立 Swift API 供 ChartCore / AlertCore / JournalCore 直接调用
// 未来优化：时机合适时可 refactor Legacy 抽共用 kernel；现阶段按 WP-41 禁做的"不重复实现"做妥协（算法等价由测试保障）

import Foundation
import Shared

/// 指标分类（承自 D2 §2 MVP 56 指标 + 产品设计书 §3.1 模块②）
public enum IndicatorCategory: String, Sendable, CaseIterable {
    case trend          // 趋势（10）
    case oscillator     // 震荡（12）
    case volume         // 量价（8）
    case volatility     // 波动率 / 通道（8）
    case structure      // 支撑阻力 / 结构（6）
    case futures        // 期货特有（12）
}

/// 指标参数定义
public struct IndicatorParameter: Sendable, Equatable {
    public let name: String
    public let defaultValue: Decimal
    public let minValue: Decimal
    public let maxValue: Decimal

    public init(name: String, defaultValue: Decimal, minValue: Decimal, maxValue: Decimal) {
        self.name = name
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
    }
}

/// 指标计算错误
public enum IndicatorError: Error, CustomStringConvertible, Equatable {
    case invalidParameter(String)
    case insufficientData(needed: Int, actual: Int)

    public var description: String {
        switch self {
        case .invalidParameter(let msg): return "参数错误: \(msg)"
        case .insufficientData(let n, let a): return "数据不足: 需要 \(n) 根 K 线，实际 \(a) 根"
        }
    }
}

/// 指标协议
///
/// 示例：
/// ```swift
/// let kline = KLineSeries(...)
/// let ma20 = try MA.calculate(kline: kline, params: [20])
/// ```
public protocol Indicator: Sendable {
    /// 指标标识（MA / MACD / RSI / OBV 等）
    static var identifier: String { get }

    /// 指标分类
    static var category: IndicatorCategory { get }

    /// 参数定义（如 MA 只需 period，一参；MACD 需要 fast/slow/signal，三参）
    static var parameters: [IndicatorParameter] { get }

    /// 计算指标
    /// - Returns: 一条或多条时间序列，长度与 kline 对齐（未计算点为 nil）
    static func calculate(kline: KLineSeries, params: [Decimal]) throws -> [IndicatorSeries]
}

// MARK: - 参数转换共用 helper（避免各指标重复写 Int(truncating: params[i] as NSDecimalNumber)）

/// Decimal → Int（向零截断，与 NSDecimalNumber.intValue 一致）
@inline(__always)
func intValue(_ d: Decimal) -> Int {
    Int(truncating: d as NSDecimalNumber)
}
