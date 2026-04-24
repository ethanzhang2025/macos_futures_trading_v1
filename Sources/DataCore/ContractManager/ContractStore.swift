import Foundation
import Shared

/// 合约存储与查询
public final class ContractStore: @unchecked Sendable {
    private var contracts: [String: Contract] = [:]
    private var productIndex: [String: [String]] = [:]  // productID -> [instrumentID]
    private var exchangeIndex: [Exchange: [String]] = [:]

    public init() {}

    /// 添加/更新合约
    public func upsert(_ contract: Contract) {
        contracts[contract.instrumentID] = contract
        productIndex[contract.productID, default: []].append(contract.instrumentID)
        exchangeIndex[contract.exchange, default: []].append(contract.instrumentID)
    }

    /// 批量加载
    public func load(_ list: [Contract]) {
        for c in list { upsert(c) }
    }

    /// 按合约代码查询
    public func get(_ instrumentID: String) -> Contract? {
        contracts[instrumentID]
    }

    /// 按品种查询所有合约
    public func byProduct(_ productID: String) -> [Contract] {
        let ids = productIndex[productID.uppercased()] ?? []
        return ids.compactMap { contracts[$0] }
    }

    /// 按交易所查询所有合约
    public func byExchange(_ exchange: Exchange) -> [Contract] {
        let ids = exchangeIndex[exchange] ?? []
        return ids.compactMap { contracts[$0] }
    }

    /// 搜索合约（代码或拼音首字母匹配）
    public func search(_ keyword: String) -> [Contract] {
        let upper = keyword.uppercased()
        return contracts.values.filter { c in
            c.instrumentID.uppercased().contains(upper) ||
            c.productID.uppercased().contains(upper) ||
            c.pinyinInitials.contains(upper) ||
            c.productName.contains(keyword)
        }
    }

    /// 获取品种的主力合约（持仓量最大的）
    /// 需要外部传入持仓量数据
    public func mainContract(productID: String, openInterests: [String: Decimal]) -> Contract? {
        byProduct(productID)
            .filter { $0.isTrading }
            .max { (openInterests[$0.instrumentID] ?? 0) < (openInterests[$1.instrumentID] ?? 0) }
    }

    /// 所有合约数量
    public var count: Int { contracts.count }

    /// 所有品种ID
    public var allProductIDs: [String] {
        Array(productIndex.keys).sorted()
    }
}
