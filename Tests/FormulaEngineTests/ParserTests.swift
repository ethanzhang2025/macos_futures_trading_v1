import Testing
@testable import FormulaEngine

@Suite("Parser Tests")
struct ParserTests {
    private func parse(_ source: String) throws -> Formula {
        var lexer = Lexer(source: source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try parser.parse()
    }

    @Test("简单赋值")
    func testSimpleAssignment() throws {
        let formula = try parse("MA5:=MA(CLOSE,5);")
        #expect(formula.statements.count == 1)
        guard case .assignment(let name, let isOutput, _, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        #expect(name == "MA5")
        #expect(isOutput == false)
    }

    @Test("输出变量")
    func testOutputVariable() throws {
        let formula = try parse("DIF:EMA(CLOSE,12)-EMA(CLOSE,26);")
        guard case .assignment(let name, let isOutput, _, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        #expect(name == "DIF")
        #expect(isOutput == true)
    }

    @Test("带绘图属性")
    func testDrawAttributes() throws {
        let formula = try parse("MACD:2*(DIF-DEA),COLORSTICK;")
        guard case .assignment(_, _, _, let attrs) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        #expect(attrs == ["COLORSTICK"])
    }

    @Test("多语句MACD公式")
    func testMACDFormula() throws {
        let source = """
        DIF:EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:EMA(DIF,9);
        MACD:2*(DIF-DEA),COLORSTICK;
        """
        let formula = try parse(source)
        #expect(formula.statements.count == 3)
    }

    @Test("运算符优先级")
    func testOperatorPrecedence() throws {
        let formula = try parse("A:1+2*3;")
        guard case .assignment(_, _, let expr, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        // 应该是 1 + (2 * 3)，不是 (1 + 2) * 3
        guard case .binaryOp(let op, _, _) = expr else {
            Issue.record("期望二元运算")
            return
        }
        #expect(op == .add)
    }

    @Test("括号覆盖优先级")
    func testParentheses() throws {
        let formula = try parse("A:(1+2)*3;")
        guard case .assignment(_, _, let expr, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        guard case .binaryOp(let op, _, _) = expr else {
            Issue.record("期望二元运算")
            return
        }
        #expect(op == .multiply)
    }

    @Test("逻辑表达式")
    func testLogicExpression() throws {
        let formula = try parse("A:CLOSE>OPEN AND VOL>REF(VOL,1);")
        guard case .assignment(_, _, let expr, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        guard case .binaryOp(let op, _, _) = expr else {
            Issue.record("期望二元运算")
            return
        }
        #expect(op == .and)
    }

    @Test("负数")
    func testNegativeNumber() throws {
        let formula = try parse("A:-CLOSE;")
        guard case .assignment(_, _, let expr, _) = formula.statements[0] else {
            Issue.record("期望赋值语句")
            return
        }
        guard case .unaryOp(let op, _) = expr else {
            Issue.record("期望一元运算")
            return
        }
        #expect(op == .negate)
    }
}
