// WP-31a · Sina 报价拉取协议
// 设计目的：
// - 让 SinaMarketDataProvider 不依赖具体的 SinaMarketData 类，而是依赖协议
// - 测试时注入 stub，无需打真网络
// - SinaMarketData 自动符合（已实现 fetchQuotes 同名方法）

import Foundation

/// 新浪报价拉取能力（实时报价批量获取）
public protocol SinaQuoteFetching: Sendable {
    /// 批量拉取多合约实时报价
    /// - Parameter symbols: 合约代码（如 "RB0", "IF0"）
    /// - Returns: 报价数组（顺序与 symbols 对齐；解析失败的合约会被跳过）
    /// - Throws: 网络错误 / 解析错误
    func fetchQuotes(symbols: [String]) async throws -> [SinaQuote]
}

extension SinaMarketData: SinaQuoteFetching {}
