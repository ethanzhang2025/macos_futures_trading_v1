// ContractStore + ProductSpecLoader 真数据 demo（第 16 个真数据 demo）
//
// 用途：
// - 验证合约元数据加载完整链路：JSON → ProductSpec → Contract → ContractStore 查询
// - 演示 5 大交易所典型品种（SHFE / CFFEX / CZCE）的 instrumentID 生成规则差异
// - 跨 Core 一致性：合约 volumeMultiple 与 PositionMatcher / IF 300 倍乘数实战对齐
// - DataCore demo 矩阵补全（之前的 demo 都用硬编码 multipliers · 这次完整加载链路）
//
// 拓扑（5 段）：
//   段 1 · 嵌入 5 品种 JSON（RB/IF/AU/CU/MA · 覆盖 SHFE+CFFEX+CZCE 三大所）
//   段 2 · ProductSpecLoader.load → [ProductSpec]
//   段 3 · generateContracts(months: [10, 11, 12]) → [Contract]（验证郑商所/其他所代码差异）
//   段 4 · ContractStore 查询全套（get / byProduct / byExchange / search / mainContract）
//   段 5 · 跨 Core 乘数校验（IF=300 / RB=10 / AU=1000 与 PositionMatcher 实战一致）
//
// 运行：swift run ContractStoreDemo
// 注意：纯本地内存计算，不依赖 Sina 网络

import Foundation
import Shared
import DataCore

@main
struct ContractStoreDemo {

