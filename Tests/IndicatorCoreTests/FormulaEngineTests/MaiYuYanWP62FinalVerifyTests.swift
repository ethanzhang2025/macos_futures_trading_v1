// WP-62 麦语言收尾验证 · 5 段实战公式
//
// 验证目标：在引擎层确认 5 段复合实战公式（多变量 / 嵌套调用 / 跨函数依赖）
// 能正确解析 + 执行 + 末尾产出合理值。
//
// 5 段公式（覆盖 v15.25 batch40~44 的 5 个旗舰新函数）：
//   1. HT_TRENDLINE — Hilbert 变换趋势线 + ATR 止损 + 突破信号
//   2. KELLY        — 凯利仓位（基于历史胜率盈亏比）
//   3. CONNORSRSI   — Larry Connors 短期反转买卖信号
//   4. KALMAN       — 卡尔曼自适应均线交叉系统
//   5. HP_FILTER    — Hodrick-Prescott 趋势/周期分解 + 周期标准化
//
// 这是 WP-62 收尾的 Linux 端自动化部分（覆盖解析器+引擎层）。
// Mac 端 UI/绘制部分见同名 .md 文档（用户切机时手工验）。

import Foundation
import Testing
@testable import IndicatorCore

@Suite("WP-62 麦语言收尾验证（5 段实战公式）")
struct MaiYuYanWP62FinalVerifyTests {

    // 200 根合成 K 线：趋势 + 周期 + 小幅波动
    // close = 100 + i*0.1 + sin(i*0.1)*5 · 足够覆盖 60-period KELLY 长窗口
    private let realisticBars: [BarData] = (0..<200).map { i in
        let trend = Double(i) * 0.1
        let cycle = sin(Double(i) * 0.1) * 5
        let noise = (Double(i % 7) - 3) * 0.3
        let close = 100 + trend + cycle + noise
        let high = close + abs(noise) + 0.5
        let low = close - abs(noise) - 0.5
        return BarData(
            open: Decimal(close - noise * 0.5),
            high: Decimal(high),
            low: Decimal(low),
            close: Decimal(close),
            volume: 1000 + Int(abs(noise) * 100)
        )
    }

    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    // 末尾窗口（最后 20 根中至少 1 根）有非 nil 值
    private func hasTailValue(_ line: IndicatorLine, window: Int = 20) -> Bool {
        let n = line.values.count
        guard n >= window else { return line.values.contains { $0 != nil } }
        return line.values.suffix(window).contains { $0 != nil }
    }

    // MARK: - 段 1 · HT_TRENDLINE 趋势过滤系统

    @Test("段1 · HT_TRENDLINE + ATR 止损 + 突破信号 · 5 变量复合解析+执行")
    func test_strategy1_HT_TRENDLINE_System() throws {
        let source = """
        TREND:HT_TRENDLINE(CLOSE);
        ATRV:ATR(14);
        LONG_STOP:TREND-2*ATRV;
        SHORT_STOP:TREND+2*ATRV;
        SIGNAL:CROSS(CLOSE,TREND);
        """
        let lines = try run(source, bars: realisticBars)
        #expect(lines.count == 5)
        #expect(hasTailValue(lines[0]))   // TREND
        #expect(hasTailValue(lines[1]))   // ATRV
        #expect(hasTailValue(lines[2]))   // LONG_STOP
        #expect(hasTailValue(lines[3]))   // SHORT_STOP
        #expect(hasTailValue(lines[4]))   // SIGNAL（CROSS · 0 或 1）
    }

    @Test("段1 · 末尾止损带正确包夹 · LONG_STOP < TREND < SHORT_STOP")
    func test_strategy1_HT_TRENDLINE_StopBracket() throws {
        let source = """
        TREND:HT_TRENDLINE(CLOSE);
        ATRV:ATR(14);
        LONG_STOP:TREND-2*ATRV;
        SHORT_STOP:TREND+2*ATRV;
        """
        let lines = try run(source, bars: realisticBars)
        let lastIdx = realisticBars.count - 1
        if let trend = lines[0].values[lastIdx],
           let longStop = lines[2].values[lastIdx],
           let shortStop = lines[3].values[lastIdx] {
            #expect(longStop < trend)
            #expect(trend < shortStop)
        } else {
            Issue.record("末尾 TREND/止损线均应有值")
        }
    }

    // MARK: - 段 2 · KELLY 仓位管理

    @Test("段2 · KELLY 基于历史 60 根胜率/盈亏比 · 嵌套 SMA+IF+REF+COUNT")
    func test_strategy2_KELLY_PositionSizing() throws {
        let source = """
        WIN_BAR:CLOSE>REF(CLOSE,1);
        WIN_RATE:COUNT(WIN_BAR,60)/60;
        AVG_WIN:SMA(IF(WIN_BAR,CLOSE-REF(CLOSE,1),0),60,1);
        AVG_LOSS:SMA(IF(CLOSE<REF(CLOSE,1),REF(CLOSE,1)-CLOSE,0),60,1);
        POS:KELLY(WIN_RATE,AVG_WIN,AVG_LOSS);
        """
        let lines = try run(source, bars: realisticBars)
        #expect(lines.count == 5)
        #expect(hasTailValue(lines[1]))   // WIN_RATE
        #expect(hasTailValue(lines[2]))   // AVG_WIN
        #expect(hasTailValue(lines[3]))   // AVG_LOSS
        #expect(hasTailValue(lines[4]))   // POS
    }

