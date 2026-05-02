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

    /// v15.16 hotfix #11 P1-1：upsert 同 instrumentID 多次时 productIndex/exchangeIndex 不应重复 append
    @Test("重复 upsert 同合约 · index 不重复（v15.16 hotfix P1-1 防回归）")
    func testUpsertIdempotent() {
        let store = ContractStore()
        let rb = makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501", pinyin: "LWG")
        // upsert 5 次同 instrumentID（模拟 hot reload / 配置同步重放）
        for _ in 0..<5 {
            store.upsert(rb)
        }
        // 修复前：byProduct 会返 5 个副本 / byExchange 同
        // 修复后：仅 1 个 · index 内仅记录 1 次
        #expect(store.count == 1)
        #expect(store.byProduct("RB").count == 1)
        #expect(store.byExchange(.SHFE).count == 1)
    }

    @Test("upsert 更新已有合约 · index 仍只 1 次")
    func testUpsertUpdate() {
        let store = ContractStore()
        let rb = makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501", pinyin: "LWG")
        let rbUpdated = makeContract(id: "rb2501", product: "RB", exchange: .SHFE, name: "螺纹钢2501更新", pinyin: "LWG")
        store.upsert(rb)
        store.upsert(rbUpdated)
        // count + index 数量都是 1 · 内容是更新后的
        #expect(store.count == 1)
        #expect(store.get("rb2501")?.instrumentName == "螺纹钢2501更新")
        #expect(store.byProduct("RB").count == 1)
    }
}
