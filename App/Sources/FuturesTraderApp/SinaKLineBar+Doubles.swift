import Foundation
import MarketData

/// 渲染层频繁访问 Double，避免每次调用 `NSDecimalNumber(decimal:).doubleValue` 重复构造对象。
/// 精度需求仍走原始 `open/high/low/close`（Decimal）。
extension SinaKLineBar {
    var openD: Double { NSDecimalNumber(decimal: open).doubleValue }
    var highD: Double { NSDecimalNumber(decimal: high).doubleValue }
    var lowD: Double { NSDecimalNumber(decimal: low).doubleValue }
    var closeD: Double { NSDecimalNumber(decimal: close).doubleValue }
}
