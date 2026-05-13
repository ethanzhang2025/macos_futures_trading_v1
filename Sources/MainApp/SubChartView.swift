// MainApp · 副图区（MACD / KDJ / RSI / 成交量 / OBV / CCI / WR / 持仓量 · 枚举驱动 · SwiftUI Canvas）
//
// 共用：drawLine（yMap 闭包参数）+ drawDashLine（零轴 / 参考线）+ drawAutoLine（上下对称自适应单线）
// 分发：y 范围（MACD/OBV/CCI 上下对称自适应 · KDJ/RSI/WR 固定视野 · Volume/OI 底基线）· 直方图（MACD/Volume/OI）· 配色 · HUD 文字
//
// viewport 共享：父视图传 viewport · 父变即重渲染（SwiftUI 标准）
// 性能取舍：[Double?] 缓存（compute() 一次性 Decimal → Double 桥接）· 拖拽 60Hz drawChart 不再走 NSDecimalNumber bridge
// 扩展：加新副图 = SubIndicatorKind 加 case + compute()/draw 加分支即可

#if canImport(SwiftUI) && os(macOS)

import SwiftUI
import Shared
import ChartCore
import IndicatorCore

// MARK: - 副图类型枚举（外部用）

enum SubIndicatorKind: String, CaseIterable, Identifiable, Sendable {
    case macd
    case kdj
    case rsi
    case volume
    case obv     // v15.11 WP-41 v4 · 累积量价（无参数 · 单线 · 视野自动）
    case cci     // v15.11 WP-41 v4 · 顺势指标（默认 14 · 单线 · ±100 参考线）
    case wr      // v15.11 WP-41 v4 · 威廉指标（默认 14 · 单线 · 固定 -100~0 视野 · -20/-80 参考）
    case oi      // v15.11 WP-41 v4 · 持仓量（期货特有 · 直读 bars · 直方图 · 类似 Volume）
    case dmi     // v15.13 WP-41 v4 第二批 · 趋向指标 +DI/-DI 双线（period 默认 14 · 视野自动 · 红 +DI 绿 -DI）
    case stoch   // v15.13 · Stochastic %K/%D 双线（[14,3] · 视野固定 0~100 · 80/50/20 参考）
    case roc     // v15.13 · 变动率 % 单线（默认 12 · 上下对称视野 · 0 参考）
    case bias    // v15.13 · 乖离率 % 单线（默认 6 · 上下对称视野 · 0 参考）
    // v15.18 · 5 个新指标
    case aroon       // 趋势强度 · Up/Down 双线 · 0~100 视野 · 50 参考线
    case stc         // Schaff Trend Cycle · 单线 · 0~100 视野 · 25/75 参考线
    case elderRay    // Elder Ray Bull/Bear 双线 · 上下对称视野 · 0 参考线
    case choppiness  // 震荡度 · 单线 · 0~100 视野 · 61.8/38.2 黄金分割参考
    case forceIndex  // ForceIndex 价量复合 · 单线 · 上下对称视野 · 0 参考线
    // v15.18+ batch13 · 波动率 squeeze + 跨品种比较
    case bbw         // Bollinger Bandwidth · 单线 · 0 基线 · 视野 visible max · % 单位
    case atrp        // ATR% · 单线 · 0 基线 · 视野 visible max · % 单位
    // v15.19 batch25 · 成交量分布（trader 支撑阻力区分析）
    case volumeProfile  // 横轴 = 价格 bin · 纵轴 = 累计成交量 · visible 范围内分桶
    // v17.143 · 4 个国际派常用副图（IndicatorCore 已有算法 · v1 hardcoded 默认参数 · 后续 ParamsBook 加可调）
    case trix     // TRIX(12) 三重 EMA 趋势 · 单线 · 上下对称视野 · 0 参考线
    case cmf      // Chaikin Money Flow(20) 资金流向 · 单线 · 上下对称视野 · ±0.05 参考线
    case pvt      // Price Volume Trend 累积价量趋势 · 单线 · auto 视野（同 OBV pattern）
    case vr       // Volume Ratio(26) 成交量比 · 单线 · auto baseline + 100 参考线
    // v17.144 · 4 个再补国际派副图（22→30 · 收口）
    case adx      // ADX(14) 平均趋向指数（DMI 配套趋势强度 · 0~100 · 25/40 阈值）
    case adl      // Accumulation/Distribution Line 累积分配（与 OBV/PVT 互补 · 累积单线）
    case mfi      // Money Flow Index(14) 资金流量指数 · 0~100 · 80/50/20（含 volume 的 RSI）
    case cmo      // Chande Momentum Oscillator(14) 钱德动量 · ±100 · ±50/0（RSI 升级版）

    var id: String { rawValue }

    /// 用当前参数生成 HUD 标题（用户改参数后立即更新 · 无参版本由调用方传 .default）
    func displayName(params: IndicatorParamsBook) -> String {
        switch self {
        case .macd:   return "MACD \(params.macdParams[0])/\(params.macdParams[1])/\(params.macdParams[2])"
        case .kdj:    return "KDJ \(params.kdjParams[0])/\(params.kdjParams[1])/\(params.kdjParams[2])"
        case .rsi:    return "RSI \(params.rsiPeriod)"
        case .volume: return "成交量"
        case .obv:    return "OBV"
        case .cci:    return "CCI \(params.cciPeriod)"
        case .wr:     return "WR \(params.wrPeriod)"
        case .oi:     return "持仓量"
        case .dmi:    return "DMI \(params.dmiPeriod)"
        case .stoch:  return "STOCH \(params.stochParams[0])/\(params.stochParams[1])"
        case .roc:    return "ROC \(params.rocPeriod)"
        case .bias:   return "BIAS \(params.biasPeriod)"
        case .aroon:       return "AROON \(params.aroonPeriod)"
        case .stc:         return "STC \(params.stcParams[0])/\(params.stcParams[1])"
        case .elderRay:    return "Elder \(params.elderRayPeriod)"
        case .choppiness:  return "CHOP \(params.choppinessPeriod)"
        case .forceIndex:  return "FI \(params.forceIndexPeriod)"
        case .bbw:         return "BBW \(params.bbwParams[0])/\(params.bbwParams[1])"
        case .atrp:        return "ATRP \(params.atrpPeriod)"
        case .volumeProfile: return "成交量分布"
        // v17.143 · v17.148 接 ParamsBook 可调 period
        case .trix:   return "TRIX \(params.trixPeriod)"
        case .cmf:    return "CMF \(params.cmfPeriod)"
        case .pvt:    return "PVT"
        case .vr:     return "VR \(params.vrPeriod)"
        // v17.144 · v17.148 接 ParamsBook 可调 period
        case .adx:    return "ADX \(params.adxPeriod)"
        case .adl:    return "ADL"
        case .mfi:    return "MFI \(params.mfiPeriod)"
        case .cmo:    return "CMO \(params.cmoPeriod)"
        }
    }

