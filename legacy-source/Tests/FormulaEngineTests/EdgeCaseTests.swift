import Foundation
import Testing
@testable import FormulaEngine

@Suite("边界测试")
struct EdgeCaseTests {
    private func run(_ source: String, bars: [BarData]) throws -> [IndicatorLine] {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let formula = try parser.parse()
        return try Interpreter().execute(formula: formula, bars: bars)
    }

    @Test("空K线数据")
    func testEmptyBars() throws {
        let results = try run("R:CLOSE;", bars: [])
        #expect(results[0].values.isEmpty)
    }

    @Test("单根K线")
    func testSingleBar() throws {
        let bars = [BarData(open: 10, high: 12, low: 9, close: 11, volume: 100)]
        let results = try run("R:CLOSE;", bars: bars)
        #expect(results[0].values[0] == 11)
    }

    @Test("单根K线计算MA")
    func testSingleBarMA() throws {
        let bars = [BarData(open: 10, high: 12, low: 9, close: 11, volume: 100)]
        let results = try run("R:MA(CLOSE,5);", bars: bars)
        #expect(results[0].values[0] == nil) // 数据不足
    }

    @Test("除零保护")
    func testDivisionByZero() throws {
        let bars = [BarData(open: 0, high: 0, low: 0, close: 0, volume: 0)]
        let results = try run("R:CLOSE/OPEN;", bars: bars)
        #expect(results[0].values[0] == nil) // 除零返回nil
    }

    @Test("大量K线性能")
    func testLargeBars() throws {
        let bars = (0..<5000).map { i in
            BarData(open: Decimal(100 + i), high: Decimal(110 + i),
                    low: Decimal(90 + i), close: Decimal(105 + i), volume: 1000)
        }
        let results = try run("R:MA(CLOSE,20);", bars: bars)
        #expect(results[0].values.count == 5000)
        #expect(results[0].values[19] != nil) // 第20根有值
        #expect(results[0].values[18] == nil) // 第19根无值
    }

    @Test("连续赋值引用")
    func testChainedAssignment() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 9, close: 11, volume: 100),
            BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
            BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        ]
        let source = """
        A:=CLOSE+1;
        B:=A*2;
        C:B+3;
        """
        let results = try run(source, bars: bars)
        // C = (CLOSE+1)*2 + 3
        // C[0] = (11+1)*2 + 3 = 27
        #expect(results[0].values[0] == 27)
    }

    @Test("嵌套函数调用")
    func testNestedFunctions() throws {
        let bars = (0..<20).map { i in
            BarData(open: Decimal(100 + i), high: Decimal(110 + i),
                    low: Decimal(90 + i), close: Decimal(105 + i), volume: 1000)
        }
        let results = try run("R:MA(EMA(CLOSE,5),3);", bars: bars)
        #expect(results[0].values[19] != nil)
    }

    @Test("负数字面量")
    func testNegativeLiteral() throws {
        let bars = [BarData(open: 10, high: 12, low: 9, close: 11, volume: 100)]
        let results = try run("R:CLOSE+(-5);", bars: bars)
        #expect(results[0].values[0] == 6)
    }

    @Test("多重比较")
    func testMultipleComparisons() throws {
        let bars = [BarData(open: 10, high: 12, low: 9, close: 11, volume: 100)]
        let results = try run("R:CLOSE>10 AND CLOSE<20 AND OPEN>=10;", bars: bars)
        #expect(results[0].values[0] == 1)
    }

    @Test("语法错误 - 缺少分号")
    func testMissingSemicolon() throws {
        #expect(throws: ParserError.self) {
            var lexer = Lexer(source: "R:CLOSE")
            let tokens = try lexer.tokenize()
            var parser = Parser(tokens: tokens)
            _ = try parser.parse()
        }
    }

    @Test("语法错误 - 缺少右括号")
    func testMissingParenthesis() throws {
        #expect(throws: ParserError.self) {
            var lexer = Lexer(source: "R:MA(CLOSE,5;")
            let tokens = try lexer.tokenize()
            var parser = Parser(tokens: tokens)
            _ = try parser.parse()
        }
    }

    @Test("ISLASTBAR")
    func testISLASTBAR() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 9, close: 11, volume: 100),
            BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
            BarData(open: 12, high: 14, low: 11, close: 13, volume: 200),
        ]
        let results = try run("R:ISLASTBAR();", bars: bars)
        #expect(results[0].values[0] == 0)
        #expect(results[0].values[1] == 0)
        #expect(results[0].values[2] == 1)
    }

    @Test("BARPOS位置")
    func testBARPOS() throws {
        let bars = [
            BarData(open: 10, high: 12, low: 9, close: 11, volume: 100),
            BarData(open: 11, high: 13, low: 10, close: 12, volume: 150),
        ]
        let results = try run("R:BARPOS();", bars: bars)
        #expect(results[0].values[0] == 1)
        #expect(results[0].values[1] == 2)
    }

    @Test("函数总数>=50")
    func testFunctionCount50() throws {
        #expect(BuiltinFunctions.all.count >= 50)
    }
}
