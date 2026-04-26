import Foundation

/// 内置函数协议
public protocol BuiltinFunction: Sendable {
    /// 函数名
    var name: String { get }
    /// 执行函数，args为参数序列，bars为K线数据
    func execute(args: [[Decimal?]], bars: [BarData]) throws -> [Decimal?]
}

/// 内置函数注册表
public enum BuiltinFunctions {
    public static let all: [String: BuiltinFunction] = {
        let functions: [BuiltinFunction] = [
            // 均线
            MAFunction(),
            EMAFunction(),
            SMAFunction(),
            // 引用
            REFFunction(),
            // 统计
            HHVFunction(),
            LLVFunction(),
            COUNTFunction(),
            SUMFunction(),
            // 逻辑
            IFFunction(),
            CROSSFunction(),
            EVERYFunction(),
            EXISTFunction(),
            // 数学
            ABSFunction(),
            MAXFunction(),
            MINFunction(),
            POWFunction(),
            SQRTFunction(),
            LOGFunction(),
            EXPFunction(),
            CEILINGFunction(),
            FLOORFunction(),
            INTPARTFunction(),
            STDFunction(),
            AVEDEVFunction(),
            // 引用
            BARSLASTFunction(),
            HHVBARSFunction(),
            LLVBARSFunction(),
            // 逻辑扩展
            LONGCROSSFunction(),
            BETWEENFunction(),
            VALUEWHENFunction(),
            IFFFunction(),
            // 均线扩展
            DMAFunction(),
            WMAFunction(),
            // 高级函数
            SLOPEFunction(),
            FORCASTFunction(),
            FILTERFunction(),
            BARSSINCEFunction(),
            BARSCOUNTFunction(),
            CONSTFunction(),
            LASTFunction(),
            DEVSQFunction(),
            ROUNDFunction(),
            SIGNFunction(),
            SUMBARSFunction(),
            MULARFunction(),
            // 时间/位置函数
            DATEFunction(),
            TIMEFunction(),
            HOURFunction(),
            MINUTEFunction(),
            ISLASTBARFunction(),
            BARPOSFunction(),
            // 麦语言扩展（第 1 批 · v6.0+ 兼容度 85% → ~90%）
            NOTFunction(),
            CROSSDOWNFunction(),
            MODFunction(),
            PEAKBARSFunction(),
            TROUGHBARSFunction(),
            // 麦语言扩展（第 2 批 · v6.0+ 兼容度 ~90% → ~95%）
            BACKSETFunction(),
            VARIANCEFunction(),
            RANGEFunction(),
            MEDIANFunction(),
            LASTPEAKFunction(),
        ]
        var dict: [String: BuiltinFunction] = [:]
        for fn in functions { dict[fn.name] = fn }
        return dict
    }()
}
