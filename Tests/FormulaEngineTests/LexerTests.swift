import Foundation
import Testing
@testable import FormulaEngine

@Suite("Lexer Tests")
struct LexerTests {
    @Test("基础MACD公式分词")
    func testMACDFormula() throws {
        let source = "DIF:EMA(CLOSE,12)-EMA(CLOSE,26);"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        // DIF : EMA ( CLOSE , 12 ) - EMA ( CLOSE , 26 ) ; EOF
        // 0    1  2   3   4    5  6  7  8  9  10  11 12 13 14 15
        #expect(tokens[0].type == .identifier("DIF"))
        #expect(tokens[1].type == .output)
        #expect(tokens[2].type == .identifier("EMA"))
        #expect(tokens[3].type == .leftParen)
        #expect(tokens[4].type == .identifier("CLOSE"))
        #expect(tokens[5].type == .comma)
        #expect(tokens[6].type == .number(12))
        #expect(tokens[7].type == .rightParen)
        #expect(tokens[8].type == .minus)
        #expect(tokens[15].type == .semicolon)
    }

    @Test("赋值运算符 :=")
    func testAssignment() throws {
        let source = "MA5:=MA(CLOSE,5);"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        #expect(tokens[0].type == .identifier("MA5"))
        #expect(tokens[1].type == .assign)
    }

    @Test("比较运算符")
    func testComparisons() throws {
        let source = "A>B AND C<=D AND E<>F;"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        #expect(tokens[1].type == .greaterThan)
        #expect(tokens[3].type == .and)
        #expect(tokens[5].type == .lessEqual)
        #expect(tokens[9].type == .notEqual)
    }

    @Test("注释跳过")
    func testComments() throws {
        let source = "{这是注释}MA5:MA(CLOSE,5);"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        #expect(tokens[0].type == .identifier("MA5"))
    }

    @Test("绘图属性识别")
    func testDrawAttributes() throws {
        let source = "MACD:2*(DIF-DEA),COLORSTICK;"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        let lastMeaningful = tokens[tokens.count - 3] // COLORSTICK before ; and EOF
        #expect(lastMeaningful.type == .drawAttribute("COLORSTICK"))
    }

    @Test("小数解析")
    func testDecimalNumber() throws {
        let source = "A:3.14;"
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()

        #expect(tokens[2].type == .number(Decimal(string: "3.14")!))
    }

    @Test("错误: 未闭合字符串")
    func testUnclosedString() throws {
        let source = "A:'hello;"
        var lexer = Lexer(source: source)
        #expect(throws: LexerError.self) {
            _ = try lexer.tokenize()
        }
    }
}
