// v17.163 · PatternDetector 单测
//
// 验证：
// - 4 种形态精确识别（手工构造典型 pivot 序列）
// - 阈值边界（肩对称 / 头突出 / 颈线 / 双顶容忍 / 中间回撤）
// - 重叠去重（同 endIndex 保留 confidence 最高）
// - 空序列 / 不足 pivot / 噪声不误报

import Testing
import Foundation
import Shared
@testable import IndicatorCore

@Suite("v17.163 · PatternDetector 形态识别")
struct PatternDetectorTests {

    // MARK: - 头肩顶（peak-trough-peak-trough-peak · 头高于肩 · 肩对称）

    @Test("头肩顶 · 典型 pivot 价格 100/90/115/89/101 · 检出 confidence > 0.5")
    func detectHeadAndShouldersTop() throws {
        // 设计 K 线：左肩 100 · 谷 90 · 头 115 · 谷 89 · 右肩 101
        // ZigZag percent=3 应该正好捕获这 5 个 pivot（5/100 ≈ 5% 摆动 · > 3% 阈值）
        let prices: [Double] = [100, 100, 90, 90, 90, 115, 115, 89, 89, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let kline = makeSeries(bars: bars)
        let detected = try PatternDetector.detect(kline: kline, params: .default)
        let hsTop = detected.filter { $0.kind == .headAndShouldersTop }
        #expect(hsTop.count >= 1, "应至少检出 1 个头肩顶 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = hsTop.first {
            #expect(p.pivotPrices.count == 5)
            #expect(p.confidence > 0.5)
        }
    }

