import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("品种规格加载器测试")
struct ProductSpecLoaderTests {
    private let sampleJSON = """
    [
      {"exchange":"SHFE","productID":"RB","name":"螺纹钢","pinyin":"LWG","multiple":10,"priceTick":"1","marginRatio":"0.10","unit":"吨","nightSession":"until2330"},
      {"exchange":"SHFE","productID":"AU","name":"黄金","pinyin":"HJ","multiple":1000,"priceTick":"0.02","marginRatio":"0.08","unit":"克","nightSession":"until0230"},
      {"exchange":"CFFEX","productID":"IF","name":"沪深300","pinyin":"HS300","multiple":300,"priceTick":"0.2","marginRatio":"0.12","unit":"点","nightSession":"none"}
    ]
    """

    @Test("加载JSON")
    func testLoadJSON() throws {
        let specs = try ProductSpecLoader.load(from: sampleJSON)
        #expect(specs.count == 3)
        #expect(specs[0].productID == "RB")
        #expect(specs[0].name == "螺纹钢")
        #expect(specs[1].multiple == 1000)
    }

    @Test("生成合约")
    func testGenerateContracts() throws {
        let specs = try ProductSpecLoader.load(from: sampleJSON)
        let contracts = ProductSpecLoader.generateContracts(specs: specs, months: [1, 5, 10])
        // 3品种 × 3月份 = 9个合约
        #expect(contracts.count == 9)
    }

    @Test("合约信息正确")
    func testContractDetails() throws {
        let specs = try ProductSpecLoader.load(from: sampleJSON)
        let contracts = ProductSpecLoader.generateContracts(specs: specs, months: [1])
        let rb = contracts.first { $0.productID == "RB" }
        #expect(rb != nil)
        #expect(rb?.volumeMultiple == 10)
        #expect(rb?.priceTick == 1)
        #expect(rb?.exchange == .SHFE)
        #expect(rb?.pinyinInitials == "LWG")
    }

    @Test("导入到ContractStore")
    func testImportToStore() throws {
        let specs = try ProductSpecLoader.load(from: sampleJSON)
        let contracts = ProductSpecLoader.generateContracts(specs: specs, months: [1, 5])
        let store = ContractStore()
        store.load(contracts)
        #expect(store.count == 6)
        let rbContracts = store.byProduct("RB")
        #expect(rbContracts.count == 2)
    }

    @Test("搜索中文名")
    func testSearchChinese() throws {
        let specs = try ProductSpecLoader.load(from: sampleJSON)
        let contracts = ProductSpecLoader.generateContracts(specs: specs, months: [1])
        let store = ContractStore()
        store.load(contracts)
        let results = store.search("黄金")
        #expect(results.count == 1)
    }

    @Test("无效JSON报错")
    func testInvalidJSON() throws {
        #expect(throws: (any Error).self) {
            _ = try ProductSpecLoader.load(from: "not json")
        }
    }
}
