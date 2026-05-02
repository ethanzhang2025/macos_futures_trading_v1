import Foundation
import Testing
@testable import IndicatorCore

@Suite("Interpreter Tests")
struct InterpreterTests {
    /// 构造测试用K线数据
    private let testBars: [BarData] = [
        BarData(open: 10, high: 12, low: 9,  close: 11, volume: 100),
        BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
        BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        BarData(open: 13, high: 15, low: 12, close: 14, volume: 180),
        BarData(open: 14, high: 16, low: 13, close: 15, volume: 220),
        BarData(open: 15, high: 17, low: 14, close: 14, volume: 190),
        BarData(open: 14, high: 15, low: 12, close: 13, volume: 210),
        BarData(open: 13, high: 14, low: 11, close: 12, volume: 170),
        BarData(open: 12, high: 13, low: 10, close: 11, volume: 160),
        BarData(open: 11, high: 12, low: 9,  close: 10, volume: 140),
    ]

    private func run(_ source: String) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        let interpreter = Interpreter()
        return try interpreter.execute(formula: formula, bars: testBars)
    }

    @Test("MA计算")
    func testMA() throws {
        let results = try run("MA3:MA(CLOSE,3);")
        #expect(results.count == 1)
        #expect(results[0].name == "MA3")
        let values = results[0].values
        // MA(3) 前2个为nil
        #expect(values[0] == nil)
        #expect(values[1] == nil)
        // 第3个 = (11+12+13)/3 = 12
        #expect(values[2] == 12)
        // 第4个 = (12+13+14)/3 = 13
        #expect(values[3] == 13)
    }

    @Test("EMA计算")
    func testEMA() throws {
        let results = try run("E:EMA(CLOSE,3);")
        #expect(results.count == 1)
        let values = results[0].values
        // EMA第一个值 = CLOSE[0] = 11
        #expect(values[0] == 11)
        // EMA[1] = 2/4 * 12 + 2/4 * 11 = 6 + 5.5 = 11.5
        #expect(values[1] == Decimal(string: "11.5"))
    }

    @Test("CROSS函数")
    func testCROSS() throws {
        // MA3上穿MA5
        let source = """
        MA3:=MA(CLOSE,3);
        MA5:=MA(CLOSE,5);
        X:CROSS(MA3,MA5);
        """
        let results = try run(source)
        let crossLine = results.first { $0.name == "X" }
        #expect(crossLine != nil)
    }

    @Test("IF函数")
    func testIF() throws {
        let results = try run("R:IF(CLOSE>OPEN,1,0);")
        let values = results[0].values
        // 第1根: close=11 > open=10 → 1
        #expect(values[0] == 1)
        // 第6根: close=14 < open=15 → 0
        #expect(values[5] == 0)
    }

    @Test("HHV和LLV")
    func testHHVLLV() throws {
        let results = try run("H3:HHV(HIGH,3);L3:LLV(LOW,3);")
        #expect(results.count == 2)
        // 第3根的HHV(HIGH,3) = max(12,13,14) = 14
        #expect(results[0].values[2] == 14)
        // 第3根的LLV(LOW,3) = min(9,10,11) = 9
        #expect(results[1].values[2] == 9)
    }

    @Test("REF函数")
    func testREF() throws {
        let results = try run("R:REF(CLOSE,1);")
        let values = results[0].values
        // REF(CLOSE,1)[0] = nil
        #expect(values[0] == nil)
        // REF(CLOSE,1)[1] = CLOSE[0] = 11
        #expect(values[1] == 11)
        // REF(CLOSE,1)[5] = CLOSE[4] = 15
        #expect(values[5] == 15)
    }

    @Test("算术运算")
    func testArithmetic() throws {
        let results = try run("R:CLOSE*2+1;")
        let values = results[0].values
        // CLOSE[0]*2+1 = 11*2+1 = 23
        #expect(values[0] == 23)
    }

    /// v15.16 hotfix #16 · P1-3：取模 quotient 超 Int.max 时不再静默错（Decimal floor 路径）
    @Test("取模 · 小数范围内")
    func testModuloSmall() throws {
        let results = try run("R:CLOSE%5;")
        let values = results[0].values
        // CLOSE[0]=11, 11 % 5 = 1
        #expect(values[0] == 1)
        // CLOSE[5]=14, 14 % 5 = 4
        #expect(values[5] == 4)
    }

    @Test("取模 · 大数 quotient 超 Int.max（v15.16 hotfix P1-3 防溢出）")
    func testModuloLarge() throws {
        // 1e18 / 3 ≈ 3.33e17 远超 Int.max (~9.2e18 实际范围内 · 用更大数测真溢出)
        // Int.max ≈ 9.22e18 · 用 1e20 / 3 触发 quotient ≈ 3.3e19 超 Int.max
        // 公式 R:CLOSE*1e20%3 · CLOSE[0]=11 → 11e20 / 3 quotient 超 Int.max
        let results = try run("R:(CLOSE*100000000000000000000)%3;")
        let values = results[0].values
        // 修复前：Int 截断 platform-defined · 结果错（可能负数巨值）
        // 修复后：Decimal floor 路径正确 · 11×1e20 = 1.1×1e21 · 1.1×1e21 mod 3 应是确定值（不是 NaN/0）
        // 11 * 10^20 = 1100000000000000000000 (1.1e21)
        // 1.1e21 / 3 = 3.6666...e20 → floor = 3.66666666666666666666e20（截至 Decimal 8 位精度）
        // 实际验证仅断言"不为 nil + 在 [0, 3) 范围"
        guard let v = values[0] else {
            Issue.record("modulo result should not be nil")
            return
        }
        #expect(v >= 0 && v < 3)
    }

    @Test("取模 · 负数（quotient 负数 · Decimal .down 截向 0 一致行为）")
    func testModuloNegative() throws {
        // -7 % 3 · quotient = -7/3 = -2.333 → floor 截向 0 = -2 → -7 - (-2)*3 = -1
        let results = try run("R:(CLOSE-18)%3;")  // CLOSE[0]=11 → 11-18=-7 → -7%3
        let values = results[0].values
        // 期望 -1（与 Swift / C 标准 truncated modulo 一致 · 不是 Python 的 floor modulo）
        #expect(values[0] == -1)
    }

    @Test("MACD完整公式")
    func testMACDFormula() throws {
        let source = """
        DIF:EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:EMA(DIF,9);
        MACD:2*(DIF-DEA),COLORSTICK;
        """
        let results = try run(source)
        #expect(results.count == 3)
        #expect(results[0].name == "DIF")
        #expect(results[1].name == "DEA")
        #expect(results[2].name == "MACD")
        #expect(results[2].attributes == ["COLORSTICK"])
        // 所有值都应该有值（10根K线足够计算）
        #expect(results[0].values[0] != nil)
    }

    @Test("中间变量不输出")
    func testIntermediateNotOutput() throws {
        let source = """
        MA5:=MA(CLOSE,5);
        R:MA5;
        """
        let results = try run(source)
        // MA5是中间变量(:=)，不应出现在输出中
        #expect(results.count == 1)
        #expect(results[0].name == "R")
    }

    @Test("未定义变量报错")
    func testUndefinedVariable() throws {
        #expect(throws: InterpreterError.self) {
            _ = try run("R:UNDEFINED_VAR;")
        }
    }

    @Test("未定义函数报错")
    func testUndefinedFunction() throws {
        #expect(throws: InterpreterError.self) {
            _ = try run("R:UNKNOWN_FUNC(CLOSE,5);")
        }
    }
}
