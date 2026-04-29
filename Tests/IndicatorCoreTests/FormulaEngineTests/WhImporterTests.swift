// WP-63 · WhImporter 单元测试
// 覆盖：切分（无/单/多/空块）+ 标头变体（描述/管道）+ 注释忽略 + 编译（成功/部分失败/行号偏移）

import Testing
import Foundation
@testable import IndicatorCore

@Suite("WhImporter · 切分 + 编译 + 错误定位")
struct WhImporterTests {

    // MARK: - 切分

    @Test("无标头 · 整文件视作单公式 untitled-1")
    func untitledSingleFormula() {
        let text = "MA5:MA(CLOSE,5);"
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 1)
        #expect(formulas[0].name == "untitled-1")
        #expect(formulas[0].description == nil)
        #expect(formulas[0].source == "MA5:MA(CLOSE,5);")
        #expect(formulas[0].lineOffset == 1)
    }

    @Test("单标头 · 公式名取自 {NAME}")
    func singleHeaderName() {
        let text = """
        {KDJ}
        K:SMA(CLOSE,9,3);
        """
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 1)
        #expect(formulas[0].name == "KDJ")
        #expect(formulas[0].description == nil)
        #expect(formulas[0].lineOffset == 2)
    }

    @Test("{NAME|描述} · 名和描述用管道分隔")
    func nameAndDescription() {
        let text = """
        {MACD|经典 MACD 指标}
        DIFF:EMA(CLOSE,12)-EMA(CLOSE,26);
        """
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas[0].name == "MACD")
        #expect(formulas[0].description == "经典 MACD 指标")
    }

    @Test("多公式分隔 · 顺序保留 · 各自 lineOffset 正确")
    func multipleFormulas() {
        let text = """
        {KDJ}
        K:SMA(CLOSE,9,3);

        {MACD|经典 MACD}
        DIFF:EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:EMA(DIFF,9);
        """
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 2)
        #expect(formulas.map(\.name) == ["KDJ", "MACD"])
        #expect(formulas[0].lineOffset == 2)  // KDJ source 起始
        #expect(formulas[1].lineOffset == 5)  // MACD source 起始
    }

    @Test("# 开头注释忽略 · 不进入 source")
    func commentLinesIgnored() {
        let text = """
        # 文件级注释
        {MA5}
        # 公式内 importer 注释
        MA5:MA(CLOSE,5);
        """
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 1)
        #expect(formulas[0].name == "MA5")
        #expect(formulas[0].source == "MA5:MA(CLOSE,5);")
        #expect(!formulas[0].source.contains("#"))
    }

    @Test("空标头块（标头后无源码）· 跳过 · 不入结果")
    func emptyBlockSkipped() {
        let text = """
        {EMPTY}

        {MA5}
        MA5:MA(CLOSE,5);
        """
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 1)
        #expect(formulas[0].name == "MA5")
    }

    @Test("标头前导空白允许 · trim 后识别为标头")
    func headerWithLeadingSpaces() {
        let text = "   {ABC}\nABC:CLOSE;"
        let formulas = WhImporter.parseFormulas(text)
        #expect(formulas.count == 1)
        #expect(formulas[0].name == "ABC")
    }

    // MARK: - 编译（importAll）

    @Test("importAll · 5 个文华典型公式全部编译成功")
    func importAllSuccess() {
        // 基于 v6.0+ MaiYuYanFormulaDemo 验证过的公式（精简到 5 个 · 覆盖均线/震荡/布林/统计/逻辑）
        let text = """
        {MA5}
        MA5:MA(CLOSE,5);

        {KDJ|经典 KDJ}
        RSV:=(CLOSE-LLV(LOW,9))/(HHV(HIGH,9)-LLV(LOW,9))*100;
        K:SMA(RSV,3,1);
        D:SMA(K,3,1);
        J:3*K-2*D;

        {MACD}
        DIFF:EMA(CLOSE,12)-EMA(CLOSE,26);
        DEA:EMA(DIFF,9);
        BAR:(DIFF-DEA)*2;

        {BOLL}
        MID:MA(CLOSE,20);
        STD:STD(CLOSE,20);
        UPPER:MID+2*STD;
        LOWER:MID-2*STD;

        {CROSS_DEMO}
        SIG:CROSS(MA(CLOSE,5),MA(CLOSE,20));
        """
        let results = WhImporter.importAll(text)
        #expect(results.count == 5)
        let successCount = results.filter { $0.isSuccess }.count
        #expect(successCount == 5, "所有公式应编译成功")
        #expect(results.map(\.formula.name) == ["MA5", "KDJ", "MACD", "BOLL", "CROSS_DEMO"])
    }

    @Test("importAll · 部分公式 lexer 失败 · 其他公式不受影响")
    func partialFailureIsolated() {
        let text = """
        {GOOD}
        OK:MA(CLOSE,5);

        {BAD}
        BAD:@@@;
        """
        let results = WhImporter.importAll(text)
        #expect(results.count == 2)
        #expect(results[0].isSuccess)
        #expect(results[1].error != nil)
        #expect(results[1].formula.name == "BAD")
    }

    @Test("失败错误的 line 是整文件相对行号 · 加 lineOffset 偏移")
    func errorLineOffsetIsAbsolute() {
        let text = """
        {GOOD}
        OK:MA(CLOSE,5);

        {BAD}
        BAD:@@@;
        """
        // 整文件第 5 行 = `BAD:@@@;`（GOOD 标头 1 + GOOD 源 2 + 空 3 + BAD 标头 4 + BAD 源 5）
        let results = WhImporter.importAll(text)
        guard let err = results[1].error else {
            #expect(Bool(false), "BAD 应失败")
            return
        }
        switch err {
        case .lexerFailed(_, let line, _, _), .parserFailed(_, let line, _, _):
            #expect(line == 5)
        }
    }

    @Test("失败错误的 formulaName 与 WhFormula 一致")
    func errorCarriesFormulaName() {
        let text = """
        {KDJ_BAD}
        K:@@;
        """
        let results = WhImporter.importAll(text)
        guard let err = results[0].error else {
            #expect(Bool(false), "应失败")
            return
        }
        switch err {
        case .lexerFailed(let name, _, _, _), .parserFailed(let name, _, _, _):
            #expect(name == "KDJ_BAD")
        }
    }

    @Test("空文件 · 0 公式")
    func emptyFile() {
        #expect(WhImporter.parseFormulas("").isEmpty)
        #expect(WhImporter.importAll("").isEmpty)
    }

    @Test("仅注释文件 · 0 公式")
    func commentsOnly() {
        let text = """
        # 这是
        # 一组
        # 注释
        """
        #expect(WhImporter.parseFormulas(text).isEmpty)
    }

    // MARK: - WP-63 DoD · 20 个文华典型公式

    @Test("WP-63 DoD · 20 个文华典型公式 .wh 批量导入全部编译成功")
    func wp63DoD_TwentyClassicFormulas() {
        let results = WhImporter.importAll(Self.wenhuaTop20Formulas)
        #expect(results.count == 20)
        // 失败诊断（仅当 successCount != 20 时打印 · 便于回归定位）
        for r in results where !r.isSuccess {
            if let err = r.error {
                Issue.record("公式 \(r.formula.name) 编译失败：\(err)")
            }
        }
        let successCount = results.filter { $0.isSuccess }.count
        #expect(successCount == 20, "20 个文华典型公式应全部编译成功")
    }

    /// 文华典型 20 公式（扩展自 v6.0+ MaiYuYanFormulaDemo 8 公式 + 12 经典指标）
    /// 仅验 Lexer + Parser 编译过 · 不跑 Interpreter（DoD 关心解析层兼容）
    private static let wenhuaTop20Formulas: String = """
    # WP-63 DoD · 20 个文华典型公式
    # 1-8 来自 v6.0+ MaiYuYanFormulaDemo（已 18th demo 验证）
    # 9-20 经典指标公式（KDJ/MACD/RSI/CCI/WR/ROC/BIAS/PSY/ATR/OBV/DMA/SLOPE）

    {金叉死叉}
    GOLD:CROSS(MA(CLOSE,5),MA(CLOSE,20));
    DEAD:CROSSDOWN(MA(CLOSE,5),MA(CLOSE,20));

    {布林通道外|MA20 ± 2σ 范围外}
    M:MA(CLOSE,20);
    S:STD(CLOSE,20);
    OUT:NOT(RANGE(CLOSE,M-2*S,M+2*S));

    {信号回设 3 根}
    SIG:CROSS(MA(CLOSE,5),MA(CLOSE,20));
    BS:BACKSET(SIG,3);

    {波峰跟踪}
    PB:PEAKBARS(CLOSE);
    LP:LASTPEAK(CLOSE);

    {波谷距离}
    TB:TROUGHBARS(CLOSE);

    {方差 vs STD²}
    V:VARIANCE(CLOSE,20);
    S:STD(CLOSE,20);
    DIFF:V-S*S;

    {中位数偏移}
    MED:MEDIAN(CLOSE,21);
    SPREAD:CLOSE-MED;

    {MOD 取模}
    P:MOD(CLOSE,5);

    {KDJ|经典 9-3-3 KDJ}
    RSV:=(CLOSE-LLV(LOW,9))/(HHV(HIGH,9)-LLV(LOW,9))*100;
    K:SMA(RSV,3,1);
    D:SMA(K,3,1);
    J:3*K-2*D;

    {MACD|经典 12-26-9 MACD}
    DIFF:EMA(CLOSE,12)-EMA(CLOSE,26);
    DEA:EMA(DIFF,9);
    BAR:(DIFF-DEA)*2;

    {RSI|14 期相对强弱指数}
    LC:=REF(CLOSE,1);
    RSI:SMA(MAX(CLOSE-LC,0),14,1)/SMA(ABS(CLOSE-LC),14,1)*100;

    {CCI|14 期顺势指标}
    TYP:=(HIGH+LOW+CLOSE)/3;
    CCI:(TYP-MA(TYP,14))/(0.015*AVEDEV(TYP,14));

    {WR|14 期威廉指标}
    WR:100*(HHV(HIGH,14)-CLOSE)/(HHV(HIGH,14)-LLV(LOW,14));

    {ROC|12 期变动率}
    ROC:100*(CLOSE-REF(CLOSE,12))/REF(CLOSE,12);

    {BIAS|6 期乖离率}
    BIAS:(CLOSE-MA(CLOSE,6))/MA(CLOSE,6)*100;

    {PSY|12 期心理线}
    PSY:COUNT(CLOSE>REF(CLOSE,1),12)/12*100;

    {ATR|14 期真实波幅}
    TR:=MAX(MAX(HIGH-LOW,ABS(HIGH-REF(CLOSE,1))),ABS(LOW-REF(CLOSE,1)));
    ATR:MA(TR,14);

    {OBV|能量潮}
    VA:=IF(CLOSE>REF(CLOSE,1),VOL,IF(CLOSE<REF(CLOSE,1),-VOL,0));
    OBV:SUM(VA,0);

    {DMA|动态平均}
    AMA:DMA(CLOSE,0.1);

    {SLOPE|10 期线性回归斜率}
    SLP:SLOPE(CLOSE,10);
    """
}