    static func main() async throws {
        printSection("ContractStore + ProductSpecLoader 真数据 demo（第 16 个真数据 demo）")

        // 段 1：嵌入 5 品种 JSON
        printSection("段 1 · 5 品种 JSON 样本（覆盖 SHFE + CFFEX + CZCE 三大所）")
        // 项目惯例 productID 用大写（与 ProductSpecLoaderTests sampleJSON / ContractStore 内部 uppercase 索引一致）
        let specsJSON = """
        [
          {"exchange":"SHFE","productID":"RB","name":"螺纹钢","pinyin":"LWG","multiple":10,"priceTick":"1","marginRatio":"0.10","unit":"吨","nightSession":"23:00"},
          {"exchange":"CFFEX","productID":"IF","name":"沪深300","pinyin":"HS300","multiple":300,"priceTick":"0.2","marginRatio":"0.12","unit":"点","nightSession":"none"},
          {"exchange":"SHFE","productID":"AU","name":"黄金","pinyin":"HJ","multiple":1000,"priceTick":"0.02","marginRatio":"0.08","unit":"克","nightSession":"02:30"},
          {"exchange":"SHFE","productID":"CU","name":"铜","pinyin":"T","multiple":5,"priceTick":"10","marginRatio":"0.10","unit":"吨","nightSession":"01:00"},
          {"exchange":"CZCE","productID":"MA","name":"甲醇","pinyin":"JC","multiple":10,"priceTick":"1","marginRatio":"0.07","unit":"吨","nightSession":"23:00"}
        ]
        """
        print("  📄 JSON 输入：5 品种 · 3 大交易所")

        // 段 2：load
        printSection("段 2 · ProductSpecLoader.load(from: jsonString) → [ProductSpec]")
        let specs = try ProductSpecLoader.load(from: specsJSON)
        print("  ✅ 解析得 \(specs.count) 个品种规格")
        print("    交易所  代码     名称     乘数   最小变动  保证金   夜盘")
        for spec in specs {
            let multiple = String(spec.multiple).padded(4)
            print("    \(spec.exchange.padded(6))  \(spec.productID.padded(6))  \(spec.name.padded(8))  ×\(multiple)  \(spec.priceTick.padded(8))  \(spec.marginRatio.padded(7))  \(spec.nightSession)")
        }

        // 段 3：generateContracts
        printSection("段 3 · generateContracts(months: [1, 5, 10]) → 15 合约（主力月份）")
        let contracts = ProductSpecLoader.generateContracts(specs: specs, months: [1, 5, 10])
        print("  ✅ 生成 \(contracts.count) 合约（5 品种 × 3 月份）")
        print("\n  [合约代码格式差异]（API 当前实现：硬编码年首位 \"2\"）")
        print("    - SHFE/CFFEX：品种小写 + \"2\" + 2 位月（rb201 / if205 / au210 等）")
        print("    - CZCE：品种保持大写 + 2 位月（MA01 / MA05 / MA10）")
        print("\n  [部分合约抽样]")
        for c in contracts.prefix(6) {
            print("    \(c.instrumentID.padded(8))  \(c.instrumentName.padded(12))  \(c.exchange.rawValue)  ×\(c.volumeMultiple)  tick=\(c.priceTick)")
        }

        // 段 4：ContractStore 查询全套
        printSection("段 4 · ContractStore 查询全套（5 种查询模式）")
        let store = ContractStore()
        store.load(contracts)
        var allCount = 0
        for productID in ["RB", "IF", "AU", "CU", "MA"] {
            allCount += store.byProduct(productID).count
        }
        print("  ✅ 装载 \(contracts.count) 合约 · 5 品种合计 \(allCount)")

        // 4.1 get(_:)（取首个生成的 rb 合约）
        let firstRBID = contracts.first(where: { $0.productID == "RB" })?.instrumentID ?? ""
        let rbMain = store.get(firstRBID)
        print("\n  [1] get(\"\(firstRBID)\") → \(rbMain?.instrumentName ?? "nil") · 乘数 \(rbMain?.volumeMultiple ?? 0)")

        // 4.2 byProduct(_:)
        let rbContracts = store.byProduct("RB")
        let rbList = rbContracts.map(\.instrumentID).joined(separator: " / ")
        print("  [2] byProduct(\"RB\") → \(rbContracts.count) 合约：\(rbList)")

        // 4.3 byExchange(_:)
        let shfeContracts = store.byExchange(.SHFE)
        let cffexContracts = store.byExchange(.CFFEX)
        let czceContracts = store.byExchange(.CZCE)
        print("  [3] byExchange:")
        print("      · SHFE  → \(shfeContracts.count) 合约（rb + au + cu × 3 月 = 9）")
        print("      · CFFEX → \(cffexContracts.count) 合约（IF × 3 月）")
        print("      · CZCE  → \(czceContracts.count) 合约（MA × 3 月）")

        // 4.4 search(_:)
        let searchAu = store.search("黄金")
        let searchPinyin = store.search("HS")  // pinyin: HS300
        print("  [4] search:")
        print("      · search(\"黄金\")  → \(searchAu.count) 合约（按 productName 匹配）")
        print("      · search(\"HS\")   → \(searchPinyin.count) 合约（按 pinyinInitials 匹配 IF=HS300）")

        // 4.5 mainContract（按持仓量选主力 · 用模拟数据）
        // 用动态生成的合约 ID 构造 openInterests，避免硬编码与 API 真实输出不一致
        let rbIDs = rbContracts.map(\.instrumentID)
        let openInterests: [String: Decimal] = Dictionary(
            uniqueKeysWithValues: zip(rbIDs, [Decimal(50000), Decimal(120000), Decimal(80000)])
        )
        let mainRB = store.mainContract(productID: "RB", openInterests: openInterests)
        let oiSummary = openInterests.map { "\($0.key):\($0.value)" }.joined(separator: " · ")
        print("  [5] mainContract(\"RB\", openInterests=[\(oiSummary)])")
        print("      → \(mainRB?.instrumentID ?? "nil")（持仓量最高的合约 · 期望第 2 个，120k）")

        // 段 5：跨 Core 乘数校验
        printSection("段 5 · 跨 Core 乘数校验（与 WenhuaCSVImportDemo / PositionMatcher 实战一致）")
        let multiplierChecks: [(productID: String, expected: Int, scenario: String)] = [
            ("RB", 10,   "螺纹钢 · 1 手 10 吨"),
            ("IF", 300,  "沪深300 · 1 点 300 元（IF 上涨 1 点 = 300 元）"),
            ("AU", 1000, "黄金 · 1 手 1000 克"),
            ("CU", 5,    "铜 · 1 手 5 吨"),
            ("MA", 10,   "甲醇 · 1 手 10 吨")
        ]
        var allMatch = true
        for check in multiplierChecks {
            let contract = store.byProduct(check.productID).first
            let actual = contract?.volumeMultiple ?? -1
            let pass = actual == check.expected
            allMatch = allMatch && pass
            print("    \(pass ? "✅" : "❌") \(check.productID.padded(3)) ×\(check.expected) · \(check.scenario)")
        }

        // 总结
        let allOK = specs.count == 5 &&
                     contracts.count == 15 &&
                     shfeContracts.count == 9 &&
                     cffexContracts.count == 3 &&
                     czceContracts.count == 3 &&
                     allMatch
        printSection(allOK
            ? "🎉 第 16 个真数据 demo 通过（合约元数据完整加载链路 + 跨 Core 一致性）"
            : "⚠️  数据流验收未达标（详见上方）")
    }

    // MARK: - 通用 helpers

    static func printSection(_ title: String) {
        print("─────────────────────────────────────────────")
        print(title)
        print("─────────────────────────────────────────────")
    }
}

private extension String {
    func padded(_ length: Int) -> String {
        padding(toLength: length, withPad: " ", startingAt: 0)
    }
}
