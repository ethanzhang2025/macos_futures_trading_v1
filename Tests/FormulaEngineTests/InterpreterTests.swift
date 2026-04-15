import Foundation
import Testing
@testable import FormulaEngine

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
