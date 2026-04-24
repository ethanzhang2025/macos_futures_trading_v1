import Foundation
import MarketData

/// 自选合约：包裹 SinaFuturesSymbol 的 tuple 以获得 Codable/Identifiable 能力，支持 UserDefaults 持久化
struct WatchItem: Codable, Identifiable, Hashable {
    let symbol: String
    let name: String
    let pinyin: String
    var id: String { symbol }

    /// 全部合约池（从 SinaFuturesSymbol.all 映射，默认即为新用户的自选列表）
    static let allContracts: [WatchItem] = SinaFuturesSymbol.all.map {
        WatchItem(symbol: $0.symbol, name: $0.name, pinyin: $0.pinyin)
    }
}
