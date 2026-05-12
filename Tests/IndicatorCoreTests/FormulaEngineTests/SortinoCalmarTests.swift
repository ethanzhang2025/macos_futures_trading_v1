// v17.45 D2 v2 · Sortino + Calmar 指标单测（独立 suite · 不污染 v1 测试）

import Testing
import Foundation
@testable import IndicatorCore

private func mkBar(_ close: Decimal) -> BarData {
    BarData(open: close, high: close, low: close, close: close,
            volume: 100, amount: 0, openInterest: 0, timestamp: nil)
}

@Suite("BacktestResult · Sortino + Calmar · v17.45 D2 v2")
struct SortinoCalmarTests {

    @Test("空 bars · sortino/calmar 都返 0")
    func empty() {
        let r = SimpleBacktestEngine.runWithSignal(signal: [], bars: [], initialEquity: 100_000)
        #expect(r.sortino == 0)
        #expect(r.calmar == 0)
    }

    @Test("无 trade · sortino/calmar 都返 0（没有 equity 变化）")
    func noTrade() {
        let bars = [mkBar(100), mkBar(105), mkBar(110)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [0, 0, 0], bars: bars, initialEquity: 100_000)
        #expect(r.sortino == 0)
        #expect(r.calmar == 0)
    }

    @Test("纯上涨持仓（无负 returns）· sortino 返 0（下行 std=0）")
    func sortinoNoDownsideReturnsZero() {
        // 100 → 110 → 120 持仓 · 都正 return · downside 空集 · sortino 应 0
        let bars = [mkBar(100), mkBar(110), mkBar(120)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1], bars: bars, initialEquity: 100_000)
        #expect(r.endingPnL > 0)        // 盈利存在
        #expect(r.sortino == 0)         // 但 sortino = 0（无下行波动）
    }

    @Test("有下行 returns · sortino > 0（且与 sharpe 不同）")
    func sortinoWithDownside() {
        // 持仓走 100 → 105 → 95 → 110 · 中间有亏损 bar
        let bars = [mkBar(100), mkBar(105), mkBar(95), mkBar(110)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1, 1], bars: bars, initialEquity: 100_000)
        #expect(r.sortino != 0)
        // sortino 分母只算负 returns · 通常 |sortino| ≥ |sharpe|（同 mean 更小分母）
        // 但符号一致
        if r.sharpe > 0 { #expect(r.sortino > 0) }
        if r.sharpe < 0 { #expect(r.sortino < 0) }
    }

    @Test("Calmar = endingPnL / maxDrawdown · 有回撤时正确")
    func calmarPositive() {
        // 持仓 100 → 120 → 90 → 130 · 最终 +30 · 最大回撤 = 120-90 = 30 · calmar = 30/30 = 1.0
        let bars = [mkBar(100), mkBar(120), mkBar(90), mkBar(130)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1, 1], bars: bars, initialEquity: 100_000)
        let endingD = (r.endingPnL as NSDecimalNumber).doubleValue
        let ddD = (r.maxDrawdown as NSDecimalNumber).doubleValue
        #expect(endingD == 30)
        #expect(ddD == 30)
        #expect(abs(r.calmar - 1.0) < 1e-9)
    }

    @Test("Calmar · maxDrawdown=0 时返 0 避 NaN")
    func calmarZeroDD() {
        // 单调上涨持仓 · 无回撤 · calmar=0 防 NaN
        let bars = [mkBar(100), mkBar(110), mkBar(120)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1], bars: bars, initialEquity: 100_000)
        #expect(r.maxDrawdown == 0)
        #expect(r.calmar == 0)
        #expect(!r.calmar.isNaN)
    }

    @Test("Calmar · 亏损 + 回撤 → 负 calmar")
    func calmarNegative() {
        // 持仓 100 → 110 → 80 · 最终 -20 · 最大回撤 = 110-80 = 30 · calmar = -20/30 < 0
        let bars = [mkBar(100), mkBar(110), mkBar(80)]
        let r = SimpleBacktestEngine.runWithSignal(signal: [1, 1, 1], bars: bars, initialEquity: 100_000)
        let endingD = (r.endingPnL as NSDecimalNumber).doubleValue
        #expect(endingD < 0)
        #expect(r.calmar < 0)
    }
}

@Suite("BacktestHistoryEntry · Codable 兼容老 JSON（v17.39-44）· v17.45 D2 v2")
struct BacktestHistoryEntryV2CompatTests {

    @Test("老 JSON（无 sortino/calmar 字段）· 解出 sortino=0 + calmar=0")
    func decodeOldJsonFallback() throws {
        // 模拟 v17.39-44 期间写入的 JSON · 缺 sortino + calmar
        let oldJson = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "createdAt": 770000000.0,
            "signalLineName": "BUY",
            "trajectoryRaw": "random",
            "barCount": 200,
            "initialEquity": 100000,
            "endingPnL": 500,
            "maxDrawdown": 100,
            "sharpe": 0.8,
            "winRate": 0.6,
            "expectancy": 50,
            "tradeCount": 10
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BacktestHistoryEntry.self, from: oldJson)
        #expect(decoded.sortino == 0)
        #expect(decoded.calmar == 0)
        #expect(decoded.signalLineName == "BUY")
        #expect(decoded.sharpe == 0.8)
    }

    @Test("新 JSON · 含 sortino + calmar · round-trip 保值")
    func decodeNewJsonRoundTrip() throws {
        let entry = BacktestHistoryEntry(
            id: UUID(), createdAt: Date(),
            signalLineName: "BUY", trajectoryRaw: "up",
            barCount: 100, initialEquity: 100_000,
            endingPnL: 1000, maxDrawdown: 200,
            sharpe: 1.2, sortino: 1.5, calmar: 5.0,
            winRate: 0.7, expectancy: 100, tradeCount: 10
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BacktestHistoryEntry.self, from: data)
        #expect(decoded == entry)
        #expect(decoded.sortino == 1.5)
        #expect(decoded.calmar == 5.0)
    }
}
