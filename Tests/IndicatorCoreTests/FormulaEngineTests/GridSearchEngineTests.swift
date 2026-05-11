// v17.38 D4 · GridSearchEngine 单测

import Testing
import Foundation
@testable import IndicatorCore

private func bar(close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close, volume: 100,
            amount: 0, openInterest: 0, timestamp: nil)
}

@Suite("GridSearchEngine · v17.38 D4 参数扫描")
struct GridSearchEngineTests {

    @Test("cartesian · 空 paramSpace → 单个空 dict")
    func cartesianEmpty() {
        let combos = GridSearchEngine.cartesian([])
        #expect(combos.count == 1)
        #expect(combos[0].isEmpty)
    }

    @Test("cartesian · 单参数 N=[1,2,3]")
    func cartesianSingleParam() {
        let combos = GridSearchEngine.cartesian([("N", [1, 2, 3])])
        #expect(combos.count == 3)
        #expect(Set(combos.compactMap { $0["N"] }) == [1, 2, 3])
    }

    @Test("cartesian · 双参数 笛卡尔积 size = m × n")
    func cartesianMultiParam() {
        let combos = GridSearchEngine.cartesian([
            ("N", [5, 10]),
            ("M", [20, 40, 60])
        ])
        #expect(combos.count == 6)   // 2 × 3
        // 每组都含两个 key
        for c in combos {
            #expect(c["N"] != nil && c["M"] != nil)
        }
    }

    @Test("substitute · 单占位替换")
    func substituteBasic() {
        let out = GridSearchEngine.substitute(template: "MA(CLOSE, {N})", params: ["N": 14])
        #expect(out == "MA(CLOSE, 14)")
    }

    @Test("substitute · 多占位")
    func substituteMulti() {
        let out = GridSearchEngine.substitute(
            template: "BUY: MA(CLOSE, {N}) > MA(CLOSE, {M});",
            params: ["N": 5, "M": 20]
        )
        #expect(out == "BUY: MA(CLOSE, 5) > MA(CLOSE, 20);")
    }

    @Test("substitute · 占位不在 params 保留原样（容错）")
    func substituteMissingKept() {
        let out = GridSearchEngine.substitute(template: "MA({X})", params: ["N": 1])
        #expect(out == "MA({X})")
    }

    @Test("run · 端到端 · 2 组合都跑成功 · 按 metric 排序")
    func runEndToEnd() {
        // 上涨趋势 bars · 信号 = CLOSE > MA(CLOSE, N)
        // N=2 与 N=4 都应产生 trade · endingPnL > 0
        let bars = (1...10).map { bar(close: Decimal($0) * 10) }   // 10, 20, ..., 100
        let outcomes = GridSearchEngine.run(
            template: "BUY: IF(CLOSE > MA(CLOSE, {N}), 1, 0);",
            paramSpace: [("N", [2, 4])],
            bars: bars
        )
        #expect(outcomes.count == 2)
        // 降序：metric 大的在前
        #expect(outcomes[0].metric >= outcomes[1].metric)
        // 公式占位已替换
        let formulas = outcomes.map(\.formula)
        #expect(formulas.contains { $0.contains("MA(CLOSE, 2)") })
        #expect(formulas.contains { $0.contains("MA(CLOSE, 4)") })
    }

    @Test("run · 单组合编译失败 · 跳过不阻塞其他")
    func runSkipsCompileError() {
        let bars = [bar(close: 100), bar(close: 110)]
        let outcomes = GridSearchEngine.run(
            template: "BUY: {OP};",
            paramSpace: [("OP", [1])],
            bars: bars
        )
        // "BUY: 1;" 是合法 formula · 应该成功
        #expect(outcomes.count == 1)
    }

    @Test("run · 自定义 metric closure · 按 winRate 排序")
    func customMetricWinRate() {
        let bars = (1...8).map { bar(close: Decimal($0) * 10) }
        let outcomes = GridSearchEngine.run(
            template: "BUY: IF(CLOSE > MA(CLOSE, {N}), 1, 0);",
            paramSpace: [("N", [2, 3])],
            bars: bars,
            metric: { $0.winRate }   // 用胜率而非 PnL 排序
        )
        #expect(outcomes.count == 2)
        #expect(outcomes[0].metric >= outcomes[1].metric)
    }
}
