import Foundation
import Testing
@testable import IndicatorCore

@Suite("高级函数测试")
struct AdvancedFunctionTests {
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
        return try Interpreter().execute(formula: formula, bars: testBars)
    }

    @Test("STD标准差")
    func testSTD() throws {
        let results = try run("R:STD(CLOSE,3);")
        #expect(results[0].values[2] != nil) // 第3根开始有值
        #expect(results[0].values[0] == nil) // 前2根无值
    }

    @Test("SLOPE线性回归斜率")
    func testSLOPE() throws {
        let results = try run("R:SLOPE(CLOSE,3);")
        #expect(results[0].values[2] != nil)
        // 11,12,13 斜率应为1
        #expect(results[0].values[2] == 1)
    }

    @Test("FILTER信号过滤")
    func testFILTER() throws {
        // CLOSE>12 在 bar 2,3,4,5 为真
        // FILTER(CLOSE>12, 2) 应该：bar2=1, bar3跳过, bar4跳过, bar5=1
        let results = try run("R:FILTER(CLOSE>12,2);")
        let vals = results[0].values
        #expect(vals[2] == 1)
        #expect(vals[3] == 0) // 冷却中
        #expect(vals[4] == 0) // 冷却中
        #expect(vals[5] == 1) // 冷却结束
    }

    @Test("ROUND四舍五入")
    func testROUND() throws {
        let results = try run("R:ROUND(CLOSE/3);")
        let vals = results[0].values
        // CLOSE[0]=11, 11/3≈3.67 → 4
        #expect(vals[0] == 4)
    }

    @Test("SIGN符号函数")
    func testSIGN() throws {
        let results = try run("R:SIGN(CLOSE-13);")
        let vals = results[0].values
        // CLOSE[0]=11, 11-13=-2 → -1
        #expect(vals[0] == -1)
        // CLOSE[2]=13, 13-13=0 → 0
        #expect(vals[2] == 0)
        // CLOSE[4]=15, 15-13=2 → 1
        #expect(vals[4] == 1)
    }

    @Test("CONST取常量")
    func testCONST() throws {
        let results = try run("R:CONST(CLOSE);")
        let vals = results[0].values
        // 最后一个CLOSE=10，所有值应为10
        for v in vals { #expect(v == 10) }
    }

    @Test("BARSCOUNT有效数据数")
    func testBARSCOUNT() throws {
        let results = try run("R:BARSCOUNT(CLOSE);")
        let vals = results[0].values
        #expect(vals[0] == 1)
        #expect(vals[9] == 10)
    }

    @Test("WMA加权移动平均")
    func testWMA() throws {
        let results = try run("R:WMA(CLOSE,3);")
        let vals = results[0].values
        #expect(vals[0] == nil)
        #expect(vals[1] == nil)
        // WMA[2] = (11*1 + 12*2 + 13*3) / (1+2+3) = (11+24+39)/6 = 74/6 ≈ 12.333
        #expect(vals[2] != nil)
    }

    @Test("AVEDEV平均绝对偏差")
    func testAVEDEV() throws {
        let results = try run("R:AVEDEV(CLOSE,3);")
        // CLOSE[0..2] = 11,12,13, avg=12, AVEDEV = (1+0+1)/3 ≈ 0.667
        #expect(results[0].values[2] != nil)
    }

    @Test("KDJ完整公式")
    func testKDJFormula() throws {
        let source = """
        RSV:=(CLOSE-LLV(LOW,9))/(HHV(HIGH,9)-LLV(LOW,9))*100;
        K:SMA(RSV,3,1);
        D:SMA(K,3,1);
        J:3*K-2*D;
        """
        let results = try run(source)
        #expect(results.count == 3) // K, D, J
        #expect(results[0].name == "K")
        #expect(results[1].name == "D")
        #expect(results[2].name == "J")
        // 所有值应存在
        #expect(results[0].values[0] != nil)
    }

    @Test("布林带完整公式")
    func testBOLLFormula() throws {
        let source = """
        MID:MA(CLOSE,5);
        UPPER:MID+2*STD(CLOSE,5);
        LOWER:MID-2*STD(CLOSE,5);
        """
        let results = try run(source)
        #expect(results.count == 3)
        #expect(results[0].name == "MID")
        #expect(results[1].name == "UPPER")
        #expect(results[2].name == "LOWER")
        // 第5根开始有值
        #expect(results[0].values[4] != nil)
        // UPPER > MID > LOWER
        if let u = results[1].values[4], let m = results[0].values[4], let l = results[2].values[4] {
            #expect(u > m)
            #expect(m > l)
        }
    }

    @Test("函数总数>=45")
    func testFunctionCount() throws {
        let count = BuiltinFunctions.all.count
        #expect(count >= 45)
    }
}
