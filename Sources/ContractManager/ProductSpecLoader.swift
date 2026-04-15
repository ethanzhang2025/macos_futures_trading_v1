import Foundation
import Shared

/// 品种规格（从JSON加载）
public struct ProductSpec: Codable, Sendable {
    public let exchange: String
    public let productID: String
    public let name: String
    public let pinyin: String
    public let multiple: Int
    public let priceTick: String
    public let marginRatio: String
    public let unit: String
    public let nightSession: String
}

/// 品种规格加载器
public enum ProductSpecLoader {
    /// 从JSON数据加载品种规格
    public static func load(from jsonData: Data) throws -> [ProductSpec] {
        let decoder = JSONDecoder()
        return try decoder.decode([ProductSpec].self, from: jsonData)
    }

    /// 从JSON字符串加载
    public static func load(from jsonString: String) throws -> [ProductSpec] {
        guard let data = jsonString.data(using: .utf8) else {
            throw ProductSpecError.invalidEncoding
        }
        return try load(from: data)
    }

    /// 将品种规格转为Contract对象（生成指定月份的合约）
    public static func generateContracts(specs: [ProductSpec], months: [Int]) -> [Contract] {
        var contracts: [Contract] = []
        for spec in specs {
            guard let exchange = Exchange(rawValue: spec.exchange),
                  let priceTick = Decimal(string: spec.priceTick),
                  let marginRatio = Decimal(string: spec.marginRatio) else { continue }

            for month in months {
                let monthStr = String(format: "%02d", month)
                let instrumentID: String
                if exchange == .CZCE {
                    // 郑商所合约代码格式：品种+1位年+2位月（如SR501）
                    instrumentID = "\(spec.productID)\(monthStr)"
                } else {
                    // 其他交易所：品种+4位年月（如rb2501）
                    instrumentID = "\(spec.productID.lowercased())2\(monthStr)"
                }

                let contract = Contract(
                    instrumentID: instrumentID,
                    instrumentName: "\(spec.name)2\(monthStr)",
                    exchange: exchange,
                    productID: spec.productID,
                    volumeMultiple: spec.multiple,
                    priceTick: priceTick,
                    deliveryMonth: month,
                    expireDate: "202\(monthStr)15",
                    longMarginRatio: marginRatio,
                    shortMarginRatio: marginRatio,
                    isTrading: true,
                    productName: spec.name,
                    pinyinInitials: spec.pinyin
                )
                contracts.append(contract)
            }
        }
        return contracts
    }
}

public enum ProductSpecError: Error {
    case invalidEncoding
    case fileNotFound
}
