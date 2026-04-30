// MainApp · 模拟交易默认合约 hardcoded 数据（v15.4 · WP-54）
//
// v1 简化：4 主力 + 4 active 月份合约 hardcoded 参数（multiplier / margin ratio）· 用真实数据近似值
// v2 接入：真合约 metadata 服务 → ContractStore → SimulatedTradingEngine.registerContracts

import Foundation
import Shared

enum SimulatedContractDefaults {

    /// 4 主连续 + 4 主力月份 · 与 MarketDataPipeline.supportedContracts 对齐
    /// 参数（volumeMultiple / marginRatio）取自常用真实数据 · 近似值（用户切机后接真合约元数据替换）
    static let list: [Contract] = [
        // 螺纹钢 · SHFE · 10 吨/手 · 双边 10%
        contract("RB0", name: "螺纹连续", exchange: .SHFE, productID: "rb",
                 multiplier: 10, marginRatio: "0.10"),
        contract("rb2609", name: "螺纹2609", exchange: .SHFE, productID: "rb",
                 multiplier: 10, marginRatio: "0.10"),
        // 沪深300 股指 · CFFEX · 300 元/点 · 双边 12%
        contract("IF0", name: "沪深300连续", exchange: .CFFEX, productID: "IF",
                 multiplier: 300, marginRatio: "0.12"),
        contract("IF2605", name: "沪深300 2605", exchange: .CFFEX, productID: "IF",
                 multiplier: 300, marginRatio: "0.12"),
        // 黄金 · SHFE · 1000 克/手 · 双边 8%
        contract("AU0", name: "黄金连续", exchange: .SHFE, productID: "au",
                 multiplier: 1000, marginRatio: "0.08"),
        contract("au2606", name: "黄金2606", exchange: .SHFE, productID: "au",
                 multiplier: 1000, marginRatio: "0.08"),
        // 铜 · SHFE · 5 吨/手 · 双边 10%
        contract("CU0", name: "铜连续", exchange: .SHFE, productID: "cu",
                 multiplier: 5, marginRatio: "0.10"),
        // 铁矿石 · DCE · 100 吨/手 · 双边 10%
        contract("i2609", name: "铁矿石2609", exchange: .DCE, productID: "i",
                 multiplier: 100, marginRatio: "0.10")
    ]

    private static func contract(
        _ id: String,
        name: String,
        exchange: Exchange,
        productID: String,
        multiplier: Int,
        marginRatio rawRatio: String
    ) -> Contract {
        // rawRatio 全部由本文件硬编码字面量传入 · Decimal(string:) 必成功 · 失败=程序员错（fatal 即可）
        guard let ratio = Decimal(string: rawRatio) else {
            fatalError("SimulatedContractDefaults · 非法 marginRatio 字面量：\(rawRatio)")
        }
        return Contract(
            instrumentID: id,
            instrumentName: name,
            exchange: exchange,
            productID: productID,
            volumeMultiple: multiplier,
            priceTick: 1,
            deliveryMonth: 0,
            expireDate: "",
            longMarginRatio: ratio,
            shortMarginRatio: ratio,
            isTrading: true,
            productName: name,
            pinyinInitials: ""
        )
    }
}
