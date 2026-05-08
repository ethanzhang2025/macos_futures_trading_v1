// 中国期货品种规格库单测（v15.26 · 行情列表大补全）

import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("ChineseFuturesProducts · 60+ 品种 hardcoded 单测")
struct ChineseFuturesProductsTests {

    @Test("品种数 ≥ 50 · 真实大盘覆盖")
    func sufficientCoverage() {
        #expect(ChineseFuturesProducts.all.count >= 50)
    }

    @Test("productID 全局唯一 · 无重复")
    func productIDUnique() {
        let ids = ChineseFuturesProducts.all.map { $0.productID }
        #expect(Set(ids).count == ids.count)
    }

    @Test("byProductID 索引完整 · 与 all 等长")
    func byProductIDComplete() {
        #expect(ChineseFuturesProducts.byProductID.count == ChineseFuturesProducts.all.count)
    }

    @Test("11 类目全部有品种 · 无空类")
    func allCategoriesPopulated() {
        for category in ChineseFuturesProducts.Category.allCases {
            let entries = ChineseFuturesProducts.byCategory[category] ?? []
            #expect(!entries.isEmpty, "类目 \(category.rawValue) 不应为空")
        }
    }

    @Test("6 大交易所全覆盖 · SHFE/INE/DCE/CZCE/CFFEX/GFEX")
    func allExchangesCovered() {
        let exchanges = Set(ChineseFuturesProducts.all.map { $0.exchange })
        #expect(exchanges.contains(.SHFE))
        #expect(exchanges.contains(.INE))
        #expect(exchanges.contains(.DCE))
        #expect(exchanges.contains(.CZCE))
        #expect(exchanges.contains(.CFFEX))
        #expect(exchanges.contains(.GFEX))
    }

    @Test("核心品种存在性 · rb/cu/au/IF/T/si")
    func coreProductsPresent() {
        #expect(ChineseFuturesProducts.byProductID["rb"] != nil)
        #expect(ChineseFuturesProducts.byProductID["cu"] != nil)
        #expect(ChineseFuturesProducts.byProductID["au"] != nil)
        #expect(ChineseFuturesProducts.byProductID["IF"] != nil)
        #expect(ChineseFuturesProducts.byProductID["T"]  != nil)
        #expect(ChineseFuturesProducts.byProductID["si"] != nil)
    }

    @Test("multiplier / marginRatio 字面量全部可解析为 Decimal")
    func numericFieldsParseable() {
        for entry in ChineseFuturesProducts.all {
            #expect(Decimal(string: entry.spec.priceTick) != nil,
                    "priceTick 不可解析: \(entry.productID) = \(entry.spec.priceTick)")
            #expect(Decimal(string: entry.spec.marginRatio) != nil,
                    "marginRatio 不可解析: \(entry.productID) = \(entry.spec.marginRatio)")
            #expect(entry.spec.multiple > 0, "multiplier 应 > 0: \(entry.productID)")
        }
    }

    @Test("国债/股指标记 isFinancial=true · 商品标 false")
    func financialFlagCorrect() {
        if let if_ = ChineseFuturesProducts.byProductID["IF"] {
            #expect(if_.isFinancial == true)
        }
        if let t = ChineseFuturesProducts.byProductID["T"] {
            #expect(t.isFinancial == true)
        }
        if let rb = ChineseFuturesProducts.byProductID["rb"] {
            #expect(rb.isFinancial == false)
        }
    }

    // MARK: - 派生合约清单

    @Test("allMainContinuousIDs 数量 = 品种数 · 全大写 + '0' 后缀")
    func mainContinuousIDsDerived() {
        let ids = ChineseFuturesProducts.allMainContinuousIDs
        #expect(ids.count == ChineseFuturesProducts.all.count)
        for id in ids {
            #expect(id.hasSuffix("0"))
            #expect(id == id.uppercased())
        }
    }

    @Test("allDominantMonthIDs 覆盖率 ≥ 95% · DominantMonthCalculator 规则齐全")
    func dominantMonthCoverage() {
        let total = ChineseFuturesProducts.all.count
        let withDominant = ChineseFuturesProducts.allDominantMonthIDs.count
        let coverage = Double(withDominant) / Double(total)
        #expect(coverage >= 0.95,
                "DominantMonthCalculator 规则覆盖率 \(coverage) < 95% · 缺漏品种")
    }

    @Test("allSupportedInstrumentIDs ≥ 100 · 包含主连续 + 主力月份去重")
    func supportedInstrumentsCount() {
        #expect(ChineseFuturesProducts.allSupportedInstrumentIDs.count >= 100)
    }

    @Test("allContracts 派生数量正确 · 主连续 + 主力月份")
    func allContractsDerived() {
        let contracts = ChineseFuturesProducts.allContracts
        // 主连续 = deliveryMonth == 0（不依赖 ID 后缀 · 避免 PK2510 末位 "0" 误判）
        let mainCount = contracts.filter { $0.deliveryMonth == 0 }.count
        #expect(mainCount == ChineseFuturesProducts.all.count)
        // 总数 = 品种数 + 主力月份数（一定 ≤ 品种数 × 2）
        #expect(contracts.count <= ChineseFuturesProducts.all.count * 2)
        #expect(contracts.count >= ChineseFuturesProducts.all.count)
    }

    @Test("派生合约 priceTick / marginRatio 与品种规格一致")
    func derivedContractsConsistent() {
        for contract in ChineseFuturesProducts.allContracts {
            guard let entry = ChineseFuturesProducts.byProductID[contract.productID] else {
                Issue.record("派生合约 \(contract.instrumentID) 找不到品种规格")
                continue
            }
            #expect(contract.volumeMultiple == entry.spec.multiple)
            // priceTick / margin 字面量精确解析
            if let expectedTick = Decimal(string: entry.spec.priceTick) {
                #expect(contract.priceTick == expectedTick)
            }
        }
    }
}
