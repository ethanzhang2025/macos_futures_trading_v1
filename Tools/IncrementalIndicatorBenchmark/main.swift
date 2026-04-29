// WP-41 v2/v3 · IndicatorCore 增量 vs 全量 性能基准（30 指标 · v3 第 11 批扩展 PriceChannel + HV · Volatility.swift 6/6 100% 收官）
//
// 运行：swift run IncrementalIndicatorBenchmark（或 IndicatorBenchmark）
//
// 测试 30 个指标：
//   v2 commit 1-3（5）：MA20 / EMA12 / RSI14 / MACD 12-26-9 / BOLL 20-2
//   v3 第 1 批 commit 1-3（3）：KDJ 9-3-3 / CCI 20 / ATR 14
//   v3 第 2 批 commit 1-3（4）：OBV / WR 14 / ADX 14 / DMI 14（DMI 复用 ADX state · 验证零开销复用）
//   v3 第 3 批（1）：Stochastic 14-3
//   v3 第 4 批（1）：TRIX 12（内嵌 3 层 EMA · 同 MACD 模式）
//   v3 第 5 批（2）：DEMA 20 / TEMA 20（复合 EMA 线性组合 · 同 TRIX 模式但无差分）
//   v3 第 6 批（3）：VWAP（累积式无周期）/ PSY 12（单 ring sliding sum）/ CMO 14（双 ring · 同 RSI 思路无 Wilder）
//   v3 第 7 批（2）：ROC 12（ring 取 n 步前 close）/ BIAS 6（ring SMA · round8 snapshot 精度对齐）
//   v3 第 8 批（2）：WMA 10（O(1) Pascal triangle sliding）/ HMA 16（内嵌 3 WMA · halfN/n/sqrtN）
//   v3 第 9 批（2）：PVT（量价累积式同 OBV）/ Donchian 20（HHV/LLV 双 ring · 同 KDJ 模式）
//   v3 第 10 批（3）：KC 20-10-2（内嵌 EMA + ATR）/ StdDev 20（BOLL 简化）/ Envelopes 20-2.5（MA 复合 + 百分比偏移）
//   v3 第 11 批（2）：PriceChannel 20（Donchian 单 ring · close 版）/ HV 20-252（log 收益 + ring StdDev + annual scaling）
// 全量 = 每批调 calculate(kline: 1000K) 一次
// 增量 = 一次 makeIncrementalState(空 history) + 1000 次 stepIncremental
//
// 解读：
// - 加速比 = 全量/批 ÷ 增量/批（同等工作量）
// - 实际回放：每帧只 step 1 次 · 等价对比"全量 1000K calculate vs 1 次 step" · 实际加速量级 ~1000×
// - 性能瓶颈位置：ChartScene.handleReplayUpdate 内 computeIndicatorsAsync(bars 全量) · v2 commit 4 接入增量后消除

import Foundation
import Shared
import IndicatorCore

let barCount = 1000
let repeats = 100

// 模拟数据：上行 + 周期 7 噪声 · 让指标各值有差异
let baseDate = Date(timeIntervalSinceReferenceDate: 0)
let bars: [KLine] = (0..<barCount).map { i in
    let noise = i % 7 - 3
    let close = Decimal(100 + i + noise)
    return KLine(
        instrumentID: "TEST", period: .minute1,
        openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
        open: close - 1, high: close + 2, low: close - 2, close: close,
        volume: 100 + i, openInterest: 0, turnover: 0
    )
}
let series = KLineSeries(
    opens: bars.map(\.open),
    highs: bars.map(\.high),
    lows: bars.map(\.low),
    closes: bars.map(\.close),
    volumes: bars.map(\.volume),
    openInterests: bars.map { _ in 0 }
)
let emptyHistory = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])

@inline(__always)
func nanoseconds(_ block: () -> Void) -> UInt64 {
    let start = DispatchTime.now().uptimeNanoseconds
    block()
    return DispatchTime.now().uptimeNanoseconds - start
}

