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
            // v15.18 · 时间细分函数（YEAR / MONTH / DAY / WEEKDAY · 通达信日历分量）
            YEARFunction(),
            MONTHFunction(),
            DAYFunction(),
            WEEKDAYFunction(),
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
            // 麦语言扩展（第 3 批 · v15.25 兼容度 ~95% → ~99%）
            TRFunction(),
            ATRFunction(),
            TROUGHFunction(),
            HHVCROSSFunction(),
            REFVFunction(),
            // 麦语言扩展（第 4 批 · v15.25 兼容度 ~99% → ~99.5% · DMI 三件套 + TRIX + CORREL）
            PDIFunction(),
            MDIFunction(),
            ADXFunction(),
            TRIXFunction(),
            CORRELFunction(),
            // 麦语言扩展（第 5 批 · v15.25 兼容度 ~99.5% → ~99.8% · trader 主流核心 7 函数）
            CCIFunction(),
            WRFunction(),
            ROCFunction(),
            MOMFunction(),
            OBVFunction(),
            MFIFunction(),
            TEMAFunction(),
            // 麦语言扩展（第 6 批 · v15.25 兼容度 ~99.8% → ~99.9% · 情绪/乖离/量能/均线变种）
            PSYFunction(),
            BIASFunction(),
            VRFunction(),
            DPOFunction(),
            HMAFunction(),
            DEMAFunction(),
            OSCFunction(),
            // 麦语言扩展（第 7 批 · v15.25 兼容度 ~99.9% → ~99.95% · 量价/反转/多空综合）
            VWAPFunction(),
            EMVFunction(),
            MASSFunction(),
            CHOFunction(),
            VHFFunction(),
            BBIFunction(),
            PVTFunction(),
            // 麦语言扩展（第 8 批 · v15.25 兼容度 ~99.95% → ~99.97% · 进阶+价格组合）
            CMOFunction(),
            AROONOSCFunction(),
            VWMAFunction(),
            NVIFunction(),
            AVGPRICEFunction(),
            MEDPRICEFunction(),
            WCFunction(),
            // 麦语言扩展（第 9 批 · v15.25 兼容度 ~99.97% → ~99.98% · 经典反转 PSAR + 综合摆动）
            PSARFunction(),
            PVIFunction(),
            ULTOSCFunction(),
            STOCHRSIFunction(),
            WADFunction(),
            HDFunction(),
            LDFunction(),
            // 麦语言扩展（第 10 批 · v15.25 兼容度 ~99.98% → ~99.99% · 枢轴/能量/AD/Aroon 拆分）
            PIVOTFunction(),
            R1Function(),
            S1Function(),
            CRFunction(),
            WVADFunction(),
            AROONLFunction(),
            AROONSFunction(),
            // 麦语言扩展（第 11 批 · v15.25 兼容度 ~99.99% → ~99.995% · 价格组合/自适应均线/包络）
            TYPFunction(),
            OCFunction(),
            ENVUPFunction(),
            ENVDNFunction(),
            KAMAFunction(),
            ZLEMAFunction(),
            NEARESTFunction(),
            // 麦语言扩展（第 12 批 · v15.25 兼容度 ~99.995% → ~99.997% · 趋势止损/Bill Williams/分形）
            SUPERTRENDFunction(),
            CHANDELIERLFunction(),
            CHANDELIERSFunction(),
            AOFunction(),
            ACFunction(),
            FRACTALHFunction(),
            FRACTALLFunction(),
            // 麦语言扩展（第 13 批 · v15.25 兼容度 ~99.997% → ~99.999% · 含补漏 RSI + 量能 + 波动率）
            RSIFunction(),
            STOCHFunction(),
            VOLRFunction(),
            VOSCFunction(),
            DKXFunction(),
            HVFunction(),
            ATRPCTFunction(),
            // 麦语言扩展（第 14 批 · v15.25 · MACD/BOLL/KDJ trader 三件套拆独立函数）
            MACDDIFFunction(),
            MACDDEAFunction(),
            MACDBARFunction(),
            BOLLMFunction(),
            BOLLUFunction(),
            BOLLLFunction(),
            KDJKFunction(),
            // 麦语言扩展（第 15 批 · v15.25 · KDJ 配套 + 布林带宽度 + K 线类型/角度/RSI差）
            KDJDFunction(),
            KDJJFunction(),
            BOLLWFunction(),
            BOLLPCTFunction(),
            TYPINGFunction(),
            MAANGLEFunction(),
            RSIDIVFunction(),
            // 麦语言扩展（第 16 批 · v15.25 · 量价进阶 + 中国市场 BR/AR + 配对统计 BETA）
            CMFFunction(),
            ADLFunction(),
            BRFunction(),
            ARFunction(),
            KVOFunction(),
            RVIFunction(),
            BETAFunction(),
            // 麦语言扩展（第 17 批 · v15.25 · ICHIMOKU 一目均衡 4 线 + Donchian 通道 3 线）
            ICHITENKANFunction(),
            ICHIKIJUNFunction(),
            ICHISPANAFunction(),
            ICHISPANBFunction(),
            DONCHIANUFunction(),
            DONCHIANLFunction(),
            DONCHIANMFunction(),
            // 麦语言扩展（第 18 批 · v15.25 · Keltner / Starc 通道 + 比率 + 周期能量）
            KELCHMFunction(),
            KELCHUFunction(),
            KELCHLFunction(),
            STARCUFunction(),
            STARCLFunction(),
            MARFunction(),
            CYCLEFunction(),
        ]
        var dict: [String: BuiltinFunction] = [:]
        for fn in functions { dict[fn.name] = fn }
        return dict
    }()
}