    @Test("头肩顶 · 肩极不对称（左肩 100 / 右肩 130）· 不应识别（shoulderDiff > 10%）")
    func headAndShouldersTopRejectsAsymmetricShoulders() throws {
        let prices: [Double] = [100, 90, 115, 89, 130, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .headAndShouldersTop }.isEmpty)
    }

    @Test("头肩顶 · 头不突出（头 102 vs 肩 100）· 不应识别（prominence < 3%）")
    func headAndShouldersTopRejectsWeakHead() throws {
        let prices: [Double] = [100, 90, 102, 89, 100, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .headAndShouldersTop }.isEmpty)
    }

    // MARK: - 头肩底（mirror）

    @Test("头肩底 · 典型 pivot 100/110/85/111/99 · 检出")
    func detectHeadAndShouldersBottom() throws {
        let prices: [Double] = [100, 100, 110, 110, 85, 85, 111, 111, 99, 99, 105]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let hsBot = detected.filter { $0.kind == .headAndShouldersBottom }
        #expect(hsBot.count >= 1, "应至少检出 1 个头肩底")
        if let p = hsBot.first {
            #expect(p.kind.direction == 1, "看多反转")
        }
    }

    // MARK: - 双顶

    @Test("双顶 · 典型 pivot 100/90/101 · 检出 · 双底 mirror")
    func detectDoubleTop() throws {
        let prices: [Double] = [100, 100, 90, 90, 90, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let dTop = detected.filter { $0.kind == .doubleTop }
        #expect(dTop.count >= 1)
        if let p = dTop.first {
            #expect(p.pivotPrices.count == 3)
            #expect(p.kind.direction == -1)
        }
    }

    @Test("双顶 · 两顶差距过大（100 vs 110）· 不应识别（topDiff > 3%）")
    func doubleTopRejectsLargeGap() throws {
        let prices: [Double] = [100, 90, 110, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .doubleTop }.isEmpty)
    }

    @Test("双顶 · 中间回撤太浅（100 vs 99 vs 100）· 不应识别（retracement < 2%）")
    func doubleTopRejectsShallowRetracement() throws {
        let prices: [Double] = [100, 99, 100, 95]
        let bars = makeBarsFromCloses(prices)
        // ZigZag 3% 阈值下 · 99 → 100 仅 1% 不算 pivot · 故 pivot 不足直接不出形态
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .doubleTop }.isEmpty)
    }

    @Test("双底 · 典型 pivot 100/110/101 · 检出")
    func detectDoubleBottom() throws {
        let prices: [Double] = [100, 100, 110, 110, 101, 101, 110]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let dBot = detected.filter { $0.kind == .doubleBottom }
        #expect(dBot.count >= 1)
        if let p = dBot.first {
            #expect(p.kind.direction == 1)
        }
    }

    // MARK: - 边界

    @Test("空 KLine · 返回空列表")
    func emptyKLine() throws {
        let kline = KLineSeries(opens: [], highs: [], lows: [], closes: [], volumes: [], openInterests: [])
        let detected = try PatternDetector.detect(kline: kline, params: .default)
        #expect(detected.isEmpty)
    }

    @Test("单调上涨 · 无 pivot · 不出形态")
    func monotonicUptrend() throws {
        let prices = (0..<50).map { 100.0 + Double($0) }
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.isEmpty)
    }

    // MARK: - 重叠去重

    @Test("同 endIndex 多命中 · 仅保留最高 confidence（dedupByEndIndex）")
    func dedupByEndIndex() throws {
        // 设计：5 pivot 同时满足 HS top + 内部 3 pivot 双顶
        // 100 / 90 / 115 / 89 / 101 ← HS top
        //          ↓ 内部 3 个：90 / 115 / 89 → 不算 doubleTop（90/89 是 trough · 115 是 peak）
        //          正确双顶覆盖：100/90/101 仍是另一个窗口（3 pivot 在 i=0..2 + 0..3? 取决于 pivot 索引）
        // ZigZag 给出的 pivot 数量取决于 percent · 这里只验证 dedup 不重复输出 endIndex
        let prices: [Double] = [100, 100, 90, 90, 90, 115, 115, 89, 89, 101, 101, 95]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let ends = detected.map(\.endIndex)
        #expect(Set(ends).count == ends.count, "dedup 后 endIndex 不重复 · 实际 \(ends)")
    }

    // MARK: - v17.173 · 三角 / 矩形

    @Test("上升三角 · 两顶 ≈ 水平 + 底逐步抬升 · 检出 direction +1")
    func detectAscendingTriangle() throws {
        // 4 pivot：低 100 / 高 120 / 低 110 / 高 121
        // 顶水平差 = 1/121 ≈ 0.83% ≤ 2% ✓ · 底抬升 = 10/100 = 10% ≥ 1.5% ✓
        let prices: [Double] = [100, 100, 120, 120, 110, 110, 121, 121, 115]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let asc = detected.filter { $0.kind == .ascendingTriangle }
        #expect(asc.count >= 1, "应至少检出 1 个上升三角 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = asc.first {
            #expect(p.kind.direction == 1)
            #expect(p.pivotPrices.count == 4)
        }
    }

    @Test("下降三角 · 两底 ≈ 水平 + 顶逐步下压 · 检出 direction -1")
    func detectDescendingTriangle() throws {
        // 4 pivot：高 120 / 低 100 / 高 110 / 低 101
        // 底水平差 = 1/100 = 1% ≤ 2% ✓ · 顶下压 = 10/120 ≈ 8.3% ≥ 1.5% ✓
        let prices: [Double] = [120, 120, 100, 100, 110, 110, 101, 101, 105]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let desc = detected.filter { $0.kind == .descendingTriangle }
        #expect(desc.count >= 1)
        if let p = desc.first {
            #expect(p.kind.direction == -1)
        }
    }

    @Test("矩形 · 顶底都水平 + range 足够 · 检出 direction 0（中性）")
    func detectRectangle() throws {
        // 4 pivot peak-trough-peak-trough：120/100/121/101
        // 顶差 = 1/121 ≈ 0.83% · 底差 = 1/100 = 1% · 都 ≤ 2% ✓
        // range = (120.5-100.5)/100.5 ≈ 19.9% · 远 ≥ 2% ✓
        let prices: [Double] = [120, 120, 100, 100, 121, 121, 101, 101, 110]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let rect = detected.filter { $0.kind == .rectangle }
        #expect(rect.count >= 1)
        if let p = rect.first {
            #expect(p.kind.direction == 0)
        }
    }

    @Test("上升三角 · 底没抬升（10 持平）· 不应识别")
    func ascendingTriangleRejectsFlatLow() throws {
        // 4 pivot：低 100 / 高 120 / 低 100.5 / 高 121
        // 底抬升 = 0.5/100 = 0.5% < 1.5% 阈值 · 拒
        let prices: [Double] = [100, 100, 120, 120, 100.5, 100.5, 121, 121, 115]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .ascendingTriangle }.isEmpty)
    }

    @Test("矩形 · range 太小（≤ 2%）· 不应识别")
    func rectangleRejectsThinRange() throws {
        // 4 pivot peak-trough-peak-trough：101/100/100.8/100.2
        // 顶底水平 OK · 但 range = 0.4/100.2 ≈ 0.4% < 2% · 拒
        let prices: [Double] = [101, 101, 100, 100, 100.8, 100.8, 100.2, 100.2, 100.5]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .rectangle }.isEmpty)
    }

    @Test("下降三角 · 两底不水平（差 6%）· 不应识别")
    func descendingTriangleRejectsAsymmetricBottoms() throws {
        // 4 pivot：高 120 / 低 100 / 高 110 / 低 106  · 底差 = 6/100 = 6% > 2% 阈值
        let prices: [Double] = [120, 120, 100, 100, 110, 110, 106, 106, 105]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .descendingTriangle }.isEmpty)
    }

    @Test("PatternKind allCases · v17.188 后扩到 13 case（v17.177 9 + 旗形/三角旗/杯柄 4）")
    func patternKindAllCasesCount() {
        #expect(PatternKind.allCases.count == 13)
        let kinds = Set(PatternKind.allCases)
        #expect(kinds.contains(.ascendingTriangle))
        #expect(kinds.contains(.descendingTriangle))
        #expect(kinds.contains(.rectangle))
        #expect(kinds.contains(.risingWedge))
        #expect(kinds.contains(.fallingWedge))
        #expect(kinds.contains(.bullishFlag))
        #expect(kinds.contains(.bearishFlag))
        #expect(kinds.contains(.pennant))
        #expect(kinds.contains(.cupAndHandle))
    }

    // MARK: - v17.188 · 旗形 / 三角旗 / 杯柄

    @Test("看多旗形 · pole 100→120 + body 顶/底略下倾平行 · 检出 direction +1")
    func detectBullishFlag() throws {
        // 5 pivot 100/120/114/118/112 · pole +20% ≥ 5% · 顶降 1.67% · 底降 1.75% · ratio 1.05 ≤ 1.5
        let prices: [Double] = [100, 100, 120, 120, 114, 114, 118, 118, 112, 112, 115]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let flag = detected.filter { $0.kind == .bullishFlag }
        #expect(flag.count >= 1, "应至少检出 1 个看多旗形 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = flag.first {
            #expect(p.kind.direction == 1)
            #expect(p.pivotPrices.count == 5)
        }
    }

    @Test("看空旗形 · pole 120→100 + body 顶/底略上倾平行 · 检出 direction -1")
    func detectBearishFlag() throws {
        // 5 pivot 120/100/106/102/108 · pole -16.67% ≥ 5% · 底升 2% · 顶升 1.89% · ratio 1.06 ≤ 1.5
        let prices: [Double] = [120, 120, 100, 100, 106, 106, 102, 102, 108, 108, 105]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let flag = detected.filter { $0.kind == .bearishFlag }
        #expect(flag.count >= 1, "应至少检出 1 个看空旗形 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = flag.first {
            #expect(p.kind.direction == -1)
        }
    }

    @Test("三角旗 · bull pole 100→120 + body 顶降 + 底升 收敛 · 检出 direction 0（跟随 pole）")
    func detectPennant() throws {
        // 5 pivot 100/120/110/116/112 · pole +20% · 顶降 3.33% · 底升 1.82% · convergence 1.83 ≤ 3
        let prices: [Double] = [100, 100, 120, 120, 110, 110, 116, 116, 112, 112, 114]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let pen = detected.filter { $0.kind == .pennant }
        #expect(pen.count >= 1, "应至少检出 1 个三角旗 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = pen.first {
            #expect(p.kind.direction == 0)
            #expect(p.pivotPrices.count == 5)
        }
    }

    @Test("杯柄 · 两口 120/119 对称 + 杯底 100 深 16% + 柄 114 浅 · 检出 direction +1")
    func detectCupAndHandle() throws {
        // 5 pivot 120/100/119/114/120 · rimDiff 0.83% ≤ 5% · cupDepth 16.32% ≥ 10% · handle 4.2% ≤ cupDepth*0.5
        let prices: [Double] = [120, 120, 100, 100, 119, 119, 114, 114, 120, 120, 118]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let cup = detected.filter { $0.kind == .cupAndHandle }
        #expect(cup.count >= 1, "应至少检出 1 个杯柄 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = cup.first {
            #expect(p.kind.direction == 1)
            #expect(p.pivotPrices.count == 5)
        }
    }

    @Test("看多旗形 · body 顶降过陡（5%）> flagBodyMaxSlope 3% · 不应识别")
    func bullishFlagRejectsSteepBody() throws {
        // pivots 100/120/110/114/108 · topSlope (120-114)/120 = 5% > 3% 阈值
        let prices: [Double] = [100, 100, 120, 120, 110, 110, 114, 114, 108, 108, 110]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .bullishFlag }.isEmpty)
    }

    @Test("看空旗形 · body 顶升过陡（8.5%）> flagBodyMaxSlope 3% · 不应识别")
    func bearishFlagRejectsSteepBody() throws {
        // pivots 120/100/106/102/115 · topSlope (115-106)/106 = 8.49% > 3%
        let prices: [Double] = [120, 120, 100, 100, 106, 106, 102, 102, 115, 115, 110]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .bearishFlag }.isEmpty)
    }

    @Test("三角旗 · body 顶降+底降（同向不收敛）· 不应识别")
    func pennantRejectsParallelBody() throws {
        // pivots 100/120/110/116/106 · 顶降 3.33% ✓ · 底降 3.64% ✗（pennant 要求底升）
        let prices: [Double] = [100, 100, 120, 120, 110, 110, 116, 116, 106, 106, 108]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .pennant }.isEmpty)
    }

    @Test("杯柄 · 两口 120/130 不对称（diff 7.7%）> cupRimTolerance 5% · 不应识别")
    func cupAndHandleRejectsAsymmetricRims() throws {
        // pivots 120/100/130/124/128 · rimDiff (130-120)/130 ≈ 7.69% > 5% 阈值
        let prices: [Double] = [120, 120, 100, 100, 130, 130, 124, 124, 128, 128, 126]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .cupAndHandle }.isEmpty)
    }

    // MARK: - v17.177 · 楔形

    @Test("上升楔形 · 3 顶+2 底都升 · 底升更快收敛 · 检出 direction -1（看空反转）")
    func detectRisingWedge() throws {
        // 5 pivot 期待：100/80/110/100/112
        // 顶升 (112-100)/100 = 12% · 底升 (100-80)/80 = 25% · ratio = 25/12 ≈ 2.08 ≥ 1.5
        let prices: [Double] = [100, 100, 80, 80, 80, 110, 110, 100, 100, 112, 112, 108]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let wedge = detected.filter { $0.kind == .risingWedge }
        #expect(wedge.count >= 1, "应至少检出 1 个上升楔形 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = wedge.first {
            #expect(p.kind.direction == -1)
            #expect(p.pivotPrices.count == 5)
        }
    }

    @Test("下降楔形 · 3 底+2 顶都降 · 顶降更快收敛 · 检出 direction +1（看多反转）")
    func detectFallingWedge() throws {
        // 5 pivot 期待：110/140/100/105/95
        // 底降 (110-95)/110 ≈ 13.6% · 顶降 (140-105)/140 = 25% · ratio = 25/13.6 ≈ 1.83 ≥ 1.5
        let prices: [Double] = [110, 110, 140, 140, 100, 100, 105, 105, 95, 95, 98]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let wedge = detected.filter { $0.kind == .fallingWedge }
        #expect(wedge.count >= 1, "应至少检出 1 个下降楔形 · detected=\(detected.map { ($0.kind, $0.confidence) })")
        if let p = wedge.first {
            #expect(p.kind.direction == 1)
            #expect(p.pivotPrices.count == 5)
        }
    }

    @Test("上升楔形 · 顶升 = 底升（无收敛）· 不应识别")
    func risingWedgeRejectsNoConvergence() throws {
        // 顶 100, 110, 120（slope 20%）· 底 80, 90（slope 12.5%）· ratio = 12.5/20 = 0.625 < 1.5 拒
        let prices: [Double] = [100, 100, 80, 80, 80, 110, 110, 90, 90, 120, 120, 115]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .risingWedge }.isEmpty)
    }

    @Test("下降楔形 · 底升而非降 · 不应识别（违反 lows 单调下降）")
    func fallingWedgeRejectsAscendingLows() throws {
        // 底 100, 105, 110（上升而非下降）· 顶 140, 120
        let prices: [Double] = [100, 100, 140, 140, 105, 105, 120, 120, 110, 110, 115]
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        #expect(detected.filter { $0.kind == .fallingWedge }.isEmpty)
    }

    // MARK: - 排序

    @Test("结果按 startIndex 升序")
    func sortedByStartIndex() throws {
        // 构造两段独立的双顶：第一段在 0..15 · 第二段在 30..45
        let segment1: [Double] = [100, 100, 90, 90, 101, 101, 95, 95]
        let connector: [Double] = Array(repeating: 95.0, count: 20)
        let segment2: [Double] = [80, 80, 90, 90, 80, 80, 85]
        let prices = segment1 + connector + segment2
        let bars = makeBarsFromCloses(prices)
        let detected = try PatternDetector.detect(kline: makeSeries(bars: bars), params: .default)
        let starts = detected.map(\.startIndex)
        #expect(starts == starts.sorted(), "starts 应升序 · 实际 \(starts)")
    }
}

// MARK: - 共享 helper

fileprivate func makeBarsFromCloses(_ closes: [Double]) -> [KLine] {
    let baseDate = Date(timeIntervalSinceReferenceDate: 0)
    return closes.enumerated().map { i, c in
        // OHLC 都取 close ± 微小噪声 · 让 ZigZag 仅基于 close 判断
        KLine(
            instrumentID: "TEST",
            period: .minute1,
            openTime: baseDate.addingTimeInterval(TimeInterval(i * 60)),
            open: Decimal(c),
            high: Decimal(c + 0.1),
            low: Decimal(c - 0.1),
            close: Decimal(c),
            volume: 100,
            openInterest: 0,
            turnover: 0
        )
    }
}

fileprivate func makeSeries(bars: [KLine]) -> KLineSeries {
    KLineSeries(
        opens: bars.map(\.open),
        highs: bars.map(\.high),
        lows: bars.map(\.low),
        closes: bars.map(\.close),
        volumes: bars.map(\.volume),
        openInterests: bars.map { _ in 0 }
    )
}
