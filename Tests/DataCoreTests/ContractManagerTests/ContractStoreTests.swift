import Foundation
import Testing
@testable import DataCore
import Shared

@Suite("合约存储测试")
struct ContractStoreTests {
    private func makeContract(id: String, product: String, exchange: Exchange, name: String, pinyin: String) -> Contract {
        Contract(
            instrumentID: id, instrumentName: name, exchange: exchange,
            productID: product, volumeMultiple: 10, priceTick: 1,
            deliveryMonth: 1, expireDate: "20250115",
            longMarginRatio: Decimal(string: "0.1")!, shortMarginRatio: Decimal(string: "0.1")!,
            isTrading: true, productName: name, pinyinInitials: pinyin
        )
    }

    @Test("基本增删查")
    func testBasicCRUD() {
        let store = ContractStore()
        let rb = makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501", pinyin: "LWG")
        store.upsert(rb)
        #expect(store.count == 1)
        #expect(store.get("rb2501")?.instrumentID == "rb2501")
    }

    @Test("按品种查询")
    func testByProduct() {
        let store = ContractStore()
        store.upsert(makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501", pinyin: "LWG"))
        store.upsert(makeContract(id: "rb2505", product: "RB", exchange: .SHFE, name: "螺纹钢2505", pinyin: "LWG"))
        store.upsert(makeContract(id: "au2506", product: "AU", exchange: .SHFE, name: "黄金2506", pinyin: "HJ"))
        let rbContracts = store.byProduct("RB")
        #expect(rbContracts.count == 2)
    }

    @Test("拼音搜索")
    func testPinyinSearch() {
        let store = ContractStore()
        store.upsert(makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501", pinyin: "LWG"))
        store.upsert(makeContract(id: "au2506", product: "AU", exchange: .SHFE, name: "黄金2506", pinyin: "HJ"))
        let results = store.search("LWG")
        #expect(results.count == 1)
        #expect(results[0].instrumentID == "rb2501")
    }

    @Test("按交易所查询")
    func testByExchange() {
        let store = ContractStore()
        store.upsert(makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢", pinyin: "LWG"))
        store.upsert(makeContract(id: "m2505", product: "M", exchange: .DCE, name: "豆粕", pinyin: "DP"))
        let shfe = store.byExchange(.SHFE)
        #expect(shfe.count == 1)
    }
}