func benchmark(_ name: String, full: () -> Void, incremental: () -> Void) {
    let fullNS = nanoseconds {
        for _ in 0..<repeats { full() }
    }
    let incrNS = nanoseconds {
        for _ in 0..<repeats { incremental() }
    }
    let fullPerBatch = Double(fullNS) / Double(repeats) / 1_000.0     // µs / 批
    let incrPerBatch = Double(incrNS) / Double(repeats) / 1_000.0     // µs / 批
    let incrPerStep  = incrPerBatch / Double(barCount)                // µs / step
    let speedup      = fullPerBatch / incrPerBatch

    print(String(
        format: "%-14@  全量 %9.1f µs/批   增量 %9.1f µs/批  ·  %.3f µs/step  ·  %5.1fx 加速",
        name as CVarArg, fullPerBatch, incrPerBatch, incrPerStep, speedup
    ))
}

print("⏱  IndicatorCore 增量 vs 全量 性能基准")
print("   数据规模 \(barCount) K 线 · 每项 \(repeats) 次重复 · DispatchTime 纳秒计时")
print(String(repeating: "─", count: 96))

benchmark("MA(20)") {
    _ = try? MA.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? MA.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = MA.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("EMA(12)") {
    _ = try? EMA.calculate(kline: series, params: [12])
} incremental: {
    guard var state = try? EMA.makeIncrementalState(kline: emptyHistory, params: [12]) else { return }
    for bar in bars {
        _ = EMA.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("RSI(14)") {
    _ = try? RSI.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? RSI.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = RSI.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("MACD(12,26,9)") {
    _ = try? MACD.calculate(kline: series, params: [12, 26, 9])
} incremental: {
    guard var state = try? MACD.makeIncrementalState(kline: emptyHistory, params: [12, 26, 9]) else { return }
    for bar in bars {
        _ = MACD.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("BOLL(20,2)") {
    _ = try? BOLL.calculate(kline: series, params: [20, 2])
} incremental: {
    guard var state = try? BOLL.makeIncrementalState(kline: emptyHistory, params: [20, 2]) else { return }
    for bar in bars {
        _ = BOLL.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 commit 4/4 · 扩展 3 指标（KDJ / CCI / ATR）

benchmark("KDJ(9,3,3)") {
    _ = try? KDJ.calculate(kline: series, params: [9, 3, 3])
} incremental: {
    guard var state = try? KDJ.makeIncrementalState(kline: emptyHistory, params: [9, 3, 3]) else { return }
    for bar in bars {
        _ = KDJ.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("CCI(20)") {
    _ = try? CCI.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? CCI.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = CCI.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("ATR(14)") {
    _ = try? ATR.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? ATR.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = ATR.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 2 批 commit 4/4 · 扩展 4 指标（OBV / WR / ADX / DMI）

benchmark("OBV") {
    _ = try? OBV.calculate(kline: series, params: [])
} incremental: {
    guard var state = try? OBV.makeIncrementalState(kline: emptyHistory, params: []) else { return }
    for bar in bars {
        _ = OBV.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("WR(14)") {
    _ = try? WilliamsR.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? WilliamsR.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = WilliamsR.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("ADX(14)") {
    _ = try? ADX.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? ADX.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = ADX.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("DMI(14)") {
    _ = try? DMI.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? DMI.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = DMI.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 3 批 · Stochastic（双 ring HHV/LLV + %K_raw 滑动 sum 给 %D）

benchmark("STOCH(14,3)") {
    _ = try? Stochastic.calculate(kline: series, params: [14, 3])
} incremental: {
    guard var state = try? Stochastic.makeIncrementalState(kline: emptyHistory, params: [14, 3]) else { return }
    for bar in bars {
        _ = Stochastic.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 4 批 · TRIX（内嵌 3 EMA · 同 MACD 模式）

benchmark("TRIX(12)") {
    _ = try? TRIX.calculate(kline: series, params: [12])
} incremental: {
    guard var state = try? TRIX.makeIncrementalState(kline: emptyHistory, params: [12]) else { return }
    for bar in bars {
        _ = TRIX.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 5 批 · DEMA / TEMA（复合 EMA 线性组合）

benchmark("DEMA(20)") {
    _ = try? DEMA.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? DEMA.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = DEMA.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("TEMA(20)") {
    _ = try? TEMA.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? TEMA.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = TEMA.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 6 批 · VWAP / PSY / CMO

benchmark("VWAP") {
    _ = try? VWAP.calculate(kline: series, params: [])
} incremental: {
    guard var state = try? VWAP.makeIncrementalState(kline: emptyHistory, params: []) else { return }
    for bar in bars {
        _ = VWAP.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("PSY(12)") {
    _ = try? PSY.calculate(kline: series, params: [12])
} incremental: {
    guard var state = try? PSY.makeIncrementalState(kline: emptyHistory, params: [12]) else { return }
    for bar in bars {
        _ = PSY.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("CMO(14)") {
    _ = try? CMO.calculate(kline: series, params: [14])
} incremental: {
    guard var state = try? CMO.makeIncrementalState(kline: emptyHistory, params: [14]) else { return }
    for bar in bars {
        _ = CMO.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 7 批 · ROC / BIAS

benchmark("ROC(12)") {
    _ = try? ROC.calculate(kline: series, params: [12])
} incremental: {
    guard var state = try? ROC.makeIncrementalState(kline: emptyHistory, params: [12]) else { return }
    for bar in bars {
        _ = ROC.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("BIAS(6)") {
    _ = try? BIAS.calculate(kline: series, params: [6])
} incremental: {
    guard var state = try? BIAS.makeIncrementalState(kline: emptyHistory, params: [6]) else { return }
    for bar in bars {
        _ = BIAS.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 8 批 · WMA / HMA（线性加权 + Hull）

benchmark("WMA(10)") {
    _ = try? WMA.calculate(kline: series, params: [10])
} incremental: {
    guard var state = try? WMA.makeIncrementalState(kline: emptyHistory, params: [10]) else { return }
    for bar in bars {
        _ = WMA.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("HMA(16)") {
    _ = try? HMA.calculate(kline: series, params: [16])
} incremental: {
    guard var state = try? HMA.makeIncrementalState(kline: emptyHistory, params: [16]) else { return }
    for bar in bars {
        _ = HMA.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 9 批 · PVT / Donchian

benchmark("PVT") {
    _ = try? PVT.calculate(kline: series, params: [])
} incremental: {
    guard var state = try? PVT.makeIncrementalState(kline: emptyHistory, params: []) else { return }
    for bar in bars {
        _ = PVT.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("DONCHIAN(20)") {
    _ = try? Donchian.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? Donchian.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = Donchian.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 10 批 · KC / StdDev / Envelopes

benchmark("KC(20,10,2)") {
    _ = try? KC.calculate(kline: series, params: [20, 10, 2])
} incremental: {
    guard var state = try? KC.makeIncrementalState(kline: emptyHistory, params: [20, 10, 2]) else { return }
    for bar in bars {
        _ = KC.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("STDDEV(20)") {
    _ = try? StdDev.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? StdDev.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = StdDev.stepIncremental(state: &state, newBar: bar)
    }
}

let envPct = Decimal(string: "2.5")!
benchmark("ENV(20,2.5)") {
    _ = try? Envelopes.calculate(kline: series, params: [20, envPct])
} incremental: {
    guard var state = try? Envelopes.makeIncrementalState(kline: emptyHistory, params: [20, envPct]) else { return }
    for bar in bars {
        _ = Envelopes.stepIncremental(state: &state, newBar: bar)
    }
}

// MARK: - WP-41 v3 第 11 批 · PriceChannel / HV（Volatility.swift 6/6 100% 收官）

benchmark("PC(20)") {
    _ = try? PriceChannel.calculate(kline: series, params: [20])
} incremental: {
    guard var state = try? PriceChannel.makeIncrementalState(kline: emptyHistory, params: [20]) else { return }
    for bar in bars {
        _ = PriceChannel.stepIncremental(state: &state, newBar: bar)
    }
}

benchmark("HV(20,252)") {
    _ = try? HV.calculate(kline: series, params: [20, 252])
} incremental: {
    guard var state = try? HV.makeIncrementalState(kline: emptyHistory, params: [20, 252]) else { return }
    for bar in bars {
        _ = HV.stepIncremental(state: &state, newBar: bar)
    }
}

print(String(repeating: "─", count: 96))
print("说明：")
print("- 全量列：每批一次 calculate(\(barCount)K) · 等价 ChartScene 当前回放每帧的全量重算")
print("- 增量列：一次 makeIncrementalState(空) + \(barCount) 次 stepIncremental · 等价从空到末完整流程")
print("- 加速比 = 全量批耗时 / 增量批耗时（同等工作量 · 增量优势来自滑动窗口避免重复计算）")
print("- 实际回放场景：每帧只 step 1 次 · 真实加速量级 ≈ \(barCount)×（commit 4 ChartScene 接入后实测）")