    /// v17.158 · 分类（与 IndicatorCore.IndicatorCategory 同步 · trader 副图 picker 按 6 大类分组下拉）
    /// 映射来自 IndicatorCore canonical category：MACD/DMI/TRIX/CMO 等都属 oscillator · MFI/CMF/VR/PVT/ADL 都属 volume
    var category: IndicatorCategory {
        switch self {
        case .macd, .kdj, .rsi, .cci, .wr, .dmi, .stoch, .roc, .bias,
             .elderRay, .choppiness, .trix, .cmo:        return .oscillator
        case .volume, .obv, .forceIndex, .cmf, .pvt, .vr, .adl, .mfi: return .volume
        case .aroon, .stc, .adx:                          return .trend
        case .bbw, .atrp:                                 return .volatility
        case .volumeProfile:                              return .structure
        case .oi:                                         return .futures
        }
    }

    /// 短名（Picker 紧凑显示）
    var shortName: String {
        switch self {
        case .macd:   return "MACD"
        case .kdj:    return "KDJ"
        case .rsi:    return "RSI"
        case .volume: return "成交量"
        case .obv:    return "OBV"
        case .cci:    return "CCI"
        case .wr:     return "WR"
        case .oi:     return "持仓量"
        case .dmi:    return "DMI"
        case .stoch:  return "STOCH"
        case .roc:    return "ROC"
        case .bias:   return "BIAS"
        case .aroon:       return "AROON"
        case .stc:         return "STC"
        case .elderRay:    return "Elder"
        case .choppiness:  return "CHOP"
        case .forceIndex:  return "FI"
        case .bbw:         return "BBW"
        case .atrp:        return "ATRP"
        case .volumeProfile: return "VP"
        case .trix:   return "TRIX"
        case .cmf:    return "CMF"
        case .pvt:    return "PVT"
        case .vr:     return "VR"
        case .adx:    return "ADX"
        case .adl:    return "ADL"
        case .mfi:    return "MFI"
        case .cmo:    return "CMO"
        }
    }
}

// v17.158 · 副图 picker 分类中文标签（仅 UI 显示用 · 不污染 IndicatorCore.IndicatorCategory）
enum SubIndicatorPickerCategoryLabel {
    static func title(_ cat: IndicatorCategory) -> String {
        switch cat {
        case .trend:       return "趋势"
        case .oscillator:  return "震荡"
        case .volume:      return "量价"
        case .volatility:  return "波动率"
        case .structure:   return "结构"
        case .futures:     return "期货"
        }
    }
}

// MARK: - 副图视图

struct SubChartView: View {

    // MARK: 配色（基色单源 · MACD/KDJ 别名指向相同基色，让维护时不漏改）

    // v15.9 删除 static bgColor / zeroLineColor / kdjGuideColor（改 instance computed 跟随 theme · 见下方主体属性）

    static let yellowColor   = Color(red: 1.00, green: 0.78, blue: 0.18)   // 短期/快线（DIF · K）
    static let purpleColor   = Color(red: 0.63, green: 0.42, blue: 0.83)   // 中期/慢线（DEA · D）
    static let blueColor     = Color(red: 0.30, green: 0.78, blue: 1.00)   // J 专用
    static let bullColor     = Color(red: 0.96, green: 0.27, blue: 0.27)   // 涨红
    static let bearColor     = Color(red: 0.18, green: 0.74, blue: 0.42)   // 跌绿

    // MACD 别名
    static let macdDifColor  = yellowColor
    static let macdDeaColor  = purpleColor
    static let macdBullColor = bullColor
    static let macdBearColor = bearColor

    // KDJ 别名
    static let kdjKColor = yellowColor
    static let kdjDColor = purpleColor
    static let kdjJColor = blueColor

    // KDJ 视野（J 极端到 ±50 不裁断 · 仅副图内部用）
    private static let kdjViewMin: CGFloat = -20
    private static let kdjViewMax: CGFloat = 120

    // RSI 视野（0~100 固定 · 70/30 超买超卖参考线）
    private static let rsiViewMin: CGFloat = 0
    private static let rsiViewMax: CGFloat = 100
    static let rsiLineColor    = yellowColor
    // v15.9 rsiGuideColor 改 instance computed

    // 成交量配色（涨红跌绿 · 与 K 线一致）
    static let volumeBullColor = bullColor
    static let volumeBearColor = bearColor
    // v15.9 volumeAxisColor 改 instance computed

    // v15.11 WP-41 v4 单线指标配色（OBV 用蓝 · CCI/WR 复用 RSI 黄 · 持仓量用紫强调期货特有）
    static let obvLineColor = blueColor
    static let cciLineColor = yellowColor
    static let wrLineColor  = yellowColor
    static let oiBarColor   = purpleColor

    // WR 视野（-100~0 固定 · -20=超买 / -80=超卖）
    private static let wrViewMin: CGFloat = -100
    private static let wrViewMax: CGFloat = 0

    // v15.13 DMI 配色（+DI 红强 / -DI 绿弱 · 与涨跌色一致）
    static let dmiPlusColor  = bullColor
    static let dmiMinusColor = bearColor

    // Stochastic 视野（0~100 固定 · 80/50/20 参考线 · 同 KDJ 但更窄）
    private static let stochViewMin: CGFloat = 0
    private static let stochViewMax: CGFloat = 100
    static let stochKColor = yellowColor   // %K
    static let stochDColor = purpleColor   // %D

    // ROC / BIAS 单线配色（黄）
    static let rocLineColor  = yellowColor
    static let biasLineColor = yellowColor

    let bars: [KLine]
    let viewport: RenderViewport
    let kind: SubIndicatorKind
    /// v15.2 自定义指标参数 · 由父级注入 · 改后通过 ComputeKey 触发重算
    /// v15.7 父级已用 subParamsOverrides[slot] ?? globalParams · 这里就是 effective 参数
    let params: IndicatorParamsBook
    /// v15.7 副图槽位 index（0~3）· 右键菜单"本副图参数..."回调用 · 父级 sheet 编辑该 slot 的 override
    let slotIndex: Int
    /// v15.7 用户右键选"本副图参数..."回调 · 父级弹 IndicatorParamsSheet 编辑 override
    let onEditParams: () -> Void
    /// v15.9 主图主题（影响 background / 网格 / HUD · 副图语义色 yellow/purple/blue/bull/bear 不变）
    let chartTheme: ChartTheme
    /// v15.17 用户右键选"恢复全局参数"回调 · 清除 override · 父级 subParamsOverrides[slot] = nil
    /// 默认 nil（兼容老 caller · 新调用处必传）· 必须在 let 必填参数之后（Swift memberwise init 限制）
    var onClearOverride: (() -> Void)? = nil
    /// v15.17 是否当前 slot 有 override（菜单项显示禁用与否的视觉提示）
    var hasOverride: Bool = false
    /// v17.71 · 跨周期共振外部光标时间（同 group 兄弟 Pane 广播 · 副图画浅蓝竖线 · 区分本地 hover）
    var externalTime: Date? = nil
    /// v17.80 · 本地主图 hover 时间（ChartContentView 传入 · 副图画黄白虚线 · 与主图 KLineCrosshairView 本地光标风格一致）
    var localTime: Date? = nil
    /// v17.104 · 价格精度（VolumeProfile POC/VAH/VAL 等价格 HUD 用 · 父级传 effectivePriceDigits · 默认 2 兼容老 caller）
    var priceDigits: Int = 2
    /// v17.119 · 用户字号档（父级 ChartContentView 透传 · 副图 HUD 跟 ChartTheme.fontXxx(size:) 同步）
    var chartFontSize: ChartFontSize = .medium

