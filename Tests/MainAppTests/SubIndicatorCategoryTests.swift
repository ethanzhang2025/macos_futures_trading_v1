// v17.158 · SubIndicatorKind.category 分组映射单测
//
// 防回归：加新 SubIndicatorKind case 必须同步加 category 映射 · 否则编译错（switch exhaustive）
// 防分类漂移：与 IndicatorCore canonical category 对齐（MACD/DMI/TRIX/CMO 都属 oscillator · 非 trend）
//
// Linux 端 SubChartView SwiftUI 整文件 #if guard · 整 file 守 macOS-only · target 空跑

#if canImport(SwiftUI) && os(macOS)

import Testing
import Foundation
import IndicatorCore
@testable import MainApp

@Suite("v17.158 · SubIndicatorKind.category 分组映射")
struct SubIndicatorCategoryTests {

    @Test("所有 28 个副图都有有效分类（switch 穷举守护）· 加新 case 必须显式映射")
    func allCasesHaveValidCategory() {
        for kind in SubIndicatorKind.allCases {
            let cat = kind.category
            #expect(IndicatorCategory.allCases.contains(cat), "\(kind) 分类 \(cat) 不在 6 大类内")
        }
    }

    @Test("oscillator 类 13 项：MACD/KDJ/RSI/CCI/WR/DMI/Stoch/ROC/BIAS/ElderRay/CHOP/TRIX/CMO")
    func oscillatorCategory() {
        let expected: Set<SubIndicatorKind> = [
            .macd, .kdj, .rsi, .cci, .wr, .dmi, .stoch, .roc, .bias,
            .elderRay, .choppiness, .trix, .cmo
        ]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .oscillator })
        #expect(actual == expected, "oscillator 集合不符 actual=\(actual) expected=\(expected)")
    }

    @Test("volume 类 8 项：Volume/OBV/ForceIndex/CMF/PVT/VR/ADL/MFI")
    func volumeCategory() {
        let expected: Set<SubIndicatorKind> = [.volume, .obv, .forceIndex, .cmf, .pvt, .vr, .adl, .mfi]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .volume })
        #expect(actual == expected)
    }

    @Test("trend 类 3 项：Aroon/STC/ADX")
    func trendCategory() {
        let expected: Set<SubIndicatorKind> = [.aroon, .stc, .adx]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .trend })
        #expect(actual == expected)
    }

    @Test("volatility 类 2 项：BBW/ATRP")
    func volatilityCategory() {
        let expected: Set<SubIndicatorKind> = [.bbw, .atrp]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .volatility })
        #expect(actual == expected)
    }

    @Test("structure 类 1 项：VolumeProfile")
    func structureCategory() {
        let expected: Set<SubIndicatorKind> = [.volumeProfile]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .structure })
        #expect(actual == expected)
    }

    @Test("futures 类 1 项：OI")
    func futuresCategory() {
        let expected: Set<SubIndicatorKind> = [.oi]
        let actual = Set(SubIndicatorKind.allCases.filter { $0.category == .futures })
        #expect(actual == expected)
    }

    @Test("6 大类标签全有中文 label")
    func categoryLabels() {
        for cat in IndicatorCategory.allCases {
            let label = SubIndicatorPickerCategoryLabel.title(cat)
            #expect(!label.isEmpty)
        }
    }
}

#endif