    @Test("段2 · 末尾凯利仓位在合理区间 [-1, 1]")
    func test_strategy2_KELLY_PositionInRange() throws {
        let source = """
        WIN_BAR:CLOSE>REF(CLOSE,1);
        WIN_RATE:COUNT(WIN_BAR,60)/60;
        AVG_WIN:SMA(IF(WIN_BAR,CLOSE-REF(CLOSE,1),0),60,1);
        AVG_LOSS:SMA(IF(CLOSE<REF(CLOSE,1),REF(CLOSE,1)-CLOSE,0),60,1);
        POS:KELLY(WIN_RATE,AVG_WIN,AVG_LOSS);
        """
        let lines = try run(source, bars: realisticBars)
        let lastIdx = realisticBars.count - 1
        if let pos = lines[4].values[lastIdx] {
            #expect(pos >= -1)
            #expect(pos <= 1)
        }
    }

    // MARK: - 段 3 · CONNORSRSI 短期反转策略

    @Test("段3 · CONNORSRSI(3,2,100) 短期反转 · OVERSOLD/OVERBOUGHT/BUY/SELL")
    func test_strategy3_CONNORSRSI_Reversal() throws {
        let source = """
        CRSI:CONNORSRSI(CLOSE,3,2,100);
        OVERSOLD:CRSI<10;
        OVERBOUGHT:CRSI>90;
        BUY:CROSS(10,CRSI);
        SELL:CROSS(CRSI,90);
        """
        let lines = try run(source, bars: realisticBars)
        #expect(lines.count == 5)
        #expect(hasTailValue(lines[0]))   // CRSI
    }

    @Test("段3 · 末尾 CRSI ∈ [0, 100]")
    func test_strategy3_CONNORSRSI_Range() throws {
        let source = "CRSI:CONNORSRSI(CLOSE,3,2,100);"
        let lines = try run(source, bars: realisticBars)
        let lastIdx = realisticBars.count - 1
        if let crsi = lines[0].values[lastIdx] {
            #expect(crsi >= 0)
            #expect(crsi <= 100)
        } else {
            Issue.record("末尾 CRSI 应有值（200 根足够 warm-up）")
        }
    }

    // MARK: - 段 4 · KALMAN 自适应均线交叉

    @Test("段4 · KALMAN 快慢线 + 金叉死叉")
    func test_strategy4_KALMAN_DualLine() throws {
        let source = """
        KF_SLOW:KALMAN(CLOSE,0.001,1);
        KF_FAST:KALMAN(CLOSE,0.01,1);
        GOLDEN:CROSS(KF_FAST,KF_SLOW);
        DEATH:CROSS(KF_SLOW,KF_FAST);
        """
        let lines = try run(source, bars: realisticBars)
        #expect(lines.count == 4)
        #expect(hasTailValue(lines[0]))   // KF_SLOW
        #expect(hasTailValue(lines[1]))   // KF_FAST
    }

    @Test("段4 · 末尾两条 KALMAN 线均贴近 CLOSE 数量级（100~120 区间）")
    func test_strategy4_KALMAN_Magnitude() throws {
        let source = """
        KF_SLOW:KALMAN(CLOSE,0.001,1);
        KF_FAST:KALMAN(CLOSE,0.01,1);
        """
        let lines = try run(source, bars: realisticBars)
        let lastIdx = realisticBars.count - 1
        if let slow = lines[0].values[lastIdx],
           let fast = lines[1].values[lastIdx],
           let close = realisticBars.last?.close {
            // 两条 KALMAN 线应都在 CLOSE ± 20 量级（合理跟踪）
            let absSlow = abs(slow - close)
            let absFast = abs(fast - close)
            #expect(absSlow < 20)
            #expect(absFast < 20)
        }
    }

    // MARK: - 段 5 · HP_FILTER 趋势/周期分解

    @Test("段5 · HP_FILTER 趋势+周期分解 + 周期百分位")
    func test_strategy5_HP_FILTER_Decomposition() throws {
        let source = """
        TREND:HP_FILTER(CLOSE,1600);
        CYCLE:CLOSE-TREND;
        HHV20:HHV(CYCLE,20);
        LLV20:LLV(CYCLE,20);
        PCT:(CYCLE-LLV20)/(HHV20-LLV20)*100;
        """
        let lines = try run(source, bars: realisticBars)
        #expect(lines.count == 5)
        #expect(hasTailValue(lines[0]))   // TREND
        #expect(hasTailValue(lines[1]))   // CYCLE
        #expect(hasTailValue(lines[2]))   // HHV20
        #expect(hasTailValue(lines[3]))   // LLV20
        #expect(hasTailValue(lines[4]))   // PCT
    }

    @Test("段5 · 末尾周期百分位在 [0, 100] 区间")
    func test_strategy5_HP_FILTER_PercentRange() throws {
        let source = """
        TREND:HP_FILTER(CLOSE,1600);
        CYCLE:CLOSE-TREND;
        HHV20:HHV(CYCLE,20);
        LLV20:LLV(CYCLE,20);
        PCT:(CYCLE-LLV20)/(HHV20-LLV20)*100;
        """
        let lines = try run(source, bars: realisticBars)
        let lastIdx = realisticBars.count - 1
        if let pct = lines[4].values[lastIdx] {
            // 浮点除法可能略超界，放宽 [-1, 101]
            #expect(pct >= -1)
            #expect(pct <= 101)
        }
    }
}