    // MARK: - 主题响应的 instance computed 颜色（v15.9 替换原 static 单一深色）

    /// 副图背景（同主图 · 跟主题）
    var bgColor: Color { chartTheme.background }
    /// MACD 0 轴线 / KDJ 50 轴线 / 副图通用零线（统一用 gridLine 强一档）
    var zeroLineColor: Color { chartTheme.gridLine.opacity(2.5) }   // 主题 gridLine 已 0.10 · ×2.5 = 0.25
    /// KDJ 80/20 参考线 + RSI 70/30 参考线 + Volume 轴 · 用 gridLine 弱档
    var kdjGuideColor: Color { chartTheme.gridLine }
    var rsiGuideColor: Color { chartTheme.gridLine }
    var volumeAxisColor: Color { chartTheme.gridLine }

    /// 三槽位（MACD: DIF/DEA/HIST · KDJ: K/D/J）
    /// compute() 末尾一次性 Decimal → Double 桥接 · 拖拽热路径直接读 Double，不再走 NSDecimalNumber
    @State private var seriesA: [Double?] = []
    @State private var seriesB: [Double?] = []
    @State private var seriesC: [Double?] = []
    /// VolumeProfile 副图专用 bins · 其他副图为空
    @State private var profileBins: [VolumeProfile.Bin] = []
    /// v17.30 B2 · Value Area（POC + VAH + VAL · 70% 成交量带）
    @State private var profileValueArea: VolumeProfile.ValueArea?
    /// v17.63 · Volume Profile 模式（Full / Visible / Session / Fixed · TradingView 对齐）
    @AppStorage("volumeProfile.mode.v1") private var volumeProfileModeRaw: String = VolumeProfileMode.fullRange.rawValue
    private var volumeProfileMode: VolumeProfileMode {
        VolumeProfileMode(rawValue: volumeProfileModeRaw) ?? .fullRange
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            bgColor
            Canvas { ctx, size in drawChart(ctx, size: size) }
            hud
            // v17.71 · 跨周期共振外部光标（接 ChartScene shellExternalCrosshair env · 浅蓝 [2,2]）
            if let ext = externalTime {
                GeometryReader { geom in
                    if let x = externalBarX(time: ext, in: geom.size) {
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: geom.size.height))
                        }
                        .stroke(Color.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .allowsHitTesting(false)
                    }
                }
            }
            // v17.80 · 本地主图 hover 同步（黄白虚线 [4,4] · 与主图 KLineCrosshairView 本地光标风格一致）
            if let local = localTime {
                GeometryReader { geom in
                    if let x = externalBarX(time: local, in: geom.size) {
                        Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: geom.size.height))
                        }
                        .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .task(id: ComputeKey(barCount: bars.count, kind: kind, params: params, vpModeRaw: volumeProfileModeRaw)) {
            await compute()
        }
        .contextMenu {
            // v15.7 右键菜单 · 本副图独立参数（仅本槽位生效）
            Button("本副图参数（槽位 \(slotIndex + 1)）…") { onEditParams() }
            // v15.17 · 仅当本 slot 有 override 时显示"恢复全局"项 · 一键清除回到全局参数
            if hasOverride, let onClear = onClearOverride {
                Button("恢复全局参数（清除本副图 override）") { onClear() }
            }
            // v17.63 · Volume Profile 模式切换（仅 .volumeProfile 副图显示）
            if kind == .volumeProfile {
                Divider()
                Menu("VP 模式：\(volumeProfileMode.displayName)") {
                    ForEach(VolumeProfileMode.allCases, id: \.self) { m in
                        Button {
                            volumeProfileModeRaw = m.rawValue
                        } label: {
                            Label("\(volumeProfileMode == m ? "✓ " : "  ")\(m.displayName)",
                                  systemImage: volumeProfileMode == m ? "checkmark" : "")
                        }
                    }
                }
            }
        }
    }

    // MARK: - v17.71 · 外部光标 bar 定位（跨周期共振 · v17.76 改调 ChartHitTester 跨 module 统一）

    private func externalBarX(time: Date, in size: CGSize) -> CGFloat? {
        ChartHitTester.xPosition(forTime: time, in: bars, width: size.width, viewport: viewport)
    }

    /// 触发重算的复合 key（bars 增量 + 切副图 + 改参数都要重算）
    /// v17.63 · 加 vpModeRaw 让 VP 模式切换触发重算
    private struct ComputeKey: Equatable {
        let barCount: Int
        let kind: SubIndicatorKind
        let params: IndicatorParamsBook
        let vpModeRaw: String
    }

    // MARK: - 计算（按 kind 分发 · 后台 detached 跑 · 末尾一次性桥接 Decimal → Double）

    @MainActor
    private func compute() async {
        let snap = bars
        let kindCopy = kind
        let paramsCopy = params
        let result = await Task.detached(priority: .userInitiated) {
            let series = KLineSeries(
                opens: snap.map(\.open),
                highs: snap.map(\.high),
                lows: snap.map(\.low),
                closes: snap.map(\.close),
                volumes: snap.map(\.volume),
                openInterests: snap.map { _ in 0 }
            )
            switch kindCopy {
            case .macd:
                return (try? MACD.calculate(kline: series, params: paramsCopy.macdParamsDecimal)) ?? []
            case .kdj:
                return (try? KDJ.calculate(kline: series, params: paramsCopy.kdjParamsDecimal)) ?? []
            case .rsi:
                return (try? RSI.calculate(kline: series, params: paramsCopy.rsiParamsDecimal)) ?? []
            case .obv:
                return (try? OBV.calculate(kline: series, params: [])) ?? []
            case .cci:
                return (try? CCI.calculate(kline: series, params: paramsCopy.cciParamsDecimal)) ?? []
            case .wr:
                return (try? WilliamsR.calculate(kline: series, params: paramsCopy.wrParamsDecimal)) ?? []
            case .dmi:
                return (try? DMI.calculate(kline: series, params: paramsCopy.dmiParamsDecimal)) ?? []
            case .stoch:
                return (try? Stochastic.calculate(kline: series, params: paramsCopy.stochParamsDecimal)) ?? []
            case .roc:
                return (try? ROC.calculate(kline: series, params: paramsCopy.rocParamsDecimal)) ?? []
            case .bias:
                return (try? BIAS.calculate(kline: series, params: paramsCopy.biasParamsDecimal)) ?? []
            // v15.18 · 5 个新指标
            case .aroon:
                return (try? Aroon.calculate(kline: series, params: paramsCopy.aroonParamsDecimal)) ?? []
            case .stc:
                return (try? STC.calculate(kline: series, params: paramsCopy.stcParamsDecimal)) ?? []
            case .elderRay:
                return (try? ElderRay.calculate(kline: series, params: paramsCopy.elderRayParamsDecimal)) ?? []
            case .choppiness:
                return (try? Choppiness.calculate(kline: series, params: paramsCopy.choppinessParamsDecimal)) ?? []
            case .forceIndex:
                return (try? ForceIndex.calculate(kline: series, params: paramsCopy.forceIndexParamsDecimal)) ?? []
            // v15.18+ batch13 · BBW / ATRP（单线 · 复用 BOLL / ATR · 单位 %）
            case .bbw:
                return (try? BollingerBandwidth.calculate(kline: series, params: paramsCopy.bbwParamsDecimal)) ?? []
            case .atrp:
                return (try? ATRPercent.calculate(kline: series, params: paramsCopy.atrpParamsDecimal)) ?? []
            // v17.143 · 4 个国际派常用副图 · v17.148 · 接 IndicatorParamsBook（trader 可调 period · UI 弹 IndicatorParamsSheet）
            case .trix:
                return (try? TRIX.calculate(kline: series, params: paramsCopy.trixParamsDecimal)) ?? []
            case .cmf:
                return (try? CMF.calculate(kline: series, params: paramsCopy.cmfParamsDecimal)) ?? []
            case .pvt:
                return (try? PVT.calculate(kline: series, params: [])) ?? []   // PVT 无参
            case .vr:
                return (try? VR.calculate(kline: series, params: paramsCopy.vrParamsDecimal)) ?? []
            // v17.144 · 4 个补全副图（趋势强度 / 累积分配 / 资金流量 / 钱德动量）· v17.148 接 ParamsBook
            case .adx:
                // ADX 输出 [+DI, -DI, ADX] 3 列 · 仅取末列 ADX 单线（DMI 已有 +DI/-DI 副图）
                return (try? ADX.calculate(kline: series, params: paramsCopy.adxParamsDecimal)) ?? []
            case .adl:
                return (try? ADL.calculate(kline: series, params: [])) ?? []   // ADL 无参
            case .mfi:
                return (try? MFI.calculate(kline: series, params: paramsCopy.mfiParamsDecimal)) ?? []
            case .cmo:
                return (try? CMO.calculate(kline: series, params: paramsCopy.cmoParamsDecimal)) ?? []
            case .volume, .oi, .volumeProfile:
                return []  // 直读 bars · 不走 Indicator 计算
            }
        }.value

        switch kind {
        case .macd:
            seriesA = doublesOf(result, name: "DIF")
            seriesB = doublesOf(result, name: "DEA")
            seriesC = doublesOf(result, name: "MACD")
        case .kdj:
            seriesA = doublesOf(result, name: "K")
            seriesB = doublesOf(result, name: "D")
            seriesC = doublesOf(result, name: "J")
        case .rsi, .obv, .cci, .wr, .roc, .bias, .stc, .choppiness, .forceIndex, .bbw, .atrp, .trix, .cmf, .pvt, .vr, .adx, .adl, .mfi, .cmo:
            // 单线副图：取首个 series（输出名带参数 · 不依赖 name 匹配 · 直接首项）
            let firstSeries = result.first?.values ?? []
            seriesA = firstSeries.map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = []
            seriesC = []
        case .aroon:
            // Aroon 输出 [Up, Down, Osc] · UI 只用 Up + Down 双线（Osc 留给用户心算）
            seriesA = (result.indices.contains(0) ? result[0].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = (result.indices.contains(1) ? result[1].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesC = []
        case .elderRay:
            // ElderRay 输出 [Bull, Bear] · 双线 · 上下对称视野
            seriesA = (result.indices.contains(0) ? result[0].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = (result.indices.contains(1) ? result[1].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesC = []
        case .dmi:
            // DMI 输出 [+DI, -DI] · v15.13
            seriesA = (result.indices.contains(0) ? result[0].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = (result.indices.contains(1) ? result[1].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesC = []
        case .stoch:
            // Stochastic 输出 [%K, %D] · v15.13 · 同 KDJ 双线模式
            seriesA = (result.indices.contains(0) ? result[0].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesB = (result.indices.contains(1) ? result[1].values : []).map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
            seriesC = []
        case .volume:
            seriesA = bars.map { Double($0.volume) }  // 直接读 K 线 volume（Int → Double）
            seriesB = []
            seriesC = []
        case .oi:
            // 持仓量：bars.openInterest 是 Decimal → Double（KLineSeries.openInterests 是 [Int] 会丢精度 · 直读 bars 走 Decimal）
            seriesA = bars.map { NSDecimalNumber(decimal: $0.openInterest).doubleValue }
            seriesB = []
            seriesC = []
        case .volumeProfile:
            // v17.63 · 按模式切分 bars（Full/Visible/Session/Fixed · TradingView 对齐）
            // 注：visibleRange/fixedRange 模式 v1 用比例近似（visible=后半 · session=后 ¼ · fixed=后 ⅓）
            //     v2 接 viewport / Fixed Range 双锚 sheet 时再走真实 startIndex/endIndex
            let mode = volumeProfileMode
            let total = bars.count
            switch mode {
            case .fullRange:
                profileBins = VolumeProfile.compute(bars: bars, binCount: 24)
            case .visibleRange:
                let s = max(0, total / 2)
                let vr: (Int, Int) = (s, total)
                profileBins = VolumeProfile.compute(bars: bars, mode: .visibleRange, visibleRange: vr, binCount: 24)
            case .session:
                profileBins = VolumeProfile.compute(bars: bars, mode: .session, sessionBarCount: max(1, total / 4), binCount: 24)
            case .fixedRange:
                let s = max(0, total * 2 / 3)
                let fr: (Int, Int) = (s, total)
                profileBins = VolumeProfile.compute(bars: bars, mode: .fixedRange, fixedRange: fr, binCount: 24)
            }
            profileValueArea = VolumeProfile.valueArea(bins: profileBins, percent: 0.7)
            seriesA = profileBins.map { Optional($0.volume) }
            seriesB = []
            seriesC = []
        }
    }

    private func doublesOf(_ result: [IndicatorSeries], name: String) -> [Double?] {
        let raw = result.first { $0.name == name }?.values ?? []
        return raw.map { $0.map { NSDecimalNumber(decimal: $0).doubleValue } }
    }

    // MARK: - HUD（按 kind 分发文字）

    private var hud: some View {
        let visibleEnd = min(viewport.startIndex + viewport.visibleCount, bars.count) - 1
        let aLast = lastValue(seriesA, at: visibleEnd)
        let bLast = lastValue(seriesB, at: visibleEnd)
        let cLast = lastValue(seriesC, at: visibleEnd)

        // 视觉迭代第 12 项：副图 HUD 去 kind 名（工具条 segmented 已显示）· 仅数值 · 更紧凑
        return HStack(spacing: 8) {
            switch kind {
            case .macd:
                Text("DIF \(fmt(aLast))").foregroundColor(Self.macdDifColor)
                Text("DEA \(fmt(bLast))").foregroundColor(Self.macdDeaColor)
                Text("MACD \(fmt(cLast))").foregroundColor(
                    cLast.map { $0 >= 0 ? Self.macdBullColor : Self.macdBearColor } ?? .secondary
                )
            case .kdj:
                Text("K \(fmt(aLast))").foregroundColor(Self.kdjKColor)
                Text("D \(fmt(bLast))").foregroundColor(Self.kdjDColor)
                Text("J \(fmt(cLast))").foregroundColor(Self.kdjJColor)
            case .rsi:
                Text("RSI \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 70 ? Self.bullColor : ($0 <= 30 ? Self.bearColor : Self.rsiLineColor) } ?? .secondary
                )
            case .volume:
                Text("VOL \(fmtVolume(aLast))").foregroundColor(
                    visibleEnd >= 0 && visibleEnd < bars.count
                        ? (bars[visibleEnd].close >= bars[visibleEnd].open ? Self.volumeBullColor : Self.volumeBearColor)
                        : .secondary
                )
            case .obv:
                Text("OBV \(fmtVolume(aLast))").foregroundColor(Self.obvLineColor)
            case .cci:
                // CCI HUD 染色：>100 红 / <-100 绿 / 中间黄（与参考线语义对齐）
                Text("CCI \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 100 ? Self.bullColor : ($0 <= -100 ? Self.bearColor : Self.cciLineColor) } ?? .secondary
                )
            case .wr:
                // WR HUD 染色：>-20 红（超买）/ <-80 绿（超卖）· 倒置语义注意
                Text("WR \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= -20 ? Self.bullColor : ($0 <= -80 ? Self.bearColor : Self.wrLineColor) } ?? .secondary
                )
            case .oi:
                Text("OI \(fmtVolume(aLast))").foregroundColor(Self.oiBarColor)
            case .dmi:
                // DMI 双线：+DI 红 / -DI 绿（与涨跌语义一致）· 强弱比较一目了然
                Text("+DI \(fmt(aLast))").foregroundColor(Self.dmiPlusColor)
                Text("-DI \(fmt(bLast))").foregroundColor(Self.dmiMinusColor)
            case .stoch:
                // Stochastic %K/%D 双线 · 同 KDJ 配色（黄 K / 紫 D）
                Text("%K \(fmt(aLast))").foregroundColor(Self.stochKColor)
                Text("%D \(fmt(bLast))").foregroundColor(Self.stochDColor)
            case .roc:
                Text("ROC \(fmt(aLast))").foregroundColor(Self.rocLineColor)
            case .bias:
                Text("BIAS \(fmt(aLast))").foregroundColor(Self.biasLineColor)
            // v15.18 · 5 个新指标
            case .aroon:
                Text("Up \(fmt(aLast))").foregroundColor(Self.bullColor)
                Text("Down \(fmt(bLast))").foregroundColor(Self.bearColor)
            case .stc:
                // STC HUD 染色：>75 红（看涨）/ <25 绿（看跌）/ 中间黄
                Text("STC \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 75 ? Self.bullColor : ($0 <= 25 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            case .elderRay:
                Text("Bull \(fmt(aLast))").foregroundColor(Self.bullColor)
                Text("Bear \(fmt(bLast))").foregroundColor(Self.bearColor)
            case .choppiness:
                // CHOP HUD 染色：>61.8 黄（横盘）/ <38.2 蓝（趋势）
                Text("CHOP \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 61.8 ? Self.yellowColor : ($0 <= 38.2 ? Self.blueColor : .secondary) } ?? .secondary
                )
            case .forceIndex:
                // FI HUD 染色：>0 红（多头）/ <0 绿（空头）
                Text("FI \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 0 ? Self.bullColor : Self.bearColor } ?? .secondary
                )
            // BBW（squeeze 信号）/ ATRP（跨品种波动率）· 单位 %
            case .bbw, .atrp:
                Text("\(kind.shortName) \(fmt(aLast))%").foregroundColor(Self.yellowColor)
            // v17.143 · TRIX %（>0 多头 / <0 空头 · 0 阈值）
            case .trix:
                Text("TRIX \(fmt(aLast))%").foregroundColor(
                    aLast.map { $0 >= 0 ? Self.bullColor : Self.bearColor } ?? .secondary
                )
            // v17.143 · CMF（>0.05 强多 · <-0.05 强空 · 中间黄）
            case .cmf:
                Text("CMF \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 0.05 ? Self.bullColor : ($0 <= -0.05 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            // v17.143 · PVT（累积值 · 用蓝色 · 与 OBV 同模式）
            case .pvt:
                Text("PVT \(fmtVolume(aLast))").foregroundColor(Self.blueColor)
            // v17.143 · VR（>150 强 · <70 弱 · 100 中性参考）
            case .vr:
                Text("VR \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 150 ? Self.bullColor : ($0 <= 70 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            // v17.144 · ADX（>40 极强 · 25-40 强 · <25 无趋势 · 黄）
            case .adx:
                Text("ADX \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 40 ? Self.bullColor : ($0 <= 25 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            // v17.144 · ADL（累积值 · 蓝色）
            case .adl:
                Text("ADL \(fmtVolume(aLast))").foregroundColor(Self.blueColor)
            // v17.144 · MFI（>80 超买 · <20 超卖 · 中间黄 · 同 RSI 染色风格）
            case .mfi:
                Text("MFI \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 80 ? Self.bullColor : ($0 <= 20 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            // v17.144 · CMO（>50 强多 · <-50 强空 · 中间黄）
            case .cmo:
                Text("CMO \(fmt(aLast))").foregroundColor(
                    aLast.map { $0 >= 50 ? Self.bullColor : ($0 <= -50 ? Self.bearColor : Self.yellowColor) } ?? .secondary
                )
            // v15.19 batch25 · Volume Profile · HUD 显示 POC + VAH + VAL（trader 一眼看支撑阻力位 + 70% 区）
            // v17.30 B2 · 加 Value Area · POC / VAH / VAL 三价位
            case .volumeProfile:
                if let va = profileValueArea {
                    let poc = NSDecimalNumber(decimal: va.pocPrice).doubleValue
                    let vah = NSDecimalNumber(decimal: va.vahPrice).doubleValue
                    let val = NSDecimalNumber(decimal: va.valPrice).doubleValue
                    Text("POC \(String(format: "%.\(priceDigits)f", poc)) · VAH \(String(format: "%.\(priceDigits)f", vah)) · VAL \(String(format: "%.\(priceDigits)f", val))")
                        .foregroundColor(Self.purpleColor)
                } else {
                    Text("VP 加载中").foregroundColor(.secondary)
                }
            }
        }
        .font(.system(size: 11 + chartFontSize.sizeDelta, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(chartTheme.hudBackground)
        .cornerRadius(4)
        .padding(8)
    }

    // MARK: - Canvas 绘制（按 kind 分发）

    private func drawChart(_ ctx: GraphicsContext, size: CGSize) {
        let visibleStart = viewport.startIndex
        let visibleCount = viewport.visibleCount
        let visibleEnd = min(visibleStart + visibleCount, bars.count)
        guard visibleEnd > visibleStart else { return }

        let barWidth = size.width / CGFloat(visibleCount)
        let xOffset = CGFloat(viewport.startOffset)

        switch kind {
        case .macd:
            drawMACD(ctx, size: size,
                     visibleStart: visibleStart, visibleEnd: visibleEnd,
                     barWidth: barWidth, xOffset: xOffset)
        case .kdj:
            drawKDJ(ctx, size: size,
                    visibleStart: visibleStart, visibleEnd: visibleEnd,
                    barWidth: barWidth, xOffset: xOffset)
        case .rsi:
            drawRSI(ctx, size: size,
                    visibleStart: visibleStart, visibleEnd: visibleEnd,
                    barWidth: barWidth, xOffset: xOffset)
        case .volume:
            drawVolume(ctx, size: size,
                       visibleStart: visibleStart, visibleEnd: visibleEnd,
                       barWidth: barWidth, xOffset: xOffset)
        case .obv:
            drawAutoLine(seriesA, color: Self.obvLineColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        case .cci:
            drawAutoLine(seriesA, color: Self.cciLineColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [100, 0, -100],
                         minHalfSpan: 150)
        case .wr:
            drawWR(ctx, size: size,
                   visibleStart: visibleStart, visibleEnd: visibleEnd,
                   barWidth: barWidth, xOffset: xOffset)
        case .oi:
            drawOI(ctx, size: size,
                   visibleStart: visibleStart, visibleEnd: visibleEnd,
                   barWidth: barWidth, xOffset: xOffset)
        case .dmi:
            drawDMI(ctx, size: size,
                    visibleStart: visibleStart, visibleEnd: visibleEnd,
                    barWidth: barWidth, xOffset: xOffset)
        case .stoch:
            drawStoch(ctx, size: size,
                      visibleStart: visibleStart, visibleEnd: visibleEnd,
                      barWidth: barWidth, xOffset: xOffset)
        case .roc:
            drawAutoLine(seriesA, color: Self.rocLineColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        case .bias:
            drawAutoLine(seriesA, color: Self.biasLineColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        // v15.18 · 5 个新指标
        case .aroon:
            drawFixedRange(0...100, guideValues: [50],
                           seriesAList: [(seriesA, Self.bullColor), (seriesB, Self.bearColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        case .stc:
            drawFixedRange(0...100, guideValues: [75, 50, 25],
                           seriesAList: [(seriesA, Self.yellowColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        case .elderRay:
            // Bull/Bear 双线 · 上下对称视野（自动）· 0 参考
            drawAutoSymmetric([(seriesA, Self.bullColor), (seriesB, Self.bearColor)],
                              ctx: ctx, size: size,
                              visibleStart: visibleStart, visibleEnd: visibleEnd,
                              barWidth: barWidth, xOffset: xOffset)
        case .choppiness:
            drawFixedRange(0...100, guideValues: [61.8, 38.2],
                           seriesAList: [(seriesA, Self.yellowColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        case .forceIndex:
            drawAutoLine(seriesA, color: Self.yellowColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        // v15.18+ batch13 · 非负值 · 0 基线（底部）· visible max 撑满 90% 高度
        case .bbw, .atrp:
            drawAutoBaseline(seriesA, color: Self.yellowColor,
                             ctx: ctx, size: size,
                             visibleStart: visibleStart, visibleEnd: visibleEnd,
                             barWidth: barWidth, xOffset: xOffset)
        // v17.143 · TRIX % 单线 · 上下对称视野 · 0 参考（同 ROC pattern）
        case .trix:
            drawAutoLine(seriesA, color: Self.yellowColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        // v17.143 · CMF 单线 · 上下对称视野 · ±0.05 弱档 + 0 中线（资金流核心阈值）
        case .cmf:
            drawAutoLine(seriesA, color: Self.yellowColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0.05, 0, -0.05],
                         minHalfSpan: 0.15)
        // v17.143 · PVT 累积值（与 OBV 同 pattern · 视野自动 · 0 参考）
        case .pvt:
            drawAutoLine(seriesA, color: Self.blueColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        // v17.143 · VR 单线 · auto baseline + 100 中线（VR 特有 = 多头/空头 100% 平衡点）
        case .vr:
            drawAutoLine(seriesA, color: Self.yellowColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [150, 100, 70],
                         minHalfSpan: 80)
        // v17.144 · ADX 0~100 固定视野 · 25/40 趋势强度阈值（< 25 无趋势 / 25-40 强 / > 40 极强）
        case .adx:
            drawFixedRange(0...100, guideValues: [40, 25],
                           seriesAList: [(seriesA, Self.yellowColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        // v17.144 · ADL 累积单线（与 OBV/PVT 同 pattern · auto 视野 · 0 参考）
        case .adl:
            drawAutoLine(seriesA, color: Self.blueColor,
                         ctx: ctx, size: size,
                         visibleStart: visibleStart, visibleEnd: visibleEnd,
                         barWidth: barWidth, xOffset: xOffset,
                         guideValues: [0])
        // v17.144 · MFI 0~100 固定视野 · 80/50/20 三参考（同 RSI · 但更敏感因含 volume）
        case .mfi:
            drawFixedRange(0...100, guideValues: [80, 50, 20],
                           seriesAList: [(seriesA, Self.yellowColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        // v17.144 · CMO ±100 固定视野 · ±50/0 强动量阈值（>50 强多 / <-50 强空 / 0 转向参考）
        case .cmo:
            drawFixedRange(-100...100, guideValues: [50, 0, -50],
                           seriesAList: [(seriesA, Self.yellowColor)],
                           ctx: ctx, size: size,
                           visibleStart: visibleStart, visibleEnd: visibleEnd,
                           barWidth: barWidth, xOffset: xOffset)
        // v15.19 batch25 · Volume Profile · 水平柱状（y=价格 bin · x=累计成交量 · 从左生长）
        case .volumeProfile:
            drawVolumeProfile(ctx, size: size)
        }
    }

    /// v15.19 batch25 · Volume Profile · 水平柱状渲染（trader 找支撑阻力区直观）
    /// y 轴：价格（高价在上 · 低价在下）· x 轴：累计成交量从左生长 · 峰值 bin 染深紫
    /// v17.30 B2 · POC 满色 · 70% Value Area 内 bin 半透明蓝 · VA 外 bin 弱紫 + POC/VAH/VAL 三引导线
    private func drawVolumeProfile(_ ctx: GraphicsContext, size: CGSize) {
        guard !profileBins.isEmpty else { return }
        let n = profileBins.count
        let maxVol = profileBins.map(\.volume).max() ?? 1
        guard maxVol > 0 else { return }
        let binHeight = size.height / CGFloat(n)
        let xScale = size.width * 0.9 / CGFloat(maxVol)
        let va = profileValueArea
        for (i, bin) in profileBins.enumerated() {
            // 高价在顶 · 低价在底（i=0 是最低价 · 倒序映射）
            let yTop = size.height - CGFloat(i + 1) * binHeight + 1
            let barWidth = CGFloat(bin.volume) * xScale
            let rect = CGRect(x: 0, y: yTop, width: barWidth, height: binHeight - 2)
            let color: Color
            if let va {
                if i == va.pocIndex {
                    color = Self.purpleColor                         // POC 满色
                } else if i >= va.valIndex && i <= va.vahIndex {
                    color = Self.blueColor.opacity(0.55)             // 70% VA 内 · 半透明蓝
                } else {
                    color = Self.purpleColor.opacity(0.30)           // VA 外 · 弱紫
                }
            } else {
                color = Self.purpleColor.opacity(0.45)
            }
            ctx.fill(Path(rect), with: .color(color))
        }
        if let va {
            drawValueAreaGuides(ctx, size: size, va: va, binHeight: binHeight)
        }
    }

    /// v17.30 B2 · POC 实线 + VAH/VAL 虚线 · 横跨整个副图
    private func drawValueAreaGuides(
        _ ctx: GraphicsContext, size: CGSize,
        va: VolumeProfile.ValueArea, binHeight: CGFloat
    ) {
        // i 是按价格升序的 bin 下标 · 屏幕 y = size.height - (i + 0.5) * binHeight
        let yFor: (Int) -> CGFloat = { i in size.height - (CGFloat(i) + 0.5) * binHeight }
        let pocY = yFor(va.pocIndex)
        let vahY = yFor(va.vahIndex)
        let valY = yFor(va.valIndex)

        var pocPath = Path()
        pocPath.move(to: CGPoint(x: 0, y: pocY))
        pocPath.addLine(to: CGPoint(x: size.width, y: pocY))
        ctx.stroke(pocPath, with: .color(Self.purpleColor), lineWidth: 1.2)

        drawDashLine(at: vahY, ctx: ctx, width: size.width, color: Self.blueColor.opacity(0.8))
        drawDashLine(at: valY, ctx: ctx, width: size.width, color: Self.blueColor.opacity(0.8))
    }

    /// v15.18 · 固定 0~100 区间多线绘制（Aroon / STC / Choppiness 共用）
    private func drawFixedRange(
        _ range: ClosedRange<CGFloat>, guideValues: [CGFloat],
        seriesAList: [(values: [Double?], color: Color)],
        ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = range.lowerBound
        let viewMax = range.upperBound
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in guideValues {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: kdjGuideColor)
        }
        for (vals, color) in seriesAList {
            drawLine(vals, color: color, ctx: ctx, yMap: yMap,
                     visibleStart: visibleStart, visibleEnd: visibleEnd,
                     barWidth: barWidth, xOffset: xOffset)
        }
    }

    /// v15.18+ batch13 · 非负单线 0 基线绘制（BBW / ATRP 共用 · 底部 0 · 顶部 visible max · 留 10% 边距）
    private func drawAutoBaseline(
        _ values: [Double?], color: Color,
        ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        var maxV: CGFloat = 0.01
        for i in visibleStart..<visibleEnd where i < values.count {
            if let v = values[i], v > 0 { maxV = max(maxV, CGFloat(v)) }
        }
        let yScale = size.height * 0.9 / max(0.0001, maxV)
        let yBase = size.height
        let yMap: (CGFloat) -> CGFloat = { yBase - $0 * yScale }

        // 底部基线（弱档 · 视觉提示 0 锚点）
        drawDashLine(at: yBase - 1, ctx: ctx, width: size.width, color: kdjGuideColor)

        drawLine(values, color: color, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// v15.18 · 上下对称视野多线绘制（ElderRay 双线共用 · visible max(|v|) 自动撑开 · 0 参考）
    private func drawAutoSymmetric(
        _ seriesAList: [(values: [Double?], color: Color)],
        ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        var maxAbs: CGFloat = 0.01
        for (vals, _) in seriesAList {
            for i in visibleStart..<visibleEnd where i < vals.count {
                if let v = vals[i] { maxAbs = max(maxAbs, abs(CGFloat(v))) }
            }
        }
        let yScale = (size.height / 2) * 0.9 / max(0.0001, maxAbs)
        let yCenter = size.height / 2
        let yMap: (CGFloat) -> CGFloat = { yCenter - $0 * yScale }

        drawDashLine(at: yMap(0), ctx: ctx, width: size.width, color: zeroLineColor)
        for (vals, color) in seriesAList {
            drawLine(vals, color: color, ctx: ctx, yMap: yMap,
                     visibleStart: visibleStart, visibleEnd: visibleEnd,
                     barWidth: barWidth, xOffset: xOffset)
        }
    }

    /// RSI：固定 0~100 视野（70/50/30 参考线 · 超买/中位/超卖）· 单线
    private func drawRSI(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.rsiViewMin
        let viewMax = Self.rsiViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(70), 50, 30] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: rsiGuideColor)
        }

        drawLine(seriesA, color: Self.rsiLineColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// 成交量：底部基线 0 · 顶部 visible max · 涨红跌绿（按 K 线 close >= open 判涨）
    private func drawVolume(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        // y 范围：visible 内最大 volume · 顶部留 10% 边距
        var maxVolume: Double = 1.0
        for i in visibleStart..<visibleEnd where i < seriesA.count {
            if let v = seriesA[i], v > maxVolume { maxVolume = v }
        }
        let yScale = size.height * 0.9 / CGFloat(maxVolume)
        let yBase = size.height

        drawDashLine(at: yBase - 1, ctx: ctx, width: size.width, color: volumeAxisColor)

        for i in visibleStart..<visibleEnd {
            guard i < seriesA.count, let v = seriesA[i], i < bars.count else { continue }
            let value = CGFloat(v)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let height = value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: yBase - height,
                width: barWidth * 0.6,
                height: height
            )
            let isUp = bars[i].close >= bars[i].open
            ctx.fill(Path(rect),
                     with: .color(isUp ? Self.volumeBullColor : Self.volumeBearColor))
        }
    }

    /// v15.11 通用上下对称自适应单线（OBV / CCI 共用 · 0 居中 · visible 内 max(|v|) 自动撑开 · 多条水平参考线）
    /// minHalfSpan: 半视野最小值（避免 visible 数据小于参考线时参考线贴边 · 如 CCI 默认 150 让 ±100 参考线明显内收）
    private func drawAutoLine(
        _ values: [Double?], color: Color,
        ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat,
        guideValues: [CGFloat],
        minHalfSpan: CGFloat = 0
    ) {
        // y 范围：visible 内 |v| 最大 · 与 guideValues 取大 · 与 minHalfSpan 取大 · 留 10% 边距
        var maxAbs: CGFloat = minHalfSpan
        for g in guideValues { maxAbs = max(maxAbs, abs(g)) }
        for i in visibleStart..<visibleEnd where i < values.count {
            if let v = values[i] { maxAbs = max(maxAbs, abs(CGFloat(v))) }
        }
        let yScale = (size.height / 2) * 0.9 / max(0.0001, maxAbs)
        let yCenter = size.height / 2
        let yMap: (CGFloat) -> CGFloat = { yCenter - $0 * yScale }

        for g in guideValues {
            // 0 用 zeroLine（强）· 其他参考线用 guide（弱）· 与 KDJ/RSI 视觉档位对齐
            let lineColor = (g == 0) ? zeroLineColor : kdjGuideColor
            drawDashLine(at: yMap(g), ctx: ctx, width: size.width, color: lineColor)
        }

        drawLine(values, color: color, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// v15.11 WR：固定 -100~0 视野 · -20=超买 / -80=超卖 参考线（与 RSI 70/30 同语义但反向）
    private func drawWR(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.wrViewMin
        let viewMax = Self.wrViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(-20), -50, -80] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: rsiGuideColor)
        }

        drawLine(seriesA, color: Self.wrLineColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// v15.11 持仓量 OI：底部基线 0 · 顶部 visible max · 单色紫（期货特有 · 不分涨跌色 · 与 Volume 区分）
    private func drawOI(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        var maxOI: Double = 1.0
        for i in visibleStart..<visibleEnd where i < seriesA.count {
            if let v = seriesA[i], v > maxOI { maxOI = v }
        }
        let yScale = size.height * 0.9 / CGFloat(maxOI)
        let yBase = size.height

        drawDashLine(at: yBase - 1, ctx: ctx, width: size.width, color: volumeAxisColor)

        for i in visibleStart..<visibleEnd {
            guard i < seriesA.count, let v = seriesA[i] else { continue }
            let value = CGFloat(v)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let height = value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: yBase - height,
                width: barWidth * 0.6,
                height: height
            )
            ctx.fill(Path(rect), with: .color(Self.oiBarColor))
        }
    }

    /// v15.13 DMI：双线 +DI/-DI · visible 内自动撑开（DI 多在 0-50 区间但视野跟随实际值）· 0 参考线（DI 都 ≥0）
    private func drawDMI(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        // 同 RSI 0~100 视野（DI 通常 ≤ 50 但 0~100 留够余量 · 与可对比指标视觉对齐）
        let viewMin = Self.rsiViewMin
        let viewMax = Self.rsiViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        // 25 ADX 阈值参考线（DMI 经典强弱分界 · 弱档）
        for guide in [CGFloat(50), 25] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: kdjGuideColor)
        }

        drawLine(seriesA, color: Self.dmiPlusColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.dmiMinusColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// v15.13 Stochastic：%K/%D 双线 · 固定 0~100 视野（同 KDJ 但更窄 · KDJ 视野 -20~120 给 J）· 80/50/20 参考
    private func drawStoch(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.stochViewMin
        let viewMax = Self.stochViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(80), 50, 20] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: kdjGuideColor)
        }

        drawLine(seriesA, color: Self.stochKColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.stochDColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// MACD：上下对称 · 零轴居中 · 直方图（涨红跌绿）+ DIF/DEA 双线
    private func drawMACD(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        // y 范围：visible 内 |DIF/DEA/柱| 最大值 · 上下对称 · 留 10% 边距
        var maxAbs: Double = 0.01
        for i in visibleStart..<visibleEnd {
            for arr in [seriesA, seriesB, seriesC] {
                if i < arr.count, let v = arr[i], abs(v) > maxAbs {
                    maxAbs = abs(v)
                }
            }
        }
        let yScale = (size.height / 2) * 0.9 / CGFloat(maxAbs)
        let yCenter = size.height / 2
        let yMap: (CGFloat) -> CGFloat = { yCenter - $0 * yScale }

        drawDashLine(at: yCenter, ctx: ctx, width: size.width, color: zeroLineColor)

        // 直方图（涨红跌绿）
        for i in visibleStart..<visibleEnd {
            guard i < seriesC.count, let v = seriesC[i] else { continue }
            let value = CGFloat(v)
            let xCenter = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let yTop = yCenter - value * yScale
            let rect = CGRect(
                x: xCenter - barWidth * 0.3,
                y: min(yTop, yCenter),
                width: barWidth * 0.6,
                height: abs(yTop - yCenter)
            )
            ctx.fill(Path(rect),
                     with: .color(value >= 0 ? Self.macdBullColor : Self.macdBearColor))
        }

        drawLine(seriesA, color: Self.macdDifColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.macdDeaColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// KDJ：固定 -20~120 视野（80/50/20 参考线 · 超买/中位/超卖）· K/D/J 三线
    private func drawKDJ(
        _ ctx: GraphicsContext, size: CGSize,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        let viewMin = Self.kdjViewMin
        let viewMax = Self.kdjViewMax
        let span = viewMax - viewMin
        let h = size.height
        let yMap: (CGFloat) -> CGFloat = { v in h * (viewMax - v) / span }

        for guide in [CGFloat(80), 50, 20] {
            drawDashLine(at: yMap(guide), ctx: ctx, width: size.width, color: kdjGuideColor)
        }

        drawLine(seriesA, color: Self.kdjKColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesB, color: Self.kdjDColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
        drawLine(seriesC, color: Self.kdjJColor, ctx: ctx, yMap: yMap,
                 visibleStart: visibleStart, visibleEnd: visibleEnd,
                 barWidth: barWidth, xOffset: xOffset)
    }

    /// 通用虚线（零轴 / 参考线 共用）
    private func drawDashLine(at y: CGFloat, ctx: GraphicsContext, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// 通用折线（MACD/KDJ 共用）· yMap 把指标值映射到屏幕 y 坐标
    private func drawLine(
        _ values: [Double?], color: Color, ctx: GraphicsContext,
        yMap: (CGFloat) -> CGFloat,
        visibleStart: Int, visibleEnd: Int,
        barWidth: CGFloat, xOffset: CGFloat
    ) {
        var path = Path()
        var moved = false
        for i in visibleStart..<visibleEnd {
            guard i < values.count, let v = values[i] else { continue }
            let value = CGFloat(v)
            let x = (CGFloat(i - visibleStart) + 0.5 - xOffset) * barWidth
            let y = yMap(value)
            if !moved {
                path.move(to: CGPoint(x: x, y: y))
                moved = true
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
    }

    // MARK: - 工具

    /// visible window 末位最近一个非 nil 值（反向 stride · 不分配中间数组）
    private func lastValue(_ values: [Double?], at end: Int) -> Double? {
        guard end >= 0, !values.isEmpty else { return nil }
        let safeEnd = min(end, values.count - 1)
        for i in stride(from: safeEnd, through: 0, by: -1) {
            if let v = values[i] { return v }
        }
        return nil
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f", v)
    }

    /// 成交量格式：≥1M 用 M / ≥1K 用 K · 与 Watchlist openInterestText 风格一致
    private func fmtVolume(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(Int(v))
    }
}

#endif
